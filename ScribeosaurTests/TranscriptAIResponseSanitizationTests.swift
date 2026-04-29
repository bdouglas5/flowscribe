import Foundation
import XCTest
@testable import Scribeosaur

@MainActor
final class TranscriptAIResponseSanitizationTests: XCTestCase {
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

        defaultsSuiteName = "TranscriptAIResponseSanitizationTests.\(UUID().uuidString)"
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

    func testSanitizeModelResponseStripsThoughtBlock() {
        let response = """
        <|channel>thought
        1. Inspect transcript
        2. Draft summary
        <channel|>## Summary
        - Fast local Gemma summaries
        """

        let sanitized = TranscriptAIUtilities.sanitizeModelResponse(response)

        XCTAssertEqual(
            sanitized,
            """
            ## Summary
            - Fast local Gemma summaries
            """
        )
    }

    func testSanitizeModelResponseStripsEmptyThoughtWrapper() {
        let response = """
        <|channel>thought
        <channel|>## Summary
        - Clean output
        """

        let sanitized = TranscriptAIUtilities.sanitizeModelResponse(response)

        XCTAssertEqual(
            sanitized,
            """
            ## Summary
            - Clean output
            """
        )
    }

    func testSanitizeModelResponseLeavesCleanMarkdownUntouched() {
        let response = """
        ## Summary
        - Already clean
        """

        XCTAssertEqual(
            TranscriptAIUtilities.sanitizeModelResponse(response),
            response
        )
    }

    func testSanitizeModelResponsePreservesMalformedWrapperWhenClosingTokenMissing() {
        let response = """
          <|channel>thought
        incomplete reasoning block without a closing token
        """

        XCTAssertEqual(
            TranscriptAIUtilities.sanitizeModelResponse(response),
            """
            <|channel>thought
            incomplete reasoning block without a closing token
            """
        )
    }

    func testRunTranscriptTaskReturnsSanitizedMarkdown() async throws {
        let descriptor = makeDescriptor(modelID: "sanitized-runtime-model")
        let runtimeClient = SanitizingFakeLocalAIRuntimeClient()
        runtimeClient.loadedModelID = descriptor.id
        runtimeClient.streamGenerateResponse = """
        <|channel>thought
        Build a summary from the transcript.
        <channel|>## Summary
        - The final answer is clean
        """

        let service = makeService(descriptor: descriptor, runtimeClient: runtimeClient)
        let result = try await service.runTranscriptTask(
            .summary,
            transcript: makeTranscript(),
            segments: [makeSegment()]
        )

        XCTAssertEqual(
            result,
            """
            ## Summary
            - The final answer is clean
            """
        )
        XCTAssertEqual(runtimeClient.streamGenerateCalls, 1)
        XCTAssertFalse(result.contains("<|channel>thought"))
        XCTAssertFalse(result.contains("<channel|>"))
    }

    func testStreamTranscriptChatBuildsPromptWithHistoryAndQuestion() async throws {
        let descriptor = makeDescriptor(modelID: "chat-runtime-model")
        let runtimeClient = SanitizingFakeLocalAIRuntimeClient()
        runtimeClient.loadedModelID = descriptor.id
        runtimeClient.streamGenerateResponse = "The transcript says local chat uses Gemma."

        let service = makeService(descriptor: descriptor, runtimeClient: runtimeClient)
        let stream = service.streamTranscriptChat(
            message: "What model is used?",
            transcript: makeTranscript(),
            segments: [makeSegment()],
            history: [
                TranscriptChatMessage(
                    id: 1,
                    transcriptId: 42,
                    role: .assistant,
                    content: "Previous answer",
                    createdAt: Date()
                ),
            ]
        )

        var streamed = ""
        for await chunk in stream {
            streamed += chunk
        }

        XCTAssertEqual(streamed, "The transcript says local chat uses Gemma.")
        let prompt = try XCTUnwrap(runtimeClient.generatedPrompts.first)
        XCTAssertTrue(prompt.contains("Transcript Chat side panel"))
        XCTAssertTrue(prompt.contains("Be warm, natural, and concise."))
        XCTAssertTrue(prompt.contains("source of truth"))
        XCTAssertTrue(prompt.contains("Recent chat history:"))
        XCTAssertTrue(prompt.contains("Assistant: Previous answer"))
        XCTAssertTrue(prompt.contains("Latest user question:"))
        XCTAssertTrue(prompt.contains("What model is used?"))
        XCTAssertFalse(prompt.contains("Work only from the transcript below"))
    }

