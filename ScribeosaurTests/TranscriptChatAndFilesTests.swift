import Foundation
import XCTest
@testable import Scribeosaur

final class TranscriptChatAndFilesTests: XCTestCase {
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

    func testChatMessagesPersistAndClearPerTranscript() throws {
        let repository = try makeRepository()
        let transcript = try saveTranscript(repository: repository)
        let transcriptID = try XCTUnwrap(transcript.id)

        var userMessage = TranscriptChatMessage(
            id: nil,
            transcriptId: transcriptID,
            role: .user,
            content: "What were the key points?",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        var assistantMessage = TranscriptChatMessage(
            id: nil,
            transcriptId: transcriptID,
            role: .assistant,
            content: "The transcript covered local AI and markdown files.",
            createdAt: Date(timeIntervalSince1970: 2)
        )

        try repository.saveChatMessage(&userMessage)
        try repository.saveChatMessage(&assistantMessage)

        let savedMessages = try repository.fetchChatMessages(transcriptId: transcriptID)
        XCTAssertEqual(savedMessages.map(\.role), [.user, .assistant])
        XCTAssertEqual(savedMessages.map(\.content), [
            "What were the key points?",
            "The transcript covered local AI and markdown files.",
        ])

        try repository.deleteChatMessages(transcriptId: transcriptID)
        XCTAssertTrue(try repository.fetchChatMessages(transcriptId: transcriptID).isEmpty)
    }

    func testMarkdownStorageWritesUniqueFilesAndReportsMissingFiles() throws {
        let repository = try makeRepository()
        let transcript = try saveTranscript(repository: repository)
        let transcriptID = try XCTUnwrap(transcript.id)

        let first = try TranscriptMarkdownFileStorage.writeMarkdown(
            title: "Plan / Summary: Notes",
            content: "## Notes\n\nFirst",
            transcriptID: transcriptID
        )
        let second = try TranscriptMarkdownFileStorage.writeMarkdown(
            title: "Plan / Summary: Notes",
            content: "## Notes\n\nSecond",
            transcriptID: transcriptID
        )

        XCTAssertNotEqual(first.fileName, second.fileName)
        XCTAssertFalse(first.fileName.contains("/"))
        XCTAssertFalse(first.fileName.contains(":"))
        XCTAssertEqual(try String(contentsOf: first.url, encoding: .utf8), "## Notes\n\nFirst")

        var file = TranscriptMarkdownFile(
            id: nil,
            transcriptId: transcriptID,
            title: "Notes",
            fileName: first.fileName,
            sourcePrompt: "Create notes",
            legacyAIResultId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try repository.insertMarkdownFile(&file)
        XCTAssertTrue(TranscriptMarkdownFileStorage.exists(file))

        try FileManager.default.removeItem(at: first.url)
        XCTAssertFalse(TranscriptMarkdownFileStorage.exists(file))
        XCTAssertThrowsError(try TranscriptMarkdownFileStorage.read(file))
    }

    func testMarkdownMetadataCascadesWhenTranscriptIsDeleted() throws {
        let repository = try makeRepository()
        let transcript = try saveTranscript(repository: repository)
        let transcriptID = try XCTUnwrap(transcript.id)

        var file = TranscriptMarkdownFile(
            id: nil,
            transcriptId: transcriptID,
            title: "Summary",
            fileName: "Summary.md",
            sourcePrompt: nil,
            legacyAIResultId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try repository.insertMarkdownFile(&file)

        try repository.delete(id: transcriptID)

        XCTAssertTrue(try repository.fetchMarkdownFiles(transcriptId: transcriptID).isEmpty)
    }

    func testLegacyAIResultsMaterializeOnceAsMarkdownFiles() throws {
        let repository = try makeRepository()
        var transcript = try saveTranscript(repository: repository)
        let transcriptID = try XCTUnwrap(transcript.id)

        var aiResult = TranscriptAIResult(
            id: nil,
            transcriptId: transcriptID,
            promptID: AIPromptTemplate.summary.id,
            promptTitle: AIPromptTemplate.summary.title,
            promptBody: AIPromptTemplate.summary.body,
            content: "## Summary\n\n- Existing AI result",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        try repository.saveAIResult(&aiResult)

        let created = try TranscriptMarkdownFileMaterializer.materializeLegacyAIResults(
            transcript: transcript,
            repository: repository
        )
        let repeated = try TranscriptMarkdownFileMaterializer.materializeLegacyAIResults(
            transcript: transcript,
            repository: repository
        )

        XCTAssertEqual(created.count, 1)
        XCTAssertTrue(repeated.isEmpty)
        XCTAssertEqual(try repository.fetchMarkdownFiles(transcriptId: transcriptID).count, 1)
        XCTAssertEqual(created.first?.legacyAIResultId, aiResult.id)

        let content = try TranscriptMarkdownFileStorage.read(try XCTUnwrap(created.first))
        XCTAssertTrue(content.contains("# Transcript Chat Test - Summary"))
        XCTAssertTrue(content.contains("- Existing AI result"))
    }

    func testChatIntentDetectorFindsMarkdownCreationRequests() {
        XCTAssertTrue(
            TranscriptChatIntentDetector.shouldCreateMarkdownFile(
                for: "Please create a markdown summary from this transcript."
            )
        )
        XCTAssertTrue(
            TranscriptChatIntentDetector.shouldCreateMarkdownFile(
                for: "Draft a checklist for the launch."
            )
        )
        XCTAssertFalse(
            TranscriptChatIntentDetector.shouldCreateMarkdownFile(
                for: "What did they say about the launch?"
            )
        )
        XCTAssertFalse(
            TranscriptChatIntentDetector.shouldCreateMarkdownFile(
                for: "Can you summarize what they said about the launch?"
            )
        )
    }

    func testChatIntentDetectorReturnsLocalRepliesForSimpleConversation() {
        let greeting = TranscriptChatIntentDetector.localAssistantReply(for: "Hello?")
        XCTAssertNotNil(greeting)
        XCTAssertTrue(greeting?.contains("Ask me anything about this transcript") == true)

        let thanks = TranscriptChatIntentDetector.localAssistantReply(for: "thanks")
        XCTAssertNotNil(thanks)
        XCTAssertTrue(thanks?.contains("You're welcome") == true)

        let capabilities = TranscriptChatIntentDetector.localAssistantReply(for: "What can you do?")
        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities?.contains("answer questions about this transcript") == true)

        XCTAssertNil(
            TranscriptChatIntentDetector.localAssistantReply(
                for: "What did they say about the launch?"
            )
        )
        XCTAssertNil(
            TranscriptChatIntentDetector.localAssistantReply(
                for: "Hello, what did they say about the launch?"
            )
        )
    }

    private func makeRepository() throws -> TranscriptRepository {
        let databaseManager = try DatabaseManager()
        return TranscriptRepository(dbQueue: databaseManager.dbQueue)
    }

    private func saveTranscript(repository: TranscriptRepository) throws -> Transcript {
        var transcript = Transcript(
            id: nil,
            title: "Transcript Chat Test",
            sourceType: .url,
            sourcePath: "https://example.com/video",
            remoteSource: .youtube,
            createdAt: Date(timeIntervalSince1970: 1_712_700_000),
            durationSeconds: 42,
            speakerDetection: false,
            speakerCount: 0,
            fullText: "The transcript body",
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
            speakerName: nil,
            text: "The speaker discusses local AI chat and generated markdown files.",
            startTime: 0,
            endTime: 5,
            sortOrder: 0
        )

        try repository.save(&transcript, segments: [segment])
        return transcript
    }
}
