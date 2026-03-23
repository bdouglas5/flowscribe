import Foundation

enum CodexServiceError: LocalizedError {
    case notInstalled
    case notSignedIn
    case emptyResponse
    case taskInProgress

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Codex CLI is not installed. Install it first to enable ChatGPT sign-in."
        case .notSignedIn:
            "Sign in with ChatGPT in Settings before running AI transcript tools."
        case .emptyResponse:
            "Codex returned an empty response."
        case .taskInProgress:
            "Another AI task is already running. Wait for it to finish before starting a new one."
        }
    }
}

@Observable
@MainActor
final class CodexService {
    enum ConnectionState: Equatable {
        case checking
        case unavailable
        case signedOut
        case signedIn(method: String)
    }

    private enum PromptExecutionStrategy {
        case singleShot
        case chunkMap
        case chunkReduce
    }

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private var executionTimeout: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: "codexTimeoutSeconds")
        return TimeInterval(stored > 0 ? stored : 300)
    }
    private let healthCheckTimeout: TimeInterval = 60
    private let healthCheckPhrase = "Floscrybe Codex health check ok"
    private let maxInlineTranscriptCharacters = 18_000
    private let promptTemplatesKey = "codexPromptTemplates"
    private let transcriptChunkSize = 18_000
    private let workingDirectoryName = "codex-workspace"

    private(set) var connectionState: ConnectionState = .checking
    private(set) var codexBinaryPath: String?
    private(set) var lastHealthCheckResponse: String?
    private(set) var lastHealthCheckAt: Date?
    private(set) var activeTaskPromptTitle: String?
    private(set) var activeTaskStatus: String?
    private(set) var activeTaskTranscriptId: Int64?

    var promptTemplates: [AIPromptTemplate]
    var statusTitle = "Checking Codex CLI..."
    var statusDetail = "Floscrybe is looking for a local Codex installation."
    var lastError: String?
    var isAuthenticating = false
    var isRunningHealthCheck = false
    var isRunningTask = false

    init() {
        self.promptTemplates = AIPromptTemplate.defaultTemplates
        self.promptTemplates = loadPromptTemplates()
    }

    var isInstalled: Bool {
        codexBinaryPath != nil
    }

    var isSignedIn: Bool {
        if case .signedIn = connectionState {
            return true
        }
        return false
    }

    var connectionLabel: String {
        switch connectionState {
        case .checking:
            "Checking"
        case .unavailable:
            "Unavailable"
        case .signedOut:
            "Signed Out"
        case .signedIn(let method):
            "Connected via \(method)"
        }
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

    func refreshStatus() async {
        lastError = nil

        guard let codexURL = locateCodexBinary() else {
            codexBinaryPath = nil
            connectionState = .unavailable
            statusTitle = "Codex CLI not installed"
            statusDetail = "Install Codex CLI to enable ChatGPT-backed transcript tools."
            return
        }

        codexBinaryPath = codexURL.path
        connectionState = .checking
        statusTitle = "Checking Codex session..."
        statusDetail = codexURL.path

        do {
            let output = try await SubprocessRunner.run(
                executable: codexURL,
                arguments: ["login", "status"],
                workingDirectory: try prepareWorkingDirectory()
            )
            applyStatus(from: cleanedOutput(from: output))
        } catch {
            AppLogger.error("Codex", "Failed to read login status: \(error.localizedDescription)")
            connectionState = .signedOut
            statusTitle = "Codex CLI found, status check failed"
            statusDetail = codexURL.path
            lastError = error.localizedDescription
        }
    }

    func signInWithChatGPT() async {
        guard let codexURL = locateCodexBinary() else {
            connectionState = .unavailable
            statusTitle = "Codex CLI not installed"
            statusDetail = "Install Codex CLI before signing in."
            return
        }

        isAuthenticating = true
        lastError = nil
        statusTitle = "Waiting for ChatGPT sign-in..."
        statusDetail = """
        Codex CLI is opening the official OpenAI browser flow. Complete it there and Floscrybe \
        will refresh automatically.
        """

        do {
            _ = try await SubprocessRunner.runChecked(
                executable: codexURL,
                arguments: ["login"],
                workingDirectory: try prepareWorkingDirectory()
            )
            await refreshStatus()
            if isSignedIn {
                await runHealthCheck()
            }
        } catch {
            AppLogger.error("Codex", "ChatGPT sign-in failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            connectionState = .signedOut
            statusTitle = "ChatGPT sign-in failed"
            statusDetail = codexURL.path
        }

        isAuthenticating = false
    }

    func signOut() async {
        guard let codexURL = locateCodexBinary() else {
            connectionState = .unavailable
            statusTitle = "Codex CLI not installed"
            statusDetail = "Install Codex CLI before managing the session."
            return
        }

        lastError = nil

        do {
            _ = try await SubprocessRunner.runChecked(
                executable: codexURL,
                arguments: ["logout"],
                workingDirectory: try prepareWorkingDirectory()
            )
            lastHealthCheckResponse = nil
            lastHealthCheckAt = nil
            await refreshStatus()
        } catch {
            AppLogger.error("Codex", "Logout failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func runHealthCheck() async {
        guard isSignedIn else {
            lastError = CodexServiceError.notSignedIn.localizedDescription
            return
        }

        isRunningHealthCheck = true
        lastError = nil

        do {
            let response = try await execute(
                prompt: """
                Reply with exactly this text and nothing else:
                \(healthCheckPhrase)
                """,
                timeout: healthCheckTimeout
            )
            guard response.localizedCaseInsensitiveContains(healthCheckPhrase) else {
                throw CodexServiceError.emptyResponse
            }
            lastHealthCheckResponse = response
            lastHealthCheckAt = Date()
            statusTitle = "Codex connection verified"
            statusDetail = "A read-only Codex execution completed successfully."
        } catch {
            AppLogger.error("Codex", "Health check failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        isRunningHealthCheck = false
    }

    func runTranscriptTask(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        segments: [TranscriptSegment]
    ) async throws -> String {
        guard isSignedIn else {
            throw CodexServiceError.notSignedIn
        }
        guard !isRunningTask else {
            throw CodexServiceError.taskInProgress
        }

        isRunningTask = true
        activeTaskPromptTitle = promptTemplate.title
        activeTaskStatus = "Preparing transcript..."
        activeTaskTranscriptId = transcript.id
        defer {
            isRunningTask = false
            activeTaskPromptTitle = nil
            activeTaskStatus = nil
            activeTaskTranscriptId = nil
        }

        let transcriptBody = transcriptText(from: transcript, segments: segments)
        let modelName = UserDefaults.standard.string(forKey: "codexModel") ?? "CLI default"
        AppLogger.info(
            "Codex",
            "Running prompt \(promptTemplate.id) for transcriptId=\(transcript.id ?? -1) chars=\(transcriptBody.count) model=\(modelName)"
        )

        let strategy = executionStrategy(
            for: promptTemplate,
            transcriptLength: transcriptBody.count
        )

        switch strategy {
        case .singleShot:
            activeTaskStatus = "Sending transcript to Codex..."
            return try await execute(
                prompt: buildPrompt(
                    for: promptTemplate,
                    transcript: transcript,
                    transcriptBody: transcriptBody
                ),
                timeout: executionTimeout
            )

        case .chunkMap:
            let chunks = transcriptChunks(from: transcriptBody)
            AppLogger.info(
                "Codex",
                "Using chunk-map execution for prompt \(promptTemplate.id) chunks=\(chunks.count)"
            )
            return try await executeChunkMapPrompt(
                promptTemplate,
                transcript: transcript,
                chunks: chunks
            )

        case .chunkReduce:
            let chunks = transcriptChunks(from: transcriptBody)
            AppLogger.info(
                "Codex",
                "Using chunk-reduce execution for prompt \(promptTemplate.id) chunks=\(chunks.count)"
            )
            return try await executeChunkReducePrompt(
                promptTemplate,
                transcript: transcript,
                chunks: chunks
            )
        }
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

    private func execute(
        prompt: String,
        timeout: TimeInterval
    ) async throws -> String {
        guard let codexURL = locateCodexBinary() else {
            throw CodexServiceError.notInstalled
        }

        let startedAt = Date()
        let workingDirectory = try prepareWorkingDirectory()
        let outputFile = workingDirectory.appendingPathComponent("codex-output-\(UUID().uuidString).txt")

        defer {
            try? fileManager.removeItem(at: outputFile)
        }

        var args = [
            "exec",
            "-C", workingDirectory.path,
            "--skip-git-repo-check",
            "--ephemeral",
            "--sandbox", "read-only",
            "--color", "never",
            "--output-last-message", outputFile.path
        ]

        if let model = UserDefaults.standard.string(forKey: "codexModel"), !model.isEmpty {
            args.append(contentsOf: ["--model", model])
            AppLogger.info("Codex", "Using model: \(model)")
        } else {
            AppLogger.info("Codex", "Using CLI default model (no --model flag)")
        }

        args.append("-")

        let output = try await SubprocessRunner.run(
            executable: codexURL,
            arguments: args,
            workingDirectory: workingDirectory,
            standardInput: prompt,
            timeout: timeout
        )

        guard output.exitCode == 0 else {
            let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = stderr.isEmpty ? cleanedOutput(from: output) : stderr
            throw SubprocessError.executionFailed(message, output.exitCode)
        }

        let fileResponse = try? String(contentsOf: outputFile, encoding: .utf8)
        let response = (fileResponse ?? cleanedOutput(from: output))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !response.isEmpty else {
            throw CodexServiceError.emptyResponse
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        AppLogger.info(
            "Codex",
            "Codex exec completed in \(String(format: "%.1f", elapsed))s promptChars=\(prompt.count) responseChars=\(response.count)"
        )

        return response
    }

    private func buildPrompt(
        for promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        transcriptBody: String
    ) -> String {
        return """
        You are helping inside Floscrybe, a desktop transcription app.
        Work only from the transcript below. If information is missing, say so instead of guessing.
        Return concise Markdown.

        Task:
        \(promptTemplate.body)

        Transcript metadata:
        - Title: \(transcript.title)
        - Created: \(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))
        - Speaker detection: \(transcript.speakerDetection ? "enabled" : "disabled")
        - Speakers detected: \(transcript.speakerCount)

        Transcript:
        \(transcriptBody)
        """
    }

    private func executeChunkMapPrompt(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        chunks: [String]
    ) async throws -> String {
        var cleanedChunks: [String] = []

        for (index, chunk) in chunks.enumerated() {
            activeTaskStatus = "Cleaning chunk \(index + 1) of \(chunks.count)..."
            let prompt = """
            You are helping inside Floscrybe, a desktop transcription app.
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

            let chunkResult = try await execute(
                prompt: prompt,
                timeout: executionTimeout
            )
            cleanedChunks.append(chunkResult)
        }

        return cleanedChunks.joined(separator: "\n\n")
    }

    private func executeChunkReducePrompt(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        chunks: [String]
    ) async throws -> String {
        var chunkOutputs: [String] = []

        for (index, chunk) in chunks.enumerated() {
            activeTaskStatus = "Analyzing chunk \(index + 1) of \(chunks.count)..."
            let prompt = """
            You are helping inside Floscrybe, a desktop transcription app.
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

            let chunkOutput = try await execute(
                prompt: prompt,
                timeout: executionTimeout
            )
            chunkOutputs.append("""
            ## Chunk \(index + 1)
            \(chunkOutput)
            """)
        }

        activeTaskStatus = "Merging chunk summaries..."
        let finalPrompt = """
        You are helping inside Floscrybe, a desktop transcription app.
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

        return try await execute(
            prompt: finalPrompt,
            timeout: executionTimeout
        )
    }

    private func executionStrategy(
        for promptTemplate: AIPromptTemplate,
        transcriptLength: Int
    ) -> PromptExecutionStrategy {
        guard transcriptLength > maxInlineTranscriptCharacters else {
            return .singleShot
        }

        if promptTemplate.id == AIPromptTemplate.cleanUp.id {
            return .chunkMap
        }

        return .chunkReduce
    }

    private func loadPromptTemplates() -> [AIPromptTemplate] {
        guard let data = defaults.data(forKey: promptTemplatesKey),
              let storedTemplates = try? JSONDecoder().decode([AIPromptTemplate].self, from: data) else {
            return AIPromptTemplate.defaultTemplates
        }

        let storedByID = Dictionary(uniqueKeysWithValues: storedTemplates.map { ($0.id, $0) })
        var mergedTemplates = AIPromptTemplate.defaultTemplates.map { defaultTemplate in
            storedByID[defaultTemplate.id] ?? defaultTemplate
        }

        let customTemplates = storedTemplates.filter { $0.kind == .custom }
        mergedTemplates.append(contentsOf: customTemplates)
        return mergedTemplates
    }

    private func persistPromptTemplates() {
        let sortedTemplates = availablePromptTemplates
        guard let data = try? JSONEncoder().encode(sortedTemplates) else { return }
        defaults.set(data, forKey: promptTemplatesKey)
        promptTemplates = sortedTemplates
    }

    private func transcriptText(from transcript: Transcript, segments: [TranscriptSegment]) -> String {
        guard !segments.isEmpty else {
            return transcript.fullText
        }

        return segments
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { segment in
                var line = ""
                if let speakerName = segment.speakerName, !speakerName.isEmpty {
                    line += "\(speakerName): "
                }
                line += segment.text
                return line
            }
            .joined(separator: "\n\n")
    }

    private func transcriptChunks(from transcriptBody: String) -> [String] {
        let paragraphs = transcriptBody
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else {
            return splitText(transcriptBody, maxLength: transcriptChunkSize)
        }

        var chunks: [String] = []
        var currentParagraphs: [String] = []
        var currentLength = 0

        for paragraph in paragraphs {
            if paragraph.count > transcriptChunkSize {
                if !currentParagraphs.isEmpty {
                    chunks.append(currentParagraphs.joined(separator: "\n\n"))
                    currentParagraphs = []
                    currentLength = 0
                }
                chunks.append(contentsOf: splitText(paragraph, maxLength: transcriptChunkSize))
                continue
            }

            let additionalLength = paragraph.count + (currentParagraphs.isEmpty ? 0 : 2)
            if currentLength + additionalLength > transcriptChunkSize, !currentParagraphs.isEmpty {
                chunks.append(currentParagraphs.joined(separator: "\n\n"))
                currentParagraphs = [paragraph]
                currentLength = paragraph.count
            } else {
                currentParagraphs.append(paragraph)
                currentLength += additionalLength
            }
        }

        if !currentParagraphs.isEmpty {
            chunks.append(currentParagraphs.joined(separator: "\n\n"))
        }

        return chunks
    }

    private func splitText(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }

        var chunks: [String] = []
        var remaining = text[...]

        while !remaining.isEmpty {
            let preferredEnd = remaining.index(
                remaining.startIndex,
                offsetBy: min(maxLength, remaining.count)
            )

            var splitIndex = preferredEnd
            if preferredEnd < remaining.endIndex {
                let candidateSlice = remaining[..<preferredEnd]
                if let newlineIndex = candidateSlice.lastIndex(of: "\n") {
                    splitIndex = newlineIndex
                } else if let spaceIndex = candidateSlice.lastIndex(of: " ") {
                    splitIndex = spaceIndex
                }
            }

            let rawChunk = remaining[..<splitIndex]
            let chunk = rawChunk.trimmingCharacters(in: .whitespacesAndNewlines)

            if chunk.isEmpty {
                let forcedChunk = remaining[..<preferredEnd]
                chunks.append(forcedChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                remaining = remaining[preferredEnd...]
            } else {
                chunks.append(chunk)
                remaining = remaining[splitIndex...]
            }

            remaining = remaining.drop(while: { $0.isWhitespace || $0.isNewline })
        }

        return chunks
    }

    private func locateCodexBinary() -> URL? {
        if let customPath = defaults.string(forKey: "codexCustomBinaryPath"),
           !customPath.isEmpty,
           fileManager.isExecutableFile(atPath: customPath) {
            return URL(fileURLWithPath: customPath)
        }

        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []

        if let explicitPath = environment["CODEX_PATH"], !explicitPath.isEmpty {
            candidates.append(explicitPath)
        }

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ])

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        return nil
    }

    private func prepareWorkingDirectory() throws -> URL {
        try StoragePaths.ensureDirectoriesExist()

        let directory = StoragePaths.temp.appendingPathComponent(workingDirectoryName)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private func applyStatus(from output: String) {
        let normalizedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedOutput.localizedCaseInsensitiveContains("logged in using") {
            let method = normalizedOutput
                .components(separatedBy: "Logged in using")
                .last?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .first
                .map(String.init) ?? "Codex"

            connectionState = .signedIn(method: method)
            statusTitle = "Codex connected"
            statusDetail = "Floscrybe will run AI transcript tasks through your local Codex session."
            return
        }

        if normalizedOutput.localizedCaseInsensitiveContains("not logged in") {
            connectionState = .signedOut
            statusTitle = "Codex CLI installed"
            statusDetail = "Sign in with ChatGPT to enable transcript-side AI tools."
            return
        }

        connectionState = .signedOut
        statusTitle = "Codex CLI installed"
        statusDetail = normalizedOutput.isEmpty ? "Sign in with ChatGPT to continue." : normalizedOutput
    }

    private func cleanedOutput(from output: SubprocessRunner.Output) -> String {
        cleanedOutput([output.stdout, output.stderr].joined(separator: "\n"))
    }

    private func cleanedOutput(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.hasPrefix("WARNING:")
                    && !trimmed.hasPrefix("Warning:")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