    func testMarkdownFileTaskAddsDocumentBoundaryInstructions() async throws {
        let descriptor = makeDescriptor(modelID: "markdown-file-model")
        let runtimeClient = SanitizingFakeLocalAIRuntimeClient()
        runtimeClient.loadedModelID = descriptor.id
        runtimeClient.streamGenerateResponse = """
        ## File
        - Generated notes
        """

        let service = makeService(descriptor: descriptor, runtimeClient: runtimeClient)
        let result = try await service.runTranscriptMarkdownFileTask(
            userPrompt: "Create launch notes",
            transcript: makeTranscript(),
            segments: [makeSegment()]
        )

        XCTAssertTrue(result.contains("Generated notes"))
        let prompt = try XCTUnwrap(runtimeClient.generatedPrompts.first)
        XCTAssertTrue(prompt.contains("Create Markdown file content from the transcript"))
        XCTAssertTrue(prompt.contains("If the request calls for multiple files"))
        XCTAssertTrue(prompt.contains("Create launch notes"))
    }

    func testSanitizedResultIsSavedAndAutoExportedWithoutThoughtChannel() async throws {
        let descriptor = makeDescriptor(modelID: "sanitized-save-model")
        let runtimeClient = SanitizingFakeLocalAIRuntimeClient()
        runtimeClient.loadedModelID = descriptor.id
        runtimeClient.streamGenerateResponse = """
        <|channel>thought
        Reason internally before answering.
        <channel|>## Summary
        - Exported output starts with the summary
        """

        let service = makeService(descriptor: descriptor, runtimeClient: runtimeClient)
        let databaseManager = try DatabaseManager()
        let repository = TranscriptRepository(dbQueue: databaseManager.dbQueue)

        var transcript = makeTranscript()
        try repository.save(&transcript, segments: [makeSegment()])
        let transcriptID = try XCTUnwrap(transcript.id)
        let segments = try repository.fetchSegments(transcriptId: transcriptID)

        let resultContent = try await service.runTranscriptTask(
            .summary,
            transcript: transcript,
            segments: segments
        )

        var aiResult = TranscriptAIResult(
            id: nil,
            transcriptId: transcriptID,
            promptID: AIPromptTemplate.summary.id,
            promptTitle: AIPromptTemplate.summary.title,
            promptBody: AIPromptTemplate.summary.body,
            content: resultContent,
            createdAt: Date()
        )
        try repository.saveAIResult(&aiResult)

        let exportFolder = tempRoot.appendingPathComponent("Exports")
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        try ExportService.autoExportAIContent(
            title: transcript.title,
            promptTitle: AIPromptTemplate.summary.title,
            content: resultContent,
            to: exportFolder
        )

        let savedResults = try repository.fetchAIResults(transcriptId: transcriptID)
        XCTAssertEqual(savedResults.count, 1)
        XCTAssertEqual(savedResults.first?.content, resultContent)
        XCTAssertTrue(savedResults.first?.content.hasPrefix("## Summary") == true)
        XCTAssertFalse(savedResults.first?.content.contains("<|channel>thought") == true)

        let exportedFiles = try FileManager.default.contentsOfDirectory(
            at: exportFolder,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(exportedFiles.count, 1)

        let exportedContent = try String(contentsOf: try XCTUnwrap(exportedFiles.first))
        XCTAssertEqual(exportedContent, resultContent)
        XCTAssertTrue(exportedContent.hasPrefix("## Summary"))
        XCTAssertFalse(exportedContent.contains("<|channel>thought"))
        XCTAssertFalse(exportedContent.contains("<channel|>"))
    }

    func testDocumentParserSplitsClearMultipleDocumentMarkdown() {
        let response = """
        ## Document 1: Workflow
        1. Intake request
        2. Review transcript

        ## Document 2: Checklist
        - Confirm owner
        - Confirm deadline
        """

        let documents = TranscriptAIDocumentParser.documents(from: response)

        XCTAssertEqual(documents.count, 2)
        XCTAssertEqual(documents[0].title, "Workflow")
        XCTAssertEqual(
            documents[0].content,
            """
            ## Workflow

            1. Intake request
            2. Review transcript
            """
        )
        XCTAssertEqual(documents[1].title, "Checklist")
        XCTAssertEqual(
            documents[1].content,
            """
            ## Checklist

            - Confirm owner
            - Confirm deadline
            """
        )
    }

    func testDocumentParserFallsBackToSingleDocumentForAmbiguousMarkdown() {
        let response = """
        ## Workflow
        - One generated document without explicit boundaries
        """

        let documents = TranscriptAIDocumentParser.documents(from: response, fallbackTitle: "Custom Summary")

        XCTAssertEqual(documents, [
            TranscriptAIDocument(title: "Custom Summary", content: response)
        ])
    }

    func testDocumentParserUsesSingleExplicitDocumentTitle() {
        let response = """
        ## Document 1: Workflow
        - One clearly bounded document
        """

        let documents = TranscriptAIDocumentParser.documents(from: response, fallbackTitle: "Custom Summary")

        XCTAssertEqual(documents, [
            TranscriptAIDocument(
                title: "Workflow",
                content: """
                ## Workflow

                - One clearly bounded document
                """
            )
        ])
    }

    func testInsertAIResultKeepsRepeatedCustomPromptRuns() throws {
        let databaseManager = try DatabaseManager()
        let repository = TranscriptRepository(dbQueue: databaseManager.dbQueue)

        var transcript = makeTranscript()
        try repository.save(&transcript, segments: [makeSegment()])
        let transcriptID = try XCTUnwrap(transcript.id)

        var first = TranscriptAIResult(
            id: nil,
            transcriptId: transcriptID,
            promptID: "custom.inline.repeated",
            promptTitle: "Custom Summary",
            promptBody: "Build a workflow document.",
            content: "First custom output",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        var second = TranscriptAIResult(
            id: nil,
            transcriptId: transcriptID,
            promptID: "custom.inline.repeated",
            promptTitle: "Custom Summary",
            promptBody: "Build a workflow document.",
            content: "Second custom output",
            createdAt: Date(timeIntervalSince1970: 2)
        )

        try repository.insertAIResult(&first)
        try repository.insertAIResult(&second)

        let savedResults = try repository.fetchAIResults(transcriptId: transcriptID)
        XCTAssertEqual(savedResults.count, 2)
        XCTAssertEqual(Set(savedResults.map(\.content)), ["First custom output", "Second custom output"])
    }

    func testLongCustomPromptUsesChunkReduceStrategy() async throws {
        let descriptor = makeDescriptor(modelID: "long-custom-model")
        let runtimeClient = SanitizingFakeLocalAIRuntimeClient()
        runtimeClient.loadedModelID = descriptor.id
        runtimeClient.streamGenerateResponse = "Chunk or final output"

        let service = makeService(descriptor: descriptor, runtimeClient: runtimeClient)
        let longSegment = TranscriptSegment(
            id: nil,
            transcriptId: 0,
            speakerId: nil,
            speakerName: nil,
            text: String(repeating: "Long transcript paragraph. ", count: 1_200),
            startTime: 0,
            endTime: 60,
            sortOrder: 0
        )
        let prompt = AIPromptTemplate(
            id: "custom.inline.test",
            title: "Custom Summary",
            body: "Build workflow documents from this transcript.",
            kind: .custom
        )

        _ = try await service.runTranscriptTask(
            prompt,
            transcript: makeTranscript(),
            segments: [longSegment]
        )

        XCTAssertGreaterThan(runtimeClient.streamGenerateCalls, 1)
        XCTAssertTrue(runtimeClient.generatedPrompts.last?.contains("merging chunk outputs") == true)
    }

    func testLongMarkdownFileTaskUsesChunkReduceStrategy() async throws {
        let descriptor = makeDescriptor(modelID: "long-markdown-file-model")
        let runtimeClient = SanitizingFakeLocalAIRuntimeClient()
        runtimeClient.loadedModelID = descriptor.id
        runtimeClient.streamGenerateResponse = "Chunk or final output"

        let service = makeService(descriptor: descriptor, runtimeClient: runtimeClient)
        let longSegment = TranscriptSegment(
            id: nil,
            transcriptId: 0,
            speakerId: nil,
            speakerName: nil,
            text: String(repeating: "Long transcript paragraph. ", count: 1_200),
            startTime: 0,
            endTime: 60,
            sortOrder: 0
        )

        _ = try await service.runTranscriptMarkdownFileTask(
            userPrompt: "Create a markdown summary file.",
            transcript: makeTranscript(),
            segments: [longSegment]
        )

        XCTAssertGreaterThan(runtimeClient.streamGenerateCalls, 1)
        XCTAssertTrue(runtimeClient.generatedPrompts.last?.contains("merging chunk outputs") == true)
    }

    func testPreparedContextChatUsesCachedMemoryWithoutRechunking() async throws {
        let descriptor = makeDescriptor(modelID: "prepared-chat-model")
        let runtimeClient = SanitizingFakeLocalAIRuntimeClient()
        runtimeClient.loadedModelID = descriptor.id
        runtimeClient.streamGenerateResponse = "Prepared-memory answer"

        let service = makeService(descriptor: descriptor, runtimeClient: runtimeClient)
        let longSegment = TranscriptSegment(
            id: nil,
            transcriptId: 0,
            speakerId: nil,
            speakerName: nil,
            text: String(repeating: "Uncached long transcript paragraph. ", count: 1_200),
            startTime: 0,
            endTime: 60,
            sortOrder: 0
        )

        let stream = service.streamTranscriptChat(
            message: "What matters?",
            transcript: makeTranscript(),
            segments: [longSegment],
            history: [],
            preparedContext: makePreparedContext()
        )

        var streamed = ""
        for await chunk in stream {
            streamed += chunk
        }

        XCTAssertEqual(streamed, "Prepared-memory answer")
        XCTAssertEqual(runtimeClient.streamGenerateCalls, 1)
        let prompt = try XCTUnwrap(runtimeClient.generatedPrompts.first)
        XCTAssertTrue(prompt.contains("Prepared transcript memory"))
        XCTAssertTrue(prompt.contains("Cached source chunk 1"))
        XCTAssertFalse(prompt.contains("This is one chunk from a longer transcript"))
    }

    func testPreparedContextMarkdownTaskUsesSingleCachedMemoryPrompt() async throws {
        let descriptor = makeDescriptor(modelID: "prepared-markdown-model")
        let runtimeClient = SanitizingFakeLocalAIRuntimeClient()
        runtimeClient.loadedModelID = descriptor.id
        runtimeClient.streamGenerateResponse = "## Summary\n- Cached"

        let service = makeService(descriptor: descriptor, runtimeClient: runtimeClient)
        let longSegment = TranscriptSegment(
            id: nil,
            transcriptId: 0,
            speakerId: nil,
            speakerName: nil,
            text: String(repeating: "Uncached long transcript paragraph. ", count: 1_200),
            startTime: 0,
            endTime: 60,
            sortOrder: 0
        )

        let result = try await service.runTranscriptMarkdownFileTask(
            userPrompt: "Create a summary file",
            transcript: makeTranscript(),
            segments: [longSegment],
            preparedContext: makePreparedContext()
        )

        XCTAssertTrue(result.contains("Cached"))
        XCTAssertEqual(runtimeClient.streamGenerateCalls, 1)
        let prompt = try XCTUnwrap(runtimeClient.generatedPrompts.first)
        XCTAssertTrue(prompt.contains("Prepared transcript memory"))
        XCTAssertFalse(prompt.contains("merging chunk outputs"))
    }

    private func makeService(
        descriptor: AIModelDescriptor,
        runtimeClient: SanitizingFakeLocalAIRuntimeClient
    ) -> GemmaService {
        GemmaService(
            defaults: defaults,
            fileManager: .default,
            verifier: AIModelVerifier(),
            downloader: SanitizingNoopDownloader(),
            descriptorProvider: { _ in descriptor },
            catalogErrorProvider: { nil },
            bundledSeedDirectoryProvider: { _ in nil },
            runtimeClient: runtimeClient
        )
    }

    private func makeDescriptor(modelID: String) -> AIModelDescriptor {
        AIModelDescriptor(
            id: modelID,
            displayName: "Test Model",
            providerID: "provider/test",
            revision: "revision-1",
            estimatedDownloadSizeBytes: 0,
            estimatedMemoryBytes: 0,
            notes: "Response sanitization test descriptor",
            assetFiles: []
        )
    }

    private func makeTranscript() -> Transcript {
        Transcript(
            id: nil,
            title: "Gemma summary test",
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
    }

    private func makeSegment() -> TranscriptSegment {
        TranscriptSegment(
            id: nil,
            transcriptId: 0,
            speakerId: nil,
            speakerName: nil,
            text: "The speaker explains how Gemma summaries should be saved.",
            startTime: 0,
            endTime: 5,
            sortOrder: 0
        )
    }

    private func makePreparedContext() -> PreparedTranscriptContext {
        let chunkContent = String(repeating: "Cached source detail. ", count: 250)
        let normalizedText = String(repeating: "Cached normalized transcript text. ", count: 900)
        return PreparedTranscriptContext(
            transcriptId: 42,
            contentHash: "prepared-hash",
            normalizedText: normalizedText,
            memorySummary: "Overall cached memory summary.",
            chunks: [
                PreparedTranscriptContextChunk(
                    sortOrder: 0,
                    content: chunkContent,
                    summary: "Cached chunk summary."
                ),
            ],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private final class SanitizingNoopDownloader: ModelAssetDownloading {
    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        XCTFail("Downloader should not be called in response sanitization tests.")
    }
}

@MainActor
private final class SanitizingFakeLocalAIRuntimeClient: LocalAIRuntimeClient {
    var loadedModelID: String?
    var streamGenerateResponse = ""
    var streamGenerateCalls = 0
    var generatedPrompts: [String] = []

    func runtimeLooksInstalled() -> Bool {
        true
    }

    func runtimeNeedsPreparation() async -> Bool {
        false
    }

    func ensureRuntimeReady() async throws {}

    func loadModel(at modelDirectory: URL, modelID: String) async throws {
        loadedModelID = modelID
    }

    func streamGenerate(
        messages: [LocalAIChatMessage],
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        streamGenerateCalls += 1
        generatedPrompts.append(messages.map(\.content).joined(separator: "\n\n"))
        onChunk(streamGenerateResponse)
        return streamGenerateResponse
    }

    func cancelGeneration() {}

    func unloadModel() async {
        loadedModelID = nil
    }

    func healthCheck() async throws {}
}
