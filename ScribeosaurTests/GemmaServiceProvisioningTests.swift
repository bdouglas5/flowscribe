import CryptoKit
import Foundation
import XCTest
@testable import Scribeosaur

@MainActor
final class GemmaServiceProvisioningTests: XCTestCase {
    private var tempRoot: URL!
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        StoragePaths.setAppSupportOverride(tempRoot.appendingPathComponent("ApplicationSupport"))
        StoragePaths.setBundledResourceRootOverride(nil)
        ThumbnailCache.resetSharedForTesting()

        defaultsSuiteName = "GemmaServiceProvisioningTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        AppLogger.flush()
        ThumbnailCache.resetSharedForTesting()
        StoragePaths.setAppSupportOverride(nil)
        StoragePaths.setBundledResourceRootOverride(nil)

        if let defaultsSuiteName {
            defaults?.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil

        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testProvisioningFailureLogsChecksumMismatchAndRemovesPartialFile() async throws {
        let expectedData = Data("good-data".utf8)
        let actualData = Data("bad-data!".utf8)
        let descriptor = makeDescriptor(modelID: "checksum-model", assets: [
            AssetFixture(path: "README.md", expectedData: expectedData)
        ])
        let downloader = FakeDownloader(assetDataByPath: ["README.md": actualData])
        let service = makeService(descriptor: descriptor, downloader: downloader)

        do {
            try await service.provisionSelectedModelFilesIfNeeded()
            XCTFail("Expected checksum mismatch")
        } catch {
            guard case LocalAIProvisioningError.checksumMismatch(let assetPath, _, _) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(assetPath, "README.md")
            XCTAssertEqual(error.localizedDescription, "Checksum verification failed for README.md.")
        }

        let partialURL = StoragePaths.modelDirectory(for: descriptor.id)
            .appendingPathComponent("README.md.part")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        XCTAssertEqual(service.modelState, .failed)
        XCTAssertEqual(service.lastError, "Checksum verification failed for README.md.")

        AppLogger.flush()
        let logContents = try String(contentsOf: StoragePaths.logFile)
        XCTAssertTrue(logContents.contains("[LocalAIProvisioning]"))
        XCTAssertTrue(logContents.contains("Checksum mismatch"))
        XCTAssertTrue(logContents.contains("asset=README.md"))
        XCTAssertFalse(logContents.contains("Process exited with code 0"))
    }

    func testProvisioningSkipsAlreadyVerifiedCachedAssetsOnRetry() async throws {
        let first = AssetFixture(path: "README.md", expectedData: Data("cached-data".utf8))
        let second = AssetFixture(path: "tokenizer.json", expectedData: Data("fresh-data".utf8))
        let descriptor = makeDescriptor(modelID: "cached-model", assets: [first, second])
        let modelDirectory = StoragePaths.modelDirectory(for: descriptor.id)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try first.expectedData.write(to: modelDirectory.appendingPathComponent(first.path))

        let downloader = FakeDownloader(assetDataByPath: [second.path: second.expectedData])
        let service = makeService(descriptor: descriptor, downloader: downloader)

        try await service.provisionSelectedModelFilesIfNeeded()

        XCTAssertEqual(downloader.downloadedAssetPaths, [second.path])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: StoragePaths.modelVerificationFile(for: descriptor.id).path
            )
        )
    }

    func testBundledSeedFailureFallsBackToRemoteDownload() async throws {
        let remoteAsset = AssetFixture(path: "README.md", expectedData: Data("remote-good".utf8))
        let descriptor = makeDescriptor(modelID: "seed-model", assets: [remoteAsset])
        let bundleSeedDirectory = tempRoot
            .appendingPathComponent("BundleRoot")
            .appendingPathComponent("ModelSeed")
            .appendingPathComponent(descriptor.id)
        try FileManager.default.createDirectory(at: bundleSeedDirectory, withIntermediateDirectories: true)
        try Data("stale-seed!".utf8).write(to: bundleSeedDirectory.appendingPathComponent(remoteAsset.path))

        let downloader = FakeDownloader(assetDataByPath: [remoteAsset.path: remoteAsset.expectedData])
        let service = makeService(
            descriptor: descriptor,
            downloader: downloader,
            bundledSeedDirectoryProvider: { _ in bundleSeedDirectory }
        )

        try await service.provisionSelectedModelFilesIfNeeded()

        XCTAssertEqual(downloader.downloadedAssetPaths, [remoteAsset.path])
        let installedData = try Data(
            contentsOf: StoragePaths.modelDirectory(for: descriptor.id).appendingPathComponent(remoteAsset.path)
        )
        XCTAssertEqual(installedData, remoteAsset.expectedData)

        AppLogger.flush()
        let logContents = try String(contentsOf: StoragePaths.logFile)
        XCTAssertTrue(logContents.contains("Bundled seed invalid"))
    }

    func testConcurrentProvisionRequestsReuseSingleFlightTask() async throws {
        let asset = AssetFixture(path: "README.md", expectedData: Data("shared-download".utf8))
        let descriptor = makeDescriptor(modelID: "single-flight-model", assets: [asset])
        let downloader = ScriptedDownloader(stepsByPath: [
            asset.path: [.overwrite(asset.expectedData, delayNanoseconds: 200_000_000)]
        ])
        let service = makeService(descriptor: descriptor, downloader: downloader)

        let first = Task { @MainActor in
            try await service.provisionSelectedModelFilesIfNeeded()
        }
        await Task.yield()
        let second = Task { @MainActor in
            try await service.provisionSelectedModelFilesIfNeeded()
        }

        _ = try await (first.value, second.value)
        let callCount = await downloader.callCount(for: asset.path)

        XCTAssertEqual(callCount, 1)

        AppLogger.flush()
        let logContents = try String(contentsOf: StoragePaths.logFile)
        XCTAssertTrue(logContents.contains("Joining active provisioning"))
    }

    func testProvisioningRetriesAfterCurl18AndResumesPartialDownload() async throws {
        let fullData = Data("resumable-download".utf8)
        let prefix = fullData.prefix(9)
        let suffix = fullData.dropFirst(prefix.count)
        let asset = AssetFixture(path: "README.md", expectedData: fullData)
        let descriptor = makeDescriptor(modelID: "curl18-model", assets: [asset])
        let downloader = ScriptedDownloader(stepsByPath: [
            asset.path: [
                .overwriteAndFail(Data(prefix), code: 18),
                .append(Data(suffix))
            ]
        ])
        let service = makeService(descriptor: descriptor, downloader: downloader)

        try await service.provisionSelectedModelFilesIfNeeded()
        let callCount = await downloader.callCount(for: asset.path)
        let existingSizes = await downloader.observedExistingSizes(for: asset.path)

        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(existingSizes, [0, Int64(prefix.count)])

        let finalURL = StoragePaths.modelDirectory(for: descriptor.id).appendingPathComponent(asset.path)
        let finalData = try Data(contentsOf: finalURL)
        XCTAssertEqual(finalData, fullData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalURL.appendingPathExtension("part").path))

        AppLogger.flush()
        let logContents = try String(contentsOf: StoragePaths.logFile)
        XCTAssertTrue(logContents.contains("Retrying partial asset download"))
        XCTAssertTrue(logContents.contains("Resuming asset download"))
    }

    func testProvisioningRetriesShortDownloadWithoutDeletingPartialBytes() async throws {
        let fullData = Data("short-then-resume".utf8)
        let prefix = fullData.prefix(5)
        let suffix = fullData.dropFirst(prefix.count)
        let asset = AssetFixture(path: "README.md", expectedData: fullData)
        let descriptor = makeDescriptor(modelID: "short-transfer-model", assets: [asset])
        let downloader = ScriptedDownloader(stepsByPath: [
            asset.path: [
                .overwrite(Data(prefix)),
                .append(Data(suffix))
            ]
        ])
        let service = makeService(descriptor: descriptor, downloader: downloader)

        try await service.provisionSelectedModelFilesIfNeeded()
        let callCount = await downloader.callCount(for: asset.path)
        let existingSizes = await downloader.observedExistingSizes(for: asset.path)

        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(existingSizes, [0, Int64(prefix.count)])

        let finalURL = StoragePaths.modelDirectory(for: descriptor.id).appendingPathComponent(asset.path)
        let finalData = try Data(contentsOf: finalURL)
        XCTAssertEqual(finalData, fullData)

        AppLogger.flush()
        let logContents = try String(contentsOf: StoragePaths.logFile)
        XCTAssertTrue(logContents.contains("Retrying short asset download"))
    }

    private func makeService(
        descriptor: AIModelDescriptor,
        downloader: any ModelAssetDownloading,
        bundledSeedDirectoryProvider: @escaping (String) -> URL? = { _ in nil }
    ) -> GemmaService {
        GemmaService(
            defaults: defaults,
            fileManager: .default,
            verifier: AIModelVerifier(),
            downloader: downloader,
            descriptorProvider: { _ in descriptor },
            catalogErrorProvider: { nil },
            bundledSeedDirectoryProvider: bundledSeedDirectoryProvider,
            runtimeClient: NoopLocalAIRuntimeClient()
        )
    }

    private func makeDescriptor(modelID: String, assets: [AssetFixture]) -> AIModelDescriptor {
        AIModelDescriptor(
            id: modelID,
            displayName: "Test Model",
            providerID: "provider/test",
            revision: "revision-1",
            estimatedDownloadSizeBytes: assets.reduce(0) { $0 + Int64($1.expectedData.count) },
            estimatedMemoryBytes: 0,
            notes: "Test descriptor",
            assetFiles: assets.map { fixture in
                AIModelAsset(
                    path: fixture.path,
                    sizeBytes: Int64(fixture.expectedData.count),
                    checksum: sha256(fixture.expectedData)
                )
            }
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct AssetFixture {
    let path: String
    let expectedData: Data
}

private final class FakeDownloader: ModelAssetDownloading {
    private let fileManager = FileManager.default
    private let assetDataByPath: [String: Data]
    private(set) var downloadedAssetPaths: [String] = []

    init(assetDataByPath: [String: Data]) {
        self.assetDataByPath = assetDataByPath
    }

    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let path = remoteURL.lastPathComponent
        downloadedAssetPaths.append(path)

        guard let data = assetDataByPath[path] else {
            throw SubprocessError.executionFailed("No fixture data for \(path)", 1)
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL)
        onProgress(Int64(data.count))
    }
}

private actor ScriptedDownloader: ModelAssetDownloading {
    enum Step {
        case overwrite(Data, delayNanoseconds: UInt64 = 0)
        case append(Data, delayNanoseconds: UInt64 = 0)
        case overwriteAndFail(Data, code: Int32, delayNanoseconds: UInt64 = 0)
    }

    private let fileManager = FileManager.default
    private var stepsByPath: [String: [Step]]
    private var callCounts: [String: Int] = [:]
    private var existingSizesByPath: [String: [Int64]] = [:]

    init(stepsByPath: [String: [Step]]) {
        self.stepsByPath = stepsByPath
    }

    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let path = remoteURL.lastPathComponent
        callCounts[path, default: 0] += 1
        existingSizesByPath[path, default: []].append(currentSize(of: destinationURL))

        guard var steps = stepsByPath[path], !steps.isEmpty else {
            throw SubprocessError.executionFailed("No scripted step for \(path)", 1)
        }

        let step = steps.removeFirst()
        stepsByPath[path] = steps
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        switch step {
        case .overwrite(let data, let delayNanoseconds):
            try await sleepIfNeeded(delayNanoseconds)
            try overwrite(data, to: destinationURL)
            onProgress(Int64(data.count))

        case .append(let data, let delayNanoseconds):
            try await sleepIfNeeded(delayNanoseconds)
            try append(data, to: destinationURL)
            onProgress(currentSize(of: destinationURL))

        case .overwriteAndFail(let data, let code, let delayNanoseconds):
            try await sleepIfNeeded(delayNanoseconds)
            try overwrite(data, to: destinationURL)
            onProgress(Int64(data.count))
            throw SubprocessError.executionFailed("Scripted curl failure", code)
        }
    }

    func callCount(for path: String) -> Int {
        callCounts[path, default: 0]
    }

    func observedExistingSizes(for path: String) -> [Int64] {
        existingSizesByPath[path, default: []]
    }

    private func sleepIfNeeded(_ nanoseconds: UInt64) async throws {
        guard nanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private func overwrite(_ data: Data, to url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try data.write(to: url)
    }

    private func append(_ data: Data, to url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try data.write(to: url)
            return
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func currentSize(of url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

@MainActor
private final class NoopLocalAIRuntimeClient: LocalAIRuntimeClient {
    var loadedModelID: String?

    func runtimeLooksInstalled() -> Bool { true }
    func runtimeNeedsPreparation() async -> Bool { false }
    func ensureRuntimeReady() async throws {}
    func loadModel(at modelDirectory: URL, modelID: String) async throws {
        loadedModelID = modelID
    }
    func streamGenerate(
        messages: [LocalAIChatMessage],
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        ""
    }
    func cancelGeneration() {}
    func unloadModel() async { loadedModelID = nil }
    func healthCheck() async throws {}
}
