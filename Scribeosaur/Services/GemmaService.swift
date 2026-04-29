import Foundation

enum GemmaServiceError: LocalizedError {
    case taskInProgress
    case emptyResponse
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .taskInProgress:
            "Another AI task is already running. Wait for it to finish before starting a new one."
        case .emptyResponse:
            "The local model returned an empty response."
        case .modelUnavailable:
            "The local model is not available yet."
        }
    }
}

@Observable
@MainActor
final class GemmaService: TranscriptAIService {
    enum ModelState: String {
        case notPresent
        case provisioning
        case loading
        case ready
        case failed

        var label: String {
            switch self {
            case .notPresent:
                "Not Downloaded"
            case .provisioning:
                "Preparing"
            case .loading:
                "Loading"
            case .ready:
                "Ready"
            case .failed:
                "Failed"
            }
        }
    }

    private static let promptTemplatesKey = "aiPromptTemplates"
    private static let legacyPromptTemplatesKey = "codexPromptTemplates"

    private let cleanupTokenLimit = 4_096
    private let defaultTokenLimit = 1_536
    private let provisioningLogCategory = "LocalAIProvisioning"

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let verifier: AIModelVerifier
    private let downloader: any ModelAssetDownloading
    private let descriptorProvider: (String?) -> AIModelDescriptor
    private let catalogErrorProvider: () -> AIModelCatalogError?
    private let bundledSeedDirectoryProvider: (String) -> URL?
    private let runtimeClient: LocalAIRuntimeClient

    private var activeGenerationTask: Task<String, Error>?
    private var autoUnloadTask: Task<Void, Never>?
    private var provisioningTasks: [String: Task<Void, Error>] = [:]

    private(set) var modelState: ModelState = .notPresent
    private(set) var modelProgress: Double = 0
    private(set) var modelProgressLabel = ""
    private(set) var startupStage: LocalAIStartupStage = .idle
    private(set) var startupStageProgress: Double = 0
    private(set) var activeTaskPromptTitle: String?
    private(set) var activeTaskStatus: String?
    private(set) var activeTaskTranscriptId: Int64?

