import GRDB
import XCTest
@testable import Scribeosaur

class StorageIsolatedTestCase: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        StoragePaths.setAppSupportOverride(tempRoot.appendingPathComponent("ApplicationSupport"))
        StoragePaths.setBundledResourceRootOverride(nil)
        ThumbnailCache.resetSharedForTesting()
    }

    override func tearDownWithError() throws {
        AppLogger.flush()
        ThumbnailCache.resetSharedForTesting()
        StoragePaths.setAppSupportOverride(nil)
        StoragePaths.setBundledResourceRootOverride(nil)

        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }
}

final class QueueManagerTests: StorageIsolatedTestCase {
    func testSuspendPreventsProcessingUntilResume() throws {
        let repo = TranscriptRepository(dbQueue: try DatabaseQueue())
        let pipeline = AudioPipelineService(
            transcriptionService: TranscriptionService(),
            diarizationService: DiarizationService(),
            repository: repo,
            settings: AppSettings()
        )
        let queueManager = QueueManager(pipeline: pipeline)
        let item = QueueItem(
            title: "Example",
            sourceURL: tempRoot.appendingPathComponent("example.wav"),
            sourceType: .file
        )

        queueManager.suspend()
        queueManager.enqueue(item)

        XCTAssertTrue(queueManager.isSuspended)
        XCTAssertFalse(queueManager.isProcessing)

        queueManager.resume()

        XCTAssertFalse(queueManager.isSuspended)
        XCTAssertTrue(queueManager.isProcessing)

        // Re-suspend immediately so the async processing task can observe the flag
        // before it starts the real audio pipeline.
        queueManager.suspend()
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
}

final class YTDLPInvocationTests: StorageIsolatedTestCase {
    func testMetadataRequestUsesManagedHelpersAndLongerTimeout() {
        let request = YTDLPInvocation.makeRequest(
            for: .metadata(url: "https://www.youtube.com/watch?v=abc12345678"),
            environment: ["PATH": "/usr/bin"]
        )

        XCTAssertEqual(request.timeout, 90)
        XCTAssertTrue(request.arguments.contains("--dump-single-json"))
        XCTAssertTrue(request.arguments.contains("--ffmpeg-location"))
        XCTAssertTrue(request.arguments.contains(StoragePaths.bin.path))
        XCTAssertTrue(request.arguments.contains("--js-runtimes"))
        XCTAssertTrue(request.arguments.contains("deno:\(StoragePaths.denoBinary.path)"))
        XCTAssertEqual(request.environment["PATH"], "\(StoragePaths.bin.path):/usr/bin")
    }

    func testTitleAndDownloadRequestsReuseManagedRuntimeConfiguration() {
        let titleRequest = YTDLPInvocation.makeRequest(for: .title(url: "https://youtu.be/abc12345678"))
        let downloadRequest = YTDLPInvocation.makeRequest(
            for: .downloadAudio(
                url: "https://youtu.be/abc12345678",
                outputTemplate: "/tmp/output.%(ext)s"
            )
        )

        XCTAssertEqual(titleRequest.timeout, 90)
        XCTAssertTrue(titleRequest.arguments.contains("--get-title"))
        XCTAssertTrue(titleRequest.arguments.contains("deno:\(StoragePaths.denoBinary.path)"))

        XCTAssertNil(downloadRequest.timeout)
        XCTAssertTrue(downloadRequest.arguments.contains("-x"))
        XCTAssertTrue(downloadRequest.arguments.contains("--newline"))
        XCTAssertTrue(downloadRequest.arguments.contains("deno:\(StoragePaths.denoBinary.path)"))
        XCTAssertTrue(downloadRequest.arguments.contains(StoragePaths.bin.path))
    }
}

final class URLResolutionCoordinatorTests: XCTestCase {
    func testNormalizedURLStringSortsQueryItemsAndRemovesFragments() {
        let normalized = URLResolutionCoordinator.normalizedURLString(
            from: "HTTPS://YouTube.com/watch?v=abc12345678&list=playlist#fragment"
        )

        XCTAssertEqual(normalized, "https://youtube.com/watch?list=playlist&v=abc12345678")
    }

    func testResolveDeduplicatesMatchingURLs() async throws {
        let coordinator = URLResolutionCoordinator()
        let probe = ResolutionProbe()
        let expected = [makeResolvedItem(url: "https://www.youtube.com/watch?v=abc12345678")]

        let first = Task {
            try await coordinator.resolve(normalizedURL: "https://youtube.com/watch?v=abc12345678") {
                await probe.recordStart("same")
                try await Task.sleep(for: .milliseconds(100))
                return expected
            }
        }

        let second = Task {
            try await coordinator.resolve(normalizedURL: "https://youtube.com/watch?v=abc12345678") {
                XCTFail("Expected duplicate URL resolution to reuse the in-flight task")
                return []
            }
        }

        let firstResult = try await first.value
        let secondResult = try await second.value
        let startCount = await probe.startCount

        XCTAssertEqual(firstResult, expected)
        XCTAssertEqual(secondResult, expected)
        XCTAssertEqual(startCount, 1)
    }

    func testResolveSerializesDifferentURLs() async throws {
        let coordinator = URLResolutionCoordinator()
        let probe = ResolutionProbe()

        let first = Task {
            try await coordinator.resolve(normalizedURL: "https://youtube.com/watch?v=first12345") { [self] in
                await probe.begin("first")
                try await Task.sleep(for: .milliseconds(100))
                await probe.end("first")
                return [self.makeResolvedItem(url: "https://www.youtube.com/watch?v=first12345")]
            }
        }

        let second = Task {
            try await coordinator.resolve(normalizedURL: "https://youtube.com/watch?v=second1234") { [self] in
                await probe.begin("second")
                await probe.end("second")
                return [self.makeResolvedItem(url: "https://www.youtube.com/watch?v=second1234")]
            }
        }

        _ = try await (first.value, second.value)
        let maxActiveCount = await probe.maxActiveCount
        let events = await probe.events

        XCTAssertEqual(maxActiveCount, 1)
        XCTAssertEqual(events.count, 4)
        XCTAssertTrue(events[0].hasPrefix("start:"))
        XCTAssertTrue(events[1].hasPrefix("end:"))
        XCTAssertTrue(events[2].hasPrefix("start:"))
        XCTAssertTrue(events[3].hasPrefix("end:"))
        XCTAssertEqual(String(events[0].dropFirst("start:".count)), String(events[1].dropFirst("end:".count)))
        XCTAssertEqual(String(events[2].dropFirst("start:".count)), String(events[3].dropFirst("end:".count)))
        XCTAssertNotEqual(events[0], events[2])
    }

    private func makeResolvedItem(url: String) -> ResolvedRemoteQueueItem {
        ResolvedRemoteQueueItem(
            title: url,
            sourceURL: URL(string: url)!,
            sourceType: .url,
            remoteSource: .youtube,
            collectionID: nil,
            collectionTitle: nil,
            collectionType: nil,
            collectionItemIndex: nil,
            thumbnailURL: nil,
            speakerDetection: false,
            speakerNames: []
        )
    }
}

private actor ResolutionProbe {
    private(set) var startCount = 0
    private(set) var activeCount = 0
    private(set) var maxActiveCount = 0
    private(set) var events: [String] = []

    func recordStart(_ label: String) {
        startCount += 1
        events.append("start:\(label)")
    }

    func begin(_ label: String) {
        startCount += 1
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        events.append("start:\(label)")
    }

    func end(_ label: String) {
        events.append("end:\(label)")
        activeCount -= 1
    }
}
