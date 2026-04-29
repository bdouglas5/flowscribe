import Foundation
import XCTest
@testable import Scribeosaur

@MainActor
final class TranscriptContextPreparerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        StoragePaths.setAppSupportOverride(tempRoot.appendingPathComponent("ApplicationSupport"))
        StoragePaths.setBundledResourceRootOverride(nil)
    }

    override func tearDownWithError() throws {
        AppLogger.flush()
        StoragePaths.setAppSupportOverride(nil)
        StoragePaths.setBundledResourceRootOverride(nil)

        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testPrepareBuildsReadyCacheWithOrderedChunksAndPreparedPayload() async throws {
        let repository = try makeRepository()
        let transcript = try saveTranscript(
            repository: repository,
            text: "First point.\n\nSecond point."
        )
        let transcriptID = try XCTUnwrap(transcript.id)
        let segments = try repository.fetchSegments(transcriptId: transcriptID)
        let preparer = TranscriptContextPreparer(repository: repository)

        await preparer.prepareIfNeeded(
            transcript: transcript,
            segments: segments,
            waitForUserAI: false
        )

        let stored = try XCTUnwrap(repository.fetchContextCacheWithChunks(transcriptId: transcriptID))
        XCTAssertEqual(stored.cache.status, .ready)
        XCTAssertEqual(stored.cache.contentHash, TranscriptContextPreparer.contentHash(for: stored.cache.normalizedText))
        XCTAssertEqual(stored.chunks.map(\.sortOrder), Array(stored.chunks.indices))
        XCTAssertTrue(stored.chunks.first?.content.contains("First point") == true)

        let prepared = try XCTUnwrap(try preparer.preparedContext(transcript: transcript, segments: segments))
        XCTAssertEqual(prepared.transcriptId, transcriptID)
        XCTAssertEqual(prepared.contentHash, stored.cache.contentHash)
        XCTAssertEqual(prepared.chunks.map(\.summary), stored.chunks.map(\.summary))
    }

    func testPreparedContextReturnsNilWhenTranscriptTextChanges() async throws {
        let repository = try makeRepository()
        let transcript = try saveTranscript(repository: repository, text: "Original transcript text.")
        let transcriptID = try XCTUnwrap(transcript.id)
        let segments = try repository.fetchSegments(transcriptId: transcriptID)
        let preparer = TranscriptContextPreparer(repository: repository)

        await preparer.prepareIfNeeded(
            transcript: transcript,
            segments: segments,
            waitForUserAI: false
        )

        let changedSegments = [
            TranscriptSegment(
                id: 999,
                transcriptId: transcriptID,
                speakerId: nil,
                speakerName: nil,
                text: "Changed transcript text.",
                startTime: 0,
                endTime: 1,
                sortOrder: 0
            ),
        ]

        XCTAssertNil(try preparer.preparedContext(transcript: transcript, segments: changedSegments))
    }

    func testContextCacheCascadesWhenTranscriptIsDeleted() async throws {
        let repository = try makeRepository()
        let transcript = try saveTranscript(repository: repository, text: "Cascade text.")
        let transcriptID = try XCTUnwrap(transcript.id)
        let segments = try repository.fetchSegments(transcriptId: transcriptID)
        let preparer = TranscriptContextPreparer(repository: repository)

        await preparer.prepareIfNeeded(
            transcript: transcript,
            segments: segments,
            waitForUserAI: false
        )
        XCTAssertNotNil(try repository.fetchContextCache(transcriptId: transcriptID))

        try repository.delete(id: transcriptID)

        XCTAssertNil(try repository.fetchContextCache(transcriptId: transcriptID))
    }

    func testFailedCacheRetriesToReady() async throws {
        let repository = try makeRepository()
        let transcript = try saveTranscript(repository: repository, text: "Retry context text.")
        let transcriptID = try XCTUnwrap(transcript.id)
        let segments = try repository.fetchSegments(transcriptId: transcriptID)
        let normalizedText = TranscriptContextPreparer.normalizedTranscriptText(
            from: transcript,
            segments: segments
        )
        let hash = TranscriptContextPreparer.contentHash(for: normalizedText)
        var failed = TranscriptContextCache(
            id: nil,
            transcriptId: transcriptID,
            contentHash: hash,
            status: .failed,
            normalizedText: normalizedText,
            memorySummary: "",
            errorMessage: "Prior failure",
            createdAt: Date(),
            updatedAt: Date()
        )
        try repository.replaceContextCache(&failed, chunks: [])

        let preparer = TranscriptContextPreparer(repository: repository)
        await preparer.prepareIfNeeded(
            transcript: transcript,
            segments: segments,
            waitForUserAI: false
        )

        let cache = try XCTUnwrap(repository.fetchContextCache(transcriptId: transcriptID))
        XCTAssertEqual(cache.status, .ready)
        XCTAssertNil(cache.errorMessage)
    }

    func testBusyUserAIWaitsBeforePreparing() async throws {
        let repository = try makeRepository()
        let transcript = try saveTranscript(repository: repository, text: "Deferred context text.")
        let transcriptID = try XCTUnwrap(transcript.id)
        let segments = try repository.fetchSegments(transcriptId: transcriptID)
        var isBusy = true
        let preparer = TranscriptContextPreparer(
            repository: repository,
            busyRetryDelay: .milliseconds(20)
        ) {
            isBusy
        }

        let task = Task { @MainActor in
            await preparer.prepareIfNeeded(
                transcript: transcript,
                segments: segments,
                waitForUserAI: true
            )
        }

        try await Task.sleep(for: .milliseconds(40))
        XCTAssertNil(try repository.fetchContextCache(transcriptId: transcriptID))

        isBusy = false
        await task.value

        XCTAssertEqual(try repository.fetchContextCache(transcriptId: transcriptID)?.status, .ready)
    }

    private func makeRepository() throws -> TranscriptRepository {
        let databaseManager = try DatabaseManager()
        return TranscriptRepository(dbQueue: databaseManager.dbQueue)
    }

    private func saveTranscript(repository: TranscriptRepository, text: String) throws -> Transcript {
        var transcript = Transcript(
            id: nil,
            title: "Context Test",
            sourceType: .url,
            sourcePath: "https://example.com/video",
            remoteSource: .youtube,
            createdAt: Date(timeIntervalSince1970: 1_712_700_000),
            durationSeconds: 42,
            speakerDetection: false,
            speakerCount: 0,
            fullText: text,
            status: .completed,
            errorMessage: nil,
            thumbnailURL: nil,
            collectionID: nil,
            collectionTitle: nil,
            collectionType: nil,
            collectionItemIndex: nil
        )

        let segment = TranscriptSegment(
            id: nil,
            transcriptId: 0,
            speakerId: nil,
            speakerName: "Speaker",
            text: text,
            startTime: 0,
            endTime: 5,
            sortOrder: 0
        )

        try repository.save(&transcript, segments: [segment])
        return transcript
    }
}