    var promptTemplates: [AIPromptTemplate]
    var statusTitle = "Checking local AI..."
    var statusDetail = "Scribeosaur is checking the local AI runtime and model."
    var lastError: String?
    var isRunningTask = false

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        verifier: AIModelVerifier? = nil,
        downloader: any ModelAssetDownloading = CurlModelAssetDownloader(),
        descriptorProvider: @escaping (String?) -> AIModelDescriptor = AIModelCatalog.descriptor,
        catalogErrorProvider: @escaping () -> AIModelCatalogError? = { AIModelCatalog.loadError },
        bundledSeedDirectoryProvider: @escaping (String) -> URL? = { StoragePaths.bundledModelSeedDirectory(for: $0) },
        runtimeClient: LocalAIRuntimeClient? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.verifier = verifier ?? AIModelVerifier(fileManager: fileManager)
        self.downloader = downloader
        self.descriptorProvider = descriptorProvider
        self.catalogErrorProvider = catalogErrorProvider
        self.bundledSeedDirectoryProvider = bundledSeedDirectoryProvider
        self.runtimeClient = runtimeClient ?? MLXLMRuntimeClient()
        self.promptTemplates = Self.loadPromptTemplates(from: defaults)
    }

    var availablePromptTemplates: [AIPromptTemplate] {
        let builtInOrder = Dictionary(
            uniqueKeysWithValues: AIPromptTemplate.defaultTemplates.enumerated().map { ($1.id, $0) }
        )
        return promptTemplates.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .builtIn
            }
            if lhs.kind == .builtIn {
                return (builtInOrder[lhs.id] ?? 0) < (builtInOrder[rhs.id] ?? 0)
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var selectedModelDescriptor: AIModelDescriptor {
        descriptorProvider(defaults.string(forKey: "selectedAIModelID"))
    }

    var isModelLoaded: Bool {
        runtimeClient.loadedModelID == selectedModelDescriptor.id
    }

    var isModelBusy: Bool {
        modelState == .provisioning || modelState == .loading
    }

    var modelStorageBytes: Int64 {
        directorySize(of: StoragePaths.modelDirectory(for: selectedModelDescriptor.id))
    }

    var hasRepairableModelFiles: Bool {
        let descriptor = selectedModelDescriptor
        guard modelStorageBytes > 0 else { return false }
        return (try? modelIsVerified(for: descriptor)) == nil
    }

    func selectedModelNeedsStartupPreparation() async -> Bool {
        do {
            let descriptor = try resolvedSelectedModelDescriptor()
            let runtimeNeedsPreparation = await runtimeClient.runtimeNeedsPreparation()
            let modelNeedsPreparation = try modelIsVerified(for: descriptor) == nil
            return runtimeNeedsPreparation || modelNeedsPreparation
        } catch {
            return true
        }
    }

    func refreshStatus() async {
        do {
            let descriptor = try resolvedSelectedModelDescriptor()

            if let loadedModelID = runtimeClient.loadedModelID, loadedModelID != descriptor.id {
                await runtimeClient.unloadModel()
            }

            let runtimeInstalled = runtimeClient.runtimeLooksInstalled()

            if try modelIsVerified(for: descriptor) != nil {
                modelProgress = 1.0
                modelProgressLabel = runtimeInstalled
                    ? "Local AI runtime and model files are ready."
                    : "Model files are ready."
                modelState = runtimeInstalled ? .ready : .notPresent
                startupStage = runtimeInstalled ? .ready : .preparingRuntime
                startupStageProgress = runtimeInstalled ? 1.0 : 0.18
                statusTitle = isModelLoaded
                    ? "\(descriptor.displayName) loaded"
                    : "\(descriptor.displayName) available"
                statusDetail = isModelLoaded
                    ? "The local AI runtime is loaded in memory and ready for transcript tools."
                    : runtimeInstalled
                        ? "The local AI runtime and model are installed and will load automatically when needed."
                        : "The model files are downloaded, but the local AI runtime still needs to be installed."
                lastError = nil
                return
            }

            if modelFilesLookComplete(for: descriptor) {
                statusTitle = "Verifying \(descriptor.displayName)..."
                statusDetail = "Checking the local model files."
                let record = try verifyModelFiles(for: descriptor)
                try writeVerificationRecord(record, for: descriptor)
                modelProgress = 1.0
                modelProgressLabel = runtimeInstalled
                    ? "Local AI runtime and model files are ready."
                    : "Model files are ready."
                modelState = runtimeInstalled ? .ready : .notPresent
                startupStage = runtimeInstalled ? .ready : .preparingRuntime
                startupStageProgress = runtimeInstalled ? 1.0 : 0.18
                statusTitle = "\(descriptor.displayName) available"
                statusDetail = runtimeInstalled
                    ? "The local AI runtime and model are installed and ready to load."
                    : "The model files are downloaded, but the local AI runtime still needs to be installed."
                lastError = nil
                return
            }

            modelState = .notPresent
            modelProgress = 0
            modelProgressLabel = ""
            startupStage = .idle
            startupStageProgress = 0
            statusTitle = "\(descriptor.displayName) not downloaded"
            statusDetail = runtimeInstalled
                ? "Scribeosaur will download this model automatically during startup setup when local model files are missing."
                : "Scribeosaur will install the local AI runtime and download the default model automatically during startup setup."
            lastError = nil
        } catch {
            handleAvailabilityFailure(error)
        }
    }

    func cancelActiveTask() {
        activeTaskStatus = "Cancelling..."
        AppLogger.info(
            "LocalAI",
            "User requested cancellation prompt=\(activeTaskPromptTitle ?? "unknown") transcriptId=\(activeTaskTranscriptId ?? -1)"
        )
        runtimeClient.cancelGeneration()
        activeGenerationTask?.cancel()
    }

    func runTranscriptTask(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        segments: [TranscriptSegment],
        preparedContext: PreparedTranscriptContext? = nil
    ) async throws -> String {
        if let preparedContext {
            return try await runPreparedTranscriptTaskInternal(
                promptTemplate,
                transcript: transcript,
                preparedContext: preparedContext,
                onChunk: nil
            )
        }

        return try await runTranscriptTaskInternal(
            promptTemplate,
            transcript: transcript,
            segments: segments,
            onChunk: nil
        )
    }

    func streamTranscriptTask(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        segments: [TranscriptSegment],
        preparedContext: PreparedTranscriptContext? = nil
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    if let preparedContext {
                        _ = try await self.runPreparedTranscriptTaskInternal(
                            promptTemplate,
                            transcript: transcript,
                            preparedContext: preparedContext
                        ) { chunk in
                            continuation.yield(chunk)
                        }
                    } else {
                        _ = try await self.runTranscriptTaskInternal(
                            promptTemplate,
                            transcript: transcript,
                            segments: segments
                        ) { chunk in
                            continuation.yield(chunk)
                        }
                    }
                } catch {
                    self.lastError = error.localizedDescription
                }

                continuation.finish()
            }
        }
    }

    func streamTranscriptChat(
        message: String,
        transcript: Transcript,
        segments: [TranscriptSegment],
        history: [TranscriptChatMessage],
        preparedContext: PreparedTranscriptContext? = nil
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    _ = try await self.runTranscriptChatInternal(
                        message: message,
                        transcript: transcript,
                        segments: segments,
                        history: history,
                        preparedContext: preparedContext
                    ) { chunk in
                        continuation.yield(chunk)
                    }
                } catch {
                    self.lastError = error.localizedDescription
                }

                continuation.finish()
            }
        }
    }

    func runTranscriptMarkdownFileTask(
        userPrompt: String,
        transcript: Transcript,
        segments: [TranscriptSegment],
        preparedContext: PreparedTranscriptContext? = nil
    ) async throws -> String {
        try await runTranscriptTask(
            Self.transcriptMarkdownFilePrompt(userPrompt: userPrompt),
            transcript: transcript,
            segments: segments,
            preparedContext: preparedContext
        )
    }

    func createCustomPrompt() -> AIPromptTemplate {
        let prompt = AIPromptTemplate.newCustomPrompt()
        promptTemplates.append(prompt)
        persistPromptTemplates()
        return prompt
    }

    func savePrompt(_ prompt: AIPromptTemplate) {
        if let index = promptTemplates.firstIndex(where: { $0.id == prompt.id }) {
            promptTemplates[index] = prompt
        } else {
            promptTemplates.append(prompt)
        }
        persistPromptTemplates()
    }

    func deletePrompt(id: String) {
        guard let prompt = promptTemplates.first(where: { $0.id == id }), prompt.isDeletable else { return }
        promptTemplates.removeAll { $0.id == id }
        persistPromptTemplates()
    }

    static func transcriptChatPrompt(
        message: String,
        history: [TranscriptChatMessage]
    ) -> AIPromptTemplate {
        let historyText = history
            .suffix(12)
            .map { chatMessage in
                "\(chatMessage.role.rawValue.capitalized): \(chatMessage.content)"
            }
            .joined(separator: "\n\n")
        let historySection = historyText.isEmpty
            ? "No prior chat messages."
            : historyText

        return AIPromptTemplate(
            id: "builtin.transcript-chat",
            title: "Transcript Chat",
            body: """
            Chat instructions:
            - Be warm, natural, and concise.
            - You may answer greetings, thanks, and questions about what you can do directly.
            - For factual questions about the transcript, use the transcript as the source of truth.
            - If the transcript does not include the answer, say that naturally and offer to help with what is present.
            - Do not invent transcript details.
            - Do not create Markdown files in this response; explicit document requests are handled by a separate Markdown creation flow.
            - Use brief Markdown only when it improves readability.

            Recent chat history:
            \(historySection)

            Latest user question:
            \(message)
            """,
            kind: .builtIn
        )
    }

    private func runTranscriptChatInternal(
        message: String,
        transcript: Transcript,
        segments: [TranscriptSegment],
        history: [TranscriptChatMessage],
        preparedContext: PreparedTranscriptContext?,
        onChunk: ((String) -> Void)?
    ) async throws -> String {
        guard !isRunningTask else {
            throw GemmaServiceError.taskInProgress
        }

        let promptTemplate = Self.transcriptChatPrompt(message: message, history: history)

        isRunningTask = true
        activeTaskPromptTitle = promptTemplate.title
        activeTaskStatus = preparedContext == nil ? "Reading transcript..." : "Reading prepared memory..."
        activeTaskTranscriptId = transcript.id
        lastError = nil

        defer {
            isRunningTask = false
            activeTaskPromptTitle = nil
            activeTaskStatus = nil
            activeTaskTranscriptId = nil
            activeGenerationTask = nil
            scheduleAutoUnloadIfNeeded()
        }

        let transcriptBody = preparedContext?.transcriptBody()
            ?? TranscriptAIUtilities.transcriptText(from: transcript, segments: segments)

        AppLogger.info(
            "LocalAI",
            "Running transcript chat transcriptId=\(transcript.id ?? -1) chars=\(transcriptBody.count) preparedContext=\(preparedContext != nil) model=\(selectedModelDescriptor.displayName)"
        )

        do {
            let result: String

            if preparedContext != nil || transcriptBody.count <= TranscriptAIUtilities.maxInlineTranscriptCharacters {
                activeTaskStatus = "Thinking..."
                result = try await executePrompt(
                    TranscriptAIUtilities.buildTranscriptChatPrompt(
                        for: promptTemplate,
                        transcript: transcript,
                        transcriptBody: transcriptBody
                    ),
                    maxTokens: defaultTokenLimit,
                    onChunk: onChunk
                )
            } else {
                let chunks = TranscriptAIUtilities.transcriptChunks(from: transcriptBody)
                var chunkOutputs: [String] = []

                for (index, chunk) in chunks.enumerated() {
                    activeTaskStatus = "Checking part \(index + 1) of \(chunks.count)..."
                    let chunkOutput = try await executePrompt(
                        TranscriptAIUtilities.buildTranscriptChatChunkPrompt(
                            for: promptTemplate,
                            transcript: transcript,
                            transcriptChunk: chunk,
                            chunkIndex: index + 1,
                            chunkCount: chunks.count
                        ),
                        maxTokens: defaultTokenLimit,
                        onChunk: nil
                    )
                    chunkOutputs.append("""
                    ## Chunk \(index + 1)
                    \(chunkOutput)
                    """)
                }

                activeTaskStatus = "Composing answer..."
                result = try await executePrompt(
                    TranscriptAIUtilities.buildTranscriptChatMergePrompt(
                        for: promptTemplate,
                        transcript: transcript,
                        chunkOutputs: chunkOutputs
                    ),
                    maxTokens: defaultTokenLimit,
                    onChunk: onChunk
                )
            }

            AppLogger.info(
                "LocalAI",
                "Completed transcript chat transcriptId=\(transcript.id ?? -1) outputChars=\(result.count) model=\(selectedModelDescriptor.displayName)"
            )
            return result
        } catch is CancellationError {
            AppLogger.info(
                "LocalAI",
                "Cancelled transcript chat transcriptId=\(transcript.id ?? -1) model=\(selectedModelDescriptor.displayName)"
            )
            throw CancellationError()
        } catch {
            lastError = error.localizedDescription
            AppLogger.error(
                "LocalAI",
                "Transcript chat failed transcriptId=\(transcript.id ?? -1) model=\(selectedModelDescriptor.id): \(error.localizedDescription)"
            )
            throw error
        }
    }

    static func transcriptMarkdownFilePrompt(userPrompt: String) -> AIPromptTemplate {
        AIPromptTemplate(
            id: "custom.chat.markdown-file.\(UUID().uuidString.lowercased())",
            title: "Markdown File",
            body: """
            Create Markdown file content from the transcript for this request:
            \(userPrompt)

            If the request calls for multiple files, return each file in this exact boundary format:

            ## Document 1: Document Title
            Document content...

            ## Document 2: Document Title
            Document content...

            If one file is enough, return a single complete Markdown document.
            Do not include any commentary outside the Markdown file content.
            """,
            kind: .custom
        )
    }

    func prepareSelectedModelIfNeeded() async throws {
        lastError = nil
        do {
            try await ensureModelLoaded()
            scheduleAutoUnloadIfNeeded()
        } catch {
            handleAvailabilityFailure(error)
            throw error
        }
    }

    func provisionSelectedModelFilesIfNeeded() async throws {
        lastError = nil
        do {
            let descriptor = try resolvedSelectedModelDescriptor()
            try await provisionModelIfNeeded(for: descriptor)
        } catch {
            handleAvailabilityFailure(error)
            throw error
        }
    }

    func unloadSelectedModel() {
        Task { @MainActor [weak self] in
            await self?.unloadModel()
        }
    }

    func deleteSelectedModel() throws {
        runtimeClient.cancelGeneration()
        Task { @MainActor [weak self] in
            await self?.unloadModel()
        }

        let descriptor = selectedModelDescriptor
        let modelDirectory = StoragePaths.modelDirectory(for: descriptor.id)
        let verificationFile = StoragePaths.modelVerificationFile(for: descriptor.id)

        if fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.removeItem(at: modelDirectory)
        }
        if fileManager.fileExists(atPath: verificationFile.path) {
            try fileManager.removeItem(at: verificationFile)
        }

        modelState = .notPresent
        modelProgress = 0
        modelProgressLabel = ""
        statusTitle = "\(descriptor.displayName) removed"
        statusDetail = "The local model files were deleted from Application Support."
        lastError = nil
    }

    private func runTranscriptTaskInternal(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        segments: [TranscriptSegment],
        onChunk: ((String) -> Void)?
    ) async throws -> String {
        guard !isRunningTask else {
            throw GemmaServiceError.taskInProgress
        }

        isRunningTask = true
        activeTaskPromptTitle = promptTemplate.title
        activeTaskStatus = "Preparing transcript..."
        activeTaskTranscriptId = transcript.id
        lastError = nil

        defer {
            isRunningTask = false
            activeTaskPromptTitle = nil
            activeTaskStatus = nil
            activeTaskTranscriptId = nil
            activeGenerationTask = nil
            scheduleAutoUnloadIfNeeded()
        }

        let transcriptBody = TranscriptAIUtilities.transcriptText(from: transcript, segments: segments)
        let strategy = TranscriptAIUtilities.executionStrategy(
            for: promptTemplate,
            transcriptLength: transcriptBody.count
        )

        AppLogger.info(
            "LocalAI",
            "Running prompt \(promptTemplate.id) transcriptId=\(transcript.id ?? -1) chars=\(transcriptBody.count) model=\(selectedModelDescriptor.displayName)"
        )

        do {
            let result: String

            switch strategy {
            case .singleShot:
                activeTaskStatus = "Running \(selectedModelDescriptor.displayName)..."
                result = try await executePrompt(
                    TranscriptAIUtilities.buildPrompt(
                        for: promptTemplate,
                        transcript: transcript,
                        transcriptBody: transcriptBody
                    ),
                    maxTokens: defaultTokenLimit,
                    onChunk: onChunk
                )

            case .chunkMap:
                let chunks = TranscriptAIUtilities.transcriptChunks(from: transcriptBody)
                var cleanedChunks: [String] = []

                for (index, chunk) in chunks.enumerated() {
                    activeTaskStatus = "Cleaning chunk \(index + 1) of \(chunks.count)..."
                    let prompt = """
                    You are helping inside Scribeosaur, a desktop transcription app.
                    Apply the task below to only this chunk of a longer transcript.
                    Preserve order and meaning. Do not mention chunk numbers in the response.
                    Return the transformed chunk only.

                    Task:
                    \(promptTemplate.body)

                    Transcript metadata:
                    - Title: \(transcript.title)
                    - Chunk: \(index + 1) of \(chunks.count)

                    Transcript chunk:
                    \(chunk)
                    """

                    let chunkResult = try await executePrompt(
                        prompt,
                        maxTokens: cleanupTokenLimit,
                        onChunk: nil
                    )
                    cleanedChunks.append(chunkResult)
                }

                result = cleanedChunks.joined(separator: "\n\n")

            case .chunkReduce:
                let chunks = TranscriptAIUtilities.transcriptChunks(from: transcriptBody)
                var chunkOutputs: [String] = []

                for (index, chunk) in chunks.enumerated() {
                    activeTaskStatus = "Analyzing chunk \(index + 1) of \(chunks.count)..."
                    let prompt = """
                    You are helping inside Scribeosaur, a desktop transcription app.
                    This is one chunk from a longer transcript.
                    Apply the task below to this chunk only.
                    Return concise Markdown with the most important details from this chunk.
                    Do not invent context from outside this chunk.

                    Task:
                    \(promptTemplate.body)

                    Transcript metadata:
                    - Title: \(transcript.title)
                    - Chunk: \(index + 1) of \(chunks.count)

                    Transcript chunk:
                    \(chunk)
                    """

                    let chunkOutput = try await executePrompt(
                        prompt,
                        maxTokens: defaultTokenLimit,
                        onChunk: nil
                    )
                    chunkOutputs.append("""
                    ## Chunk \(index + 1)
                    \(chunkOutput)
                    """)
                }

                activeTaskStatus = "Merging chunk summaries..."
                let finalPrompt = """
                You are helping inside Scribeosaur, a desktop transcription app.
                The transcript was too long to process in one pass, so you are merging chunk outputs.
                Produce the final result for the original task below.
                Deduplicate repeated points, maintain chronology when useful, and stay faithful to the source.
                Return concise Markdown.

                Original task:
                \(promptTemplate.body)

                Transcript metadata:
                - Title: \(transcript.title)
                - Chunks analyzed: \(chunks.count)

                Chunk outputs:
                \(chunkOutputs.joined(separator: "\n\n"))
                """

                result = try await executePrompt(
                    finalPrompt,
                    maxTokens: defaultTokenLimit,
                    onChunk: onChunk
                )
            }

            AppLogger.info(
                "LocalAI",
                "Completed prompt \(promptTemplate.id) transcriptId=\(transcript.id ?? -1) outputChars=\(result.count) model=\(selectedModelDescriptor.displayName)"
            )
            return result
        } catch is CancellationError {
            AppLogger.info(
                "LocalAI",
                "Cancelled prompt \(promptTemplate.id) transcriptId=\(transcript.id ?? -1) model=\(selectedModelDescriptor.displayName)"
            )
            throw CancellationError()
        } catch {
            lastError = error.localizedDescription
            AppLogger.error(
                "LocalAI",
                "Prompt \(promptTemplate.id) failed transcriptId=\(transcript.id ?? -1) model=\(selectedModelDescriptor.id): \(error.localizedDescription)"
            )
            throw error
        }
    }

    private func runPreparedTranscriptTaskInternal(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        preparedContext: PreparedTranscriptContext,
        onChunk: ((String) -> Void)?
    ) async throws -> String {
        guard !isRunningTask else {
            throw GemmaServiceError.taskInProgress
        }

        isRunningTask = true
        activeTaskPromptTitle = promptTemplate.title
        activeTaskStatus = "Using prepared transcript memory..."
        activeTaskTranscriptId = transcript.id
        lastError = nil

        defer {
            isRunningTask = false
            activeTaskPromptTitle = nil
            activeTaskStatus = nil
            activeTaskTranscriptId = nil
            activeGenerationTask = nil
            scheduleAutoUnloadIfNeeded()
        }

        let transcriptBody = preparedContext.transcriptBody()

        AppLogger.info(
            "LocalAI",
            "Running prompt \(promptTemplate.id) with prepared context transcriptId=\(transcript.id ?? -1) chars=\(transcriptBody.count) hash=\(preparedContext.contentHash) model=\(selectedModelDescriptor.displayName)"
        )

        do {
            activeTaskStatus = "Running \(selectedModelDescriptor.displayName)..."
            let result = try await executePrompt(
                TranscriptAIUtilities.buildPrompt(
                    for: promptTemplate,
                    transcript: transcript,
                    transcriptBody: transcriptBody
                ),
                maxTokens: defaultTokenLimit,
                onChunk: onChunk
            )

            AppLogger.info(
                "LocalAI",
                "Completed prompt \(promptTemplate.id) with prepared context transcriptId=\(transcript.id ?? -1) outputChars=\(result.count) model=\(selectedModelDescriptor.displayName)"
            )
            return result
        } catch is CancellationError {
            AppLogger.info(
                "LocalAI",
                "Cancelled prompt \(promptTemplate.id) with prepared context transcriptId=\(transcript.id ?? -1) model=\(selectedModelDescriptor.displayName)"
            )
            throw CancellationError()
        } catch {
            lastError = error.localizedDescription
            AppLogger.error(
                "LocalAI",
                "Prepared-context prompt \(promptTemplate.id) failed transcriptId=\(transcript.id ?? -1) model=\(selectedModelDescriptor.id): \(error.localizedDescription)"
            )
            throw error
        }
    }

    private func executePrompt(
        _ prompt: String,
        maxTokens: Int,
        onChunk: ((String) -> Void)?
    ) async throws -> String {
        try await ensureModelLoaded()
        guard isModelLoaded else {
            throw GemmaServiceError.modelUnavailable
        }

        let generationTask = Task<String, Error> { [runtimeClient] in
            try await withTaskCancellationHandler {
                try await runtimeClient.streamGenerate(
                    messages: [LocalAIChatMessage(role: .user, content: prompt)],
                    maxTokens: maxTokens
                ) { chunk in
                    onChunk?(chunk)
                }
            } onCancel: {
                Task { @MainActor in
                    runtimeClient.cancelGeneration()
                }
            }
        }

        activeGenerationTask = generationTask
        let response = TranscriptAIUtilities.sanitizeModelResponse(
            try await generationTask.value
        )

        guard !response.isEmpty else {
            throw GemmaServiceError.emptyResponse
        }

        return response
    }

    private func ensureModelLoaded() async throws {
        let descriptor = try resolvedSelectedModelDescriptor()

        if runtimeClient.loadedModelID == descriptor.id {
            modelState = .ready
            startupStage = .ready
            startupStageProgress = 1.0
            statusTitle = "\(descriptor.displayName) loaded"
            statusDetail = "The local AI runtime is ready for transcript tools."
            lastError = nil
            return
        }

        autoUnloadTask?.cancel()

        if runtimeClient.runtimeLooksInstalled() == false {
            modelState = .provisioning
            modelProgress = 0.02
            modelProgressLabel = "Installing local AI runtime..."
            startupStage = .preparingRuntime
            startupStageProgress = 0.02
            statusTitle = "Preparing local AI runtime..."
            statusDetail = "Scribeosaur is installing Python and mlx-lm for local Gemma prompts."
        }

        try await runtimeClient.ensureRuntimeReady()

        let isVerified = try modelIsVerified(for: descriptor) != nil
        if !modelFilesLookComplete(for: descriptor) || !isVerified {
            try await provisionModelIfNeeded(for: descriptor)
        }

        modelState = .loading
        modelProgress = 1.0
        modelProgressLabel = "Loading \(descriptor.displayName)..."
        startupStage = .loading
        startupStageProgress = 1.0
        statusTitle = "Loading \(descriptor.displayName)..."
        statusDetail = "Preparing the local AI model in memory."

        let modelDirectory = StoragePaths.modelDirectory(for: descriptor.id)
        try await runtimeClient.loadModel(at: modelDirectory, modelID: descriptor.id)
        try await runtimeClient.healthCheck()

        modelState = .ready
        modelProgress = 1.0
        modelProgressLabel = "Model loaded."
        startupStage = .ready
        startupStageProgress = 1.0
        statusTitle = "\(descriptor.displayName) loaded"
        statusDetail = "The local AI runtime is ready for transcript tools."
        lastError = nil
    }

    private func provisionModelIfNeeded(for descriptor: AIModelDescriptor) async throws {
        if try modelIsVerified(for: descriptor) != nil {
            return
        }

        if let existingTask = provisioningTasks[descriptor.id] {
            AppLogger.info(
                provisioningLogCategory,
                "Joining active provisioning modelId=\(descriptor.id)"
            )
            try await existingTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            try await self.performProvisionModel(for: descriptor)
        }
        provisioningTasks[descriptor.id] = task

        do {
            try await task.value
            provisioningTasks.removeValue(forKey: descriptor.id)
        } catch {
            provisioningTasks.removeValue(forKey: descriptor.id)
            throw error
        }
    }

    private func performProvisionModel(for descriptor: AIModelDescriptor) async throws {
        if try modelIsVerified(for: descriptor) != nil {
            return
        }

        try StoragePaths.ensureDirectoriesExist()
        let modelDirectory = StoragePaths.modelDirectory(for: descriptor.id)
        if !fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        }

        modelState = .provisioning
        modelProgress = 0
        modelProgressLabel = "Preparing model files..."
        startupStage = .preparingAssets
        startupStageProgress = 0
        statusTitle = "Preparing \(descriptor.displayName)..."
        statusDetail = "Scribeosaur is provisioning the local AI model."
        AppLogger.info(
            provisioningLogCategory,
            "Starting provisioning modelId=\(descriptor.id) provider=\(descriptor.providerID) revision=\(descriptor.revision)"
        )

        do {
            if try installBundledModelSeedIfPresent(for: descriptor) {
                modelState = .ready
                modelProgress = 1.0
                modelProgressLabel = "Bundled model installed."
                startupStage = .ready
                startupStageProgress = 1.0
                statusTitle = "\(descriptor.displayName) installed"
                statusDetail = "The local AI model was installed from the app bundle."
                lastError = nil
                AppLogger.info(provisioningLogCategory, "Installed bundled seed for modelId=\(descriptor.id)")
                return
            }

            modelProgressLabel = "Preparing download..."
            startupStage = .downloadingAssets
            startupStageProgress = 0.02
            statusTitle = "Downloading \(descriptor.displayName)..."
            statusDetail = "Scribeosaur is downloading the local AI model."

            var completedBytes: Int64 = 0

            for asset in descriptor.assetFiles {
                let finalURL = modelDirectory.appendingPathComponent(asset.path)

                if fileManager.fileExists(atPath: finalURL.path),
                   fileSize(at: finalURL) == asset.sizeBytes,
                   try FileChecksum.matches(url: finalURL, expectedDigest: asset.checksum) {
                    completedBytes += asset.sizeBytes
                    updateDownloadProgress(
                        completedBytes: completedBytes,
                        totalBytes: descriptor.totalBytes,
                        label: "Verified \(asset.path)"
                    )
                    AppLogger.info(
                        provisioningLogCategory,
                        "Skipped already verified asset modelId=\(descriptor.id) asset=\(asset.path)"
                    )
                    continue
                }

                try await downloadAsset(
                    asset,
                    for: descriptor,
                    previouslyCompletedBytes: completedBytes
                )
                completedBytes += asset.sizeBytes
                AppLogger.info(
                    provisioningLogCategory,
                    "Downloaded and verified asset modelId=\(descriptor.id) asset=\(asset.path)"
                )
            }

            let record = try verifyModelFiles(for: descriptor)
            try writeVerificationRecord(record, for: descriptor)
            modelState = .ready
            modelProgress = 1.0
            modelProgressLabel = "Download complete."
            startupStage = .ready
            startupStageProgress = 1.0
            statusTitle = "\(descriptor.displayName) downloaded"
            statusDetail = "The local model files are ready."
            lastError = nil
            AppLogger.info(provisioningLogCategory, "Provisioning complete modelId=\(descriptor.id)")
        } catch {
            _ = invalidateVerificationRecord(for: descriptor)
            modelState = .failed
            startupStage = .failed
            statusTitle = "Local AI unavailable"
            statusDetail = error.localizedDescription
            lastError = error.localizedDescription
            AppLogger.error(
                provisioningLogCategory,
                "Provisioning failed modelId=\(descriptor.id): \(provisioningLogDetail(for: error))"
            )
            throw error
        }
    }

    private func installBundledModelSeedIfPresent(for descriptor: AIModelDescriptor) throws -> Bool {
        guard let bundledDirectory = bundledSeedDirectoryProvider(descriptor.id),
              fileManager.fileExists(atPath: bundledDirectory.path)
        else {
            return false
        }

        AppLogger.info(
            provisioningLogCategory,
            "Attempting bundled seed install modelId=\(descriptor.id) source=\(bundledDirectory.path)"
        )

        let destination = StoragePaths.modelDirectory(for: descriptor.id)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
            AppLogger.info(
                provisioningLogCategory,
                "Removed existing model directory before bundled seed install modelId=\(descriptor.id)"
            )
        }

        try fileManager.copyItem(at: bundledDirectory, to: destination)

        do {
            let record = try verifyModelFiles(for: descriptor)
            try writeVerificationRecord(record, for: descriptor)
        } catch {
            let seedError = LocalAIProvisioningError.bundledSeedInvalid(error.localizedDescription)
            AppLogger.error(
                provisioningLogCategory,
                "Bundled seed invalid modelId=\(descriptor.id): \(provisioningLogDetail(for: seedError))"
            )
            if removeItemIfPresent(
                at: destination,
                logMessage: "Removed copied bundled seed after verification failure modelId=\(descriptor.id)"
            ) {
                AppLogger.info(
                    provisioningLogCategory,
                    "Continuing with remote download after bundled seed cleanup modelId=\(descriptor.id)"
                )
            }
            if invalidateVerificationRecord(for: descriptor) {
                AppLogger.info(
                    provisioningLogCategory,
                    "Removed verification record during bundled seed cleanup modelId=\(descriptor.id)"
                )
            }
            return false
        }

        return true
    }

    private func downloadAsset(
        _ asset: AIModelAsset,
        for descriptor: AIModelDescriptor,
        previouslyCompletedBytes: Int64
    ) async throws {
        let modelDirectory = StoragePaths.modelDirectory(for: descriptor.id)
        let finalURL = modelDirectory.appendingPathComponent(asset.path)
        let partialURL = finalURL.appendingPathExtension("part")

        _ = removeItemIfPresent(
            at: finalURL,
            logMessage: "Removed stale asset before download modelId=\(descriptor.id) asset=\(asset.path)"
        )

        if fileManager.fileExists(atPath: partialURL.path),
           fileSize(at: partialURL) > asset.sizeBytes {
            _ = removeItemIfPresent(
                at: partialURL,
                logMessage: "Removed oversized partial download modelId=\(descriptor.id) asset=\(asset.path)"
            )
        }

        AppLogger.info(
            provisioningLogCategory,
            "Downloading asset modelId=\(descriptor.id) asset=\(asset.path) expectedBytes=\(asset.sizeBytes)"
        )

        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let existingBytes = fileSize(at: partialURL)
                if existingBytes > 0 {
                    AppLogger.info(
                        provisioningLogCategory,
                        "Resuming asset download modelId=\(descriptor.id) asset=\(asset.path) bytesOnDisk=\(existingBytes) attempt=\(attempt)"
                    )
                }

                try await downloader.download(
                    from: descriptor.remoteURL(for: asset),
                    to: partialURL
                ) { [weak self] bytesOnDisk in
                    Task { @MainActor [weak self] in
                        self?.startupStage = .downloadingAssets
                        self?.updateDownloadProgress(
                            completedBytes: previouslyCompletedBytes + min(bytesOnDisk, asset.sizeBytes),
                            totalBytes: descriptor.totalBytes,
                            label: existingBytes > 0
                                ? "Resuming \(asset.path)..."
                                : "Downloading \(asset.path)..."
                        )
                    }
                }
            } catch {
                lastError = error
                let downloadedSize = fileSize(at: partialURL)
                guard shouldRetryDownload(error: error),
                      downloadedSize > 0,
                      downloadedSize < asset.sizeBytes,
                      attempt < maxAttempts
                else {
                    throw error
                }

                AppLogger.info(
                    provisioningLogCategory,
                    "Retrying partial asset download modelId=\(descriptor.id) asset=\(asset.path) attempt=\(attempt + 1) bytesOnDisk=\(downloadedSize)"
                )
                try? await Task.sleep(for: .seconds(Double(attempt)))
                continue
            }

            let downloadedSize = fileSize(at: partialURL)
            startupStage = .verifyingAssets
            updateDownloadProgress(
                completedBytes: previouslyCompletedBytes + downloadedSize,
                totalBytes: descriptor.totalBytes,
                label: "Verifying \(asset.path)..."
            )

            guard downloadedSize <= asset.sizeBytes else {
                _ = removeItemIfPresent(
                    at: partialURL,
                    logMessage: "Cleaned oversized partial download modelId=\(descriptor.id) asset=\(asset.path)"
                )
                AppLogger.error(
                    provisioningLogCategory,
                    "Size mismatch modelId=\(descriptor.id) asset=\(asset.path) expectedBytes=\(asset.sizeBytes) actualBytes=\(downloadedSize)"
                )
                throw LocalAIProvisioningError.sizeMismatch(
                    assetPath: asset.path,
                    expectedBytes: asset.sizeBytes,
                    actualBytes: downloadedSize
                )
            }

            guard fileManager.fileExists(atPath: partialURL.path) else {
                throw LocalAIProvisioningError.downloadFailed(
                    assetPath: asset.path,
                    reason: "The partial download file was missing after download completion."
                )
            }

            guard downloadedSize == asset.sizeBytes else {
                lastError = LocalAIProvisioningError.sizeMismatch(
                    assetPath: asset.path,
                    expectedBytes: asset.sizeBytes,
                    actualBytes: downloadedSize
                )

                guard attempt < maxAttempts else {
                    AppLogger.error(
                        provisioningLogCategory,
                        "Size mismatch modelId=\(descriptor.id) asset=\(asset.path) expectedBytes=\(asset.sizeBytes) actualBytes=\(downloadedSize)"
                    )
                    throw lastError!
                }

                AppLogger.info(
                    provisioningLogCategory,
                    "Retrying short asset download modelId=\(descriptor.id) asset=\(asset.path) attempt=\(attempt + 1) bytesOnDisk=\(downloadedSize)"
                )
                try? await Task.sleep(for: .seconds(Double(attempt)))
                continue
            }

            let actualDigest = try FileChecksum.digest(for: partialURL, expectedDigest: asset.checksum)
            guard actualDigest.caseInsensitiveCompare(asset.checksum) == .orderedSame else {
                _ = removeItemIfPresent(
                    at: partialURL,
                    logMessage: "Cleaned partial download after checksum mismatch modelId=\(descriptor.id) asset=\(asset.path)"
                )
                AppLogger.error(
                    provisioningLogCategory,
                    "Checksum mismatch modelId=\(descriptor.id) asset=\(asset.path) expectedDigest=\(asset.checksum) actualDigest=\(actualDigest)"
                )
                throw LocalAIProvisioningError.checksumMismatch(
                    assetPath: asset.path,
                    expectedDigest: asset.checksum,
                    actualDigest: actualDigest
                )
            }

            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: partialURL, to: finalURL)
            return
        }

        throw lastError ?? LocalAIProvisioningError.downloadFailed(
            assetPath: asset.path,
            reason: "The asset download did not complete."
        )
    }

    private func shouldRetryDownload(error: Error) -> Bool {
        switch error {
        case SubprocessError.timedOut:
            return true
        case SubprocessError.executionFailed(_, let code):
            return code == 18
        default:
            return false
        }
    }

    private func modelIsVerified(for descriptor: AIModelDescriptor) throws -> VerifiedAIModelRecord? {
        let verificationFile = StoragePaths.modelVerificationFile(for: descriptor.id)
        let modelDirectory = StoragePaths.modelDirectory(for: descriptor.id)

        do {
            return try verifier.currentRecordIfValid(
                for: descriptor,
                verificationFile: verificationFile,
                modelDirectory: modelDirectory
            )
        } catch LocalAIProvisioningError.verificationRecordInvalid(let reason) {
            AppLogger.error(
                provisioningLogCategory,
                "Invalid verification record modelId=\(descriptor.id): \(reason)"
            )
            if removeItemIfPresent(
                at: verificationFile,
                logMessage: "Removed invalid verification record modelId=\(descriptor.id)"
            ) {
                AppLogger.info(
                    provisioningLogCategory,
                    "Falling back to full verification after invalid record cleanup modelId=\(descriptor.id)"
                )
            }
            return nil
        } catch {
            throw error
        }
    }

    private func modelFilesLookComplete(for descriptor: AIModelDescriptor) -> Bool {
        descriptor.assetFiles.allSatisfy { asset in
            let assetURL = StoragePaths.modelDirectory(for: descriptor.id).appendingPathComponent(asset.path)
            guard fileManager.fileExists(atPath: assetURL.path) else { return false }
            return fileSize(at: assetURL) == asset.sizeBytes
        }
    }

    private func verifyModelFiles(for descriptor: AIModelDescriptor) throws -> VerifiedAIModelRecord {
        try verifier.verifyFiles(
            for: descriptor,
            in: StoragePaths.modelDirectory(for: descriptor.id)
        )
    }

    private func writeVerificationRecord(
        _ record: VerifiedAIModelRecord,
        for descriptor: AIModelDescriptor
    ) throws {
        try verifier.writeVerificationRecord(
            record,
            to: StoragePaths.modelVerificationFile(for: descriptor.id)
        )
    }

    @discardableResult
    private func invalidateVerificationRecord(for descriptor: AIModelDescriptor) -> Bool {
        let verificationFile = StoragePaths.modelVerificationFile(for: descriptor.id)
        return removeItemIfPresent(
            at: verificationFile,
            logMessage: "Removed verification record modelId=\(descriptor.id)"
        )
    }

    private func unloadModel() async {
        autoUnloadTask?.cancel()
        autoUnloadTask = nil
        await runtimeClient.unloadModel()
        let descriptor = selectedModelDescriptor
        lastError = nil
        modelProgressLabel = "Model unloaded."
        startupStage = .idle
        startupStageProgress = 0
        statusTitle = "\(descriptor.displayName) available"
        statusDetail = "The local model and runtime remain installed and can reload automatically."
    }

    private func scheduleAutoUnloadIfNeeded() {
        autoUnloadTask?.cancel()

        let minutes = defaults.integer(forKey: "aiAutoUnloadMinutes")
        guard minutes > 0, isModelLoaded else { return }

        autoUnloadTask = Task { @MainActor [weak self] in
            let duration = UInt64(minutes) * 60 * 1_000_000_000
            try? await Task.sleep(nanoseconds: duration)
            await self?.autoUnloadIfIdle()
        }
    }

    private func autoUnloadIfIdle() async {
        guard !isRunningTask, isModelLoaded else { return }
        await unloadModel()
        let descriptor = selectedModelDescriptor
        statusTitle = "\(descriptor.displayName) available"
        statusDetail = "The local model was unloaded after being idle."
        modelProgressLabel = "Model unloaded after idle timeout."
        startupStage = .idle
        startupStageProgress = 0
    }

    private func resolvedSelectedModelDescriptor() throws -> AIModelDescriptor {
        if let catalogError = catalogErrorProvider() {
            throw LocalAIProvisioningError.manifestInvalid(catalogError.localizedDescription)
        }
        return selectedModelDescriptor
    }

    private func handleAvailabilityFailure(_ error: Error) {
        modelState = .failed
        startupStage = .failed
        lastError = error.localizedDescription
        statusTitle = "Local AI unavailable"
        statusDetail = error.localizedDescription
    }

    private func provisioningLogDetail(for error: Error) -> String {
        guard let provisioningError = error as? LocalAIProvisioningError else {
            return error.localizedDescription
        }

        switch provisioningError {
        case .downloadFailed(let assetPath, let reason):
            return "download failed asset=\(assetPath) reason=\(reason)"
        case .missingAsset(let assetPath):
            return "missing asset=\(assetPath)"
        case .sizeMismatch(let assetPath, let expectedBytes, let actualBytes):
            return "size mismatch asset=\(assetPath) expectedBytes=\(expectedBytes) actualBytes=\(actualBytes)"
        case .checksumMismatch(let assetPath, let expectedDigest, let actualDigest):
            return "checksum mismatch asset=\(assetPath) expectedDigest=\(expectedDigest) actualDigest=\(actualDigest)"
        case .verificationRecordInvalid(let reason):
            return "verification record invalid reason=\(reason)"
        case .bundledSeedInvalid(let reason):
            return "bundled seed invalid reason=\(reason)"
        case .manifestInvalid(let reason):
            return "manifest invalid reason=\(reason)"
        }
    }

    private static func loadPromptTemplates(from defaults: UserDefaults) -> [AIPromptTemplate] {
        let keys = [promptTemplatesKey, legacyPromptTemplatesKey]

        for key in keys {
            guard let data = defaults.data(forKey: key),
                  let storedTemplates = try? JSONDecoder().decode([AIPromptTemplate].self, from: data) else {
                continue
            }

            let storedByID = Dictionary(uniqueKeysWithValues: storedTemplates.map { ($0.id, $0) })
            var mergedTemplates = AIPromptTemplate.defaultTemplates.map { defaultTemplate in
                storedByID[defaultTemplate.id] ?? defaultTemplate
            }

            let customTemplates = storedTemplates.filter { $0.kind == .custom }
            mergedTemplates.append(contentsOf: customTemplates)
            return mergedTemplates
        }

        return AIPromptTemplate.defaultTemplates
    }

    private func persistPromptTemplates() {
        let sortedTemplates = availablePromptTemplates
        guard let data = try? JSONEncoder().encode(sortedTemplates) else { return }
        defaults.set(data, forKey: Self.promptTemplatesKey)
        promptTemplates = sortedTemplates
    }

    private func updateDownloadProgress(
        completedBytes: Int64,
        totalBytes: Int64,
        label: String
    ) {
        let normalizedProgress = totalBytes > 0
            ? min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
            : 0
        modelProgress = normalizedProgress
        startupStageProgress = normalizedProgress
        modelProgressLabel = label
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    @discardableResult
    private func removeItemIfPresent(at url: URL, logMessage: String) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }

        do {
            try fileManager.removeItem(at: url)
            AppLogger.info(provisioningLogCategory, logMessage)
            return true
        } catch {
            AppLogger.error(
                provisioningLogCategory,
                "Cleanup failed path=\(url.path): \(error.localizedDescription)"
            )
            return false
        }
    }

    private func directorySize(of url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }

        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )

        var total: Int64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}
