import Darwin
import Foundation

struct LocalAIChatMessage: Codable, Equatable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

enum LocalAIRuntimeError: LocalizedError {
    case helperScriptMissing
    case runtimeVerificationInvalid(String)
    case runtimeInstallationFailed(String)
    case helperLaunchFailed(String)
    case helperProtocolViolation(String)
    case helperTerminated(String)
    case modelNotLoaded
    case modelLoadFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperScriptMissing:
            "The bundled local AI helper script is missing."
        case .runtimeVerificationInvalid(let reason):
            "The local AI runtime is invalid: \(reason)"
        case .runtimeInstallationFailed(let reason):
            "Failed to install the local AI runtime: \(reason)"
        case .helperLaunchFailed(let reason):
            "Failed to launch the local AI helper: \(reason)"
        case .helperProtocolViolation(let reason):
            "The local AI helper returned an invalid response: \(reason)"
        case .helperTerminated(let reason):
            "The local AI helper stopped unexpectedly: \(reason)"
        case .modelNotLoaded:
            "The local AI model is not loaded."
        case .modelLoadFailed(let reason):
            "Failed to load the local AI model: \(reason)"
        case .generationFailed(let reason):
            "The local AI runtime failed while generating text: \(reason)"
        }
    }
}

struct VerifiedLocalAIRuntimeRecord: Codable, Equatable {
    let recordVersion: Int
    let pythonMajorMinor: String
    let mlxLMVersion: String
    let helperProtocolVersion: Int
    let verifiedAt: Date
}

@MainActor
protocol LocalAIRuntimeClient: AnyObject {
    var loadedModelID: String? { get }

    func runtimeLooksInstalled() -> Bool
    func runtimeNeedsPreparation() async -> Bool
    func ensureRuntimeReady() async throws
    func loadModel(at modelDirectory: URL, modelID: String) async throws
    func streamGenerate(
        messages: [LocalAIChatMessage],
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String
    func cancelGeneration()
    func unloadModel() async
    func healthCheck() async throws
}

@MainActor
final class MLXLMRuntimeClient: LocalAIRuntimeClient {
    typealias CommandRunner = @Sendable (
        _ executable: URL,
        _ arguments: [String],
        _ environment: [String: String]?,
        _ workingDirectory: URL?,
        _ standardInput: String?,
        _ timeout: TimeInterval?
    ) async throws -> SubprocessRunner.Output

    private static let logCategory = "LocalAIRuntime"
    private static let pythonMajorMinor = "3.12"
    private static let mlxLMVersion = "0.31.2"
    private static let helperProtocolVersion = 1
    private static let recordVersion = 1

    private let fileManager: FileManager
    private let bundledSeedDirectoryProvider: () -> URL?
    private let helperScriptURLProvider: () throws -> URL
    private let commandRunner: CommandRunner

    private var helperProcess: Process?
    private var helperStdin: FileHandle?
    private var helperStdoutBuffer = Data()
    private var helperStderrBuffer = Data()
    private var helperReadyContinuation: CheckedContinuation<Void, Error>?
    private var pendingCommands: [String: CheckedContinuation<HelperEvent, Error>] = [:]
    private var pendingGeneration: PendingGenerationRequest?
    private var helperTerminationExpectation: HelperTerminationExpectation = .unexpected
    private var activeGenerationRequestID: String?
    private(set) var loadedModelID: String?
    private var loadedModelPath: String?

    init(
        fileManager: FileManager = .default,
        bundledSeedDirectoryProvider: @escaping () -> URL? = { StoragePaths.bundledAIRuntimeSeedDirectory() },
        helperScriptURLProvider: @escaping () throws -> URL = {
            if let url = Bundle.main.url(
                forResource: "mlx_lm_helper",
                withExtension: "py",
                subdirectory: "LocalAI"
            ) {
                return url
            }

            throw LocalAIRuntimeError.helperScriptMissing
        },
        commandRunner: @escaping CommandRunner = { executable, arguments, environment, workingDirectory, standardInput, timeout in
            try await SubprocessRunner.run(
                executable: executable,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory,
                standardInput: standardInput,
                timeout: timeout
            )
        }
    ) {
        self.fileManager = fileManager
        self.bundledSeedDirectoryProvider = bundledSeedDirectoryProvider
        self.helperScriptURLProvider = helperScriptURLProvider
        self.commandRunner = commandRunner
    }

    func runtimeLooksInstalled() -> Bool {
        guard fileManager.fileExists(atPath: StoragePaths.aiRuntimeVerificationFile.path),
              fileManager.isExecutableFile(atPath: StoragePaths.aiRuntimePython.path)
        else {
            return false
        }

        guard let record = try? readRuntimeRecord() else {
            return false
        }

        return record.recordVersion == Self.recordVersion
            && record.pythonMajorMinor == Self.pythonMajorMinor
            && record.mlxLMVersion == Self.mlxLMVersion
            && record.helperProtocolVersion == Self.helperProtocolVersion
    }

    func runtimeNeedsPreparation() async -> Bool {
        do {
            return try await currentRuntimeRecordIfValid() == nil
        } catch {
            AppLogger.error(Self.logCategory, "Runtime validation failed: \(error.localizedDescription)")
            return true
        }
    }

    func ensureRuntimeReady() async throws {
        if try await currentRuntimeRecordIfValid() != nil {
            return
        }

        try StoragePaths.ensureDirectoriesExist()

        if try await installBundledRuntimeSeedIfPresent() {
            return
        }

        try await installRuntimeFresh()
    }

    func loadModel(at modelDirectory: URL, modelID: String) async throws {
        try await ensureRuntimeReady()

        if loadedModelID == modelID,
           loadedModelPath == modelDirectory.path,
           helperProcess?.isRunning == true {
            return
        }

        if let loadedModelPath, loadedModelPath != modelDirectory.path {
            await unloadModel()
        }

        try await launchHelperIfNeeded()
        let response = try await sendCommand([
            "command": "loadModel",
            "modelPath": modelDirectory.path,
        ])

        guard response.event == "loaded" else {
            throw LocalAIRuntimeError.modelLoadFailed(response.message ?? "Unexpected load response.")
        }

        loadedModelID = modelID
        loadedModelPath = modelDirectory.path
    }

    func streamGenerate(
        messages: [LocalAIChatMessage],
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard helperProcess?.isRunning == true, loadedModelID != nil else {
            throw LocalAIRuntimeError.modelNotLoaded
        }

        let requestID = UUID().uuidString
        let payloadMessages = messages.map { message in
            [
                "role": message.role.rawValue,
                "content": message.content,
            ]
        }

        return try await withCheckedThrowingContinuation { continuation in
            let pending = PendingGenerationRequest(
                id: requestID,
                onChunk: onChunk,
                continuation: continuation
            )
            pendingGeneration = pending
            activeGenerationRequestID = requestID

            do {
                try writeHelperCommand([
                    "id": requestID,
                    "command": "generate",
                    "messages": payloadMessages,
                    "maxTokens": maxTokens,
                ])
            } catch {
                pendingGeneration = nil
                activeGenerationRequestID = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func cancelGeneration() {
        guard activeGenerationRequestID != nil else { return }
        terminateHelper(expectation: .generationCancelled)
    }

    func unloadModel() async {
        guard helperProcess?.isRunning == true, loadedModelID != nil else {
            loadedModelID = nil
            loadedModelPath = nil
            return
        }

        do {
            let response = try await sendCommand(["command": "unloadModel"])
            guard response.event == "unloaded" else {
                throw LocalAIRuntimeError.helperProtocolViolation("Unexpected unload response.")
            }
        } catch {
            AppLogger.error(Self.logCategory, "Unloading helper model failed: \(error.localizedDescription)")
            terminateHelper(expectation: .expectedShutdown)
        }

        loadedModelID = nil
        loadedModelPath = nil
    }

    func healthCheck() async throws {
        let response = try await sendCommand(["command": "health"])
        guard response.event == "healthy" else {
            throw LocalAIRuntimeError.helperProtocolViolation("Unexpected health response.")
        }
    }

    private func installBundledRuntimeSeedIfPresent() async throws -> Bool {
        guard let bundledDirectory = bundledSeedDirectoryProvider(),
              fileManager.fileExists(atPath: bundledDirectory.path)
        else {
            return false
        }

        AppLogger.info(Self.logCategory, "Attempting bundled AI runtime install source=\(bundledDirectory.path)")
        try replaceRuntimeDirectory(with: bundledDirectory)

        do {
            let record = try await validateInstalledRuntime()
            try writeRuntimeRecord(record)
            AppLogger.info(Self.logCategory, "Installed bundled AI runtime seed")
            return true
        } catch {
            AppLogger.error(Self.logCategory, "Bundled AI runtime seed invalid: \(error.localizedDescription)")
            removeRuntimeArtifacts()
            return false
        }
    }

    private func installRuntimeFresh() async throws {
        AppLogger.info(Self.logCategory, "Installing local AI runtime with uv")
        removeRuntimeArtifacts()
        try StoragePaths.ensureDirectoriesExist()
        try fileManager.createDirectory(at: StoragePaths.aiRuntimeRoot, withIntermediateDirectories: true)

        do {
            _ = try await runCommand(
                executable: StoragePaths.uvBinary,
                arguments: [
                    "venv",
                    StoragePaths.aiRuntimeVenv.path,
                    "--python",
                    Self.pythonMajorMinor,
                ],
                timeout: 60 * 20
            )

            _ = try await runCommand(
                executable: StoragePaths.uvBinary,
                arguments: [
                    "pip",
                    "install",
                    "--python",
                    StoragePaths.aiRuntimePython.path,
                    "mlx-lm==\(Self.mlxLMVersion)",
                ],
                timeout: 60 * 30
            )

            let record = try await validateInstalledRuntime()
            try writeRuntimeRecord(record)
            AppLogger.info(Self.logCategory, "Local AI runtime installed successfully")
        } catch {
            removeRuntimeArtifacts()
            if let error = error as? LocalizedError, let description = error.errorDescription {
                throw LocalAIRuntimeError.runtimeInstallationFailed(description)
            }
            throw LocalAIRuntimeError.runtimeInstallationFailed(error.localizedDescription)
        }
    }

    private func currentRuntimeRecordIfValid() async throws -> VerifiedLocalAIRuntimeRecord? {
        guard runtimeLooksInstalled() else {
            return nil
        }

        guard let record = try? readRuntimeRecord() else {
            return nil
        }

        do {
            let validatedRecord = try await validateInstalledRuntime()
            if validatedRecord != record {
                try writeRuntimeRecord(validatedRecord)
                return validatedRecord
            }
            return record
        } catch {
            AppLogger.error(Self.logCategory, "Installed runtime failed validation: \(error.localizedDescription)")
            return nil
        }
    }

    private func readRuntimeRecord() throws -> VerifiedLocalAIRuntimeRecord {
        let data = try Data(contentsOf: StoragePaths.aiRuntimeVerificationFile)
        return try JSONDecoder().decode(VerifiedLocalAIRuntimeRecord.self, from: data)
    }

    private func writeRuntimeRecord(_ record: VerifiedLocalAIRuntimeRecord) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(to: StoragePaths.aiRuntimeVerificationFile, options: .atomic)
    }

    private func validateInstalledRuntime() async throws -> VerifiedLocalAIRuntimeRecord {
        guard fileManager.isExecutableFile(atPath: StoragePaths.aiRuntimePython.path) else {
            throw LocalAIRuntimeError.runtimeVerificationInvalid("Missing runtime Python executable.")
        }

        let script = """
        import json
        import sys
        import mlx_lm
        print(json.dumps({
            "python": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
            "mlx_lm": getattr(mlx_lm, "__version__", "unknown"),
        }))
        """

        let output = try await runCommand(
            executable: StoragePaths.aiRuntimePython,
            arguments: ["-c", script],
            timeout: 60
        )

        guard output.exitCode == 0 else {
            throw LocalAIRuntimeError.runtimeVerificationInvalid(output.stderr.isEmpty ? output.stdout : output.stderr)
        }

        struct ValidationPayload: Decodable {
            let python: String
            let mlx_lm: String
        }

        let payload = try JSONDecoder().decode(
            ValidationPayload.self,
            from: Data(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        )

        guard payload.python.hasPrefix("\(Self.pythonMajorMinor).") else {
            throw LocalAIRuntimeError.runtimeVerificationInvalid(
                "Expected Python \(Self.pythonMajorMinor), found \(payload.python)."
            )
        }

        guard payload.mlx_lm == Self.mlxLMVersion else {
            throw LocalAIRuntimeError.runtimeVerificationInvalid(
                "Expected mlx-lm \(Self.mlxLMVersion), found \(payload.mlx_lm)."
            )
        }

        return VerifiedLocalAIRuntimeRecord(
            recordVersion: Self.recordVersion,
            pythonMajorMinor: Self.pythonMajorMinor,
            mlxLMVersion: Self.mlxLMVersion,
            helperProtocolVersion: Self.helperProtocolVersion,
            verifiedAt: Date()
        )
    }

    private func launchHelperIfNeeded() async throws {
        guard helperProcess?.isRunning != true else {
            return
        }

        let helperScriptURL = try helperScriptURLProvider()
        guard fileManager.fileExists(atPath: helperScriptURL.path) else {
            throw LocalAIRuntimeError.helperScriptMissing
        }

        let process = Process()
        process.executableURL = StoragePaths.aiRuntimePython
        process.arguments = [helperScriptURL.path]
        process.environment = helperEnvironment()
        process.currentDirectoryURL = StoragePaths.appSupport

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeHelperStdout(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeHelperStderr(data)
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.handleHelperTermination(proc)
            }
        }

        helperTerminationExpectation = .unexpected
        helperStdoutBuffer.removeAll(keepingCapacity: true)
        helperStderrBuffer.removeAll(keepingCapacity: true)

        try await withCheckedThrowingContinuation { continuation in
            helperReadyContinuation = continuation

            do {
                try process.run()
                helperProcess = process
                helperStdin = stdinPipe.fileHandleForWriting
            } catch {
                helperReadyContinuation = nil
                continuation.resume(throwing: LocalAIRuntimeError.helperLaunchFailed(error.localizedDescription))
            }
        }
    }

    private func consumeHelperStdout(_ data: Data) {
        helperStdoutBuffer.append(data)
        processLineBuffer(&helperStdoutBuffer) { [weak self] line in
            self?.handleHelperStdoutLine(line)
        }
    }

    private func consumeHelperStderr(_ data: Data) {
        helperStderrBuffer.append(data)
        processLineBuffer(&helperStderrBuffer) { line in
            AppLogger.info(Self.logCategory, "helper: \(line)")
        }
    }

    private func handleHelperStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        let event: HelperEvent
        do {
            event = try JSONDecoder().decode(HelperEvent.self, from: data)
        } catch {
            AppLogger.error(Self.logCategory, "Helper returned non-JSON output: \(line)")
            return
        }

        if event.event == "ready" {
            helperReadyContinuation?.resume()
            helperReadyContinuation = nil
            AppLogger.info(Self.logCategory, "Local AI helper is ready")
            return
        }

        if let pendingGeneration, pendingGeneration.id == event.id {
            switch event.event {
            case "token":
                if let text = event.text, !text.isEmpty {
                    pendingGeneration.append(text)
                }
            case "done":
                let responseText = event.text ?? pendingGeneration.response
                self.pendingGeneration = nil
                activeGenerationRequestID = nil
                pendingGeneration.continuation.resume(returning: responseText)
            case "error":
                self.pendingGeneration = nil
                activeGenerationRequestID = nil
                pendingGeneration.continuation.resume(
                    throwing: LocalAIRuntimeError.generationFailed(event.message ?? "Unknown generation failure.")
                )
            default:
                pendingGeneration.continuation.resume(
                    throwing: LocalAIRuntimeError.helperProtocolViolation("Unexpected generation event \(event.event).")
                )
                self.pendingGeneration = nil
                activeGenerationRequestID = nil
            }
            return
        }

        guard let requestID = event.id,
              let continuation = pendingCommands.removeValue(forKey: requestID)
        else {
            AppLogger.info(Self.logCategory, "Ignoring helper event without pending request: \(line)")
            return
        }

        if event.event == "error" {
            continuation.resume(
                throwing: LocalAIRuntimeError.helperProtocolViolation(event.message ?? "Unknown helper error.")
            )
            return
        }

        continuation.resume(returning: event)
    }

    private func handleHelperTermination(_ process: Process) {
        helperProcess = nil
        helperStdin = nil
        loadedModelID = nil
        loadedModelPath = nil

        let stderrTail = helperStderrBuffer.trailingText(maxLines: 8)
        let error = helperTerminationError(stderrTail: stderrTail)

        helperReadyContinuation?.resume(throwing: error)
        helperReadyContinuation = nil

        for continuation in pendingCommands.values {
            continuation.resume(throwing: error)
        }
        pendingCommands.removeAll()

        if let pendingGeneration {
            self.pendingGeneration = nil
            activeGenerationRequestID = nil

            switch helperTerminationExpectation {
            case .generationCancelled:
                pendingGeneration.continuation.resume(throwing: CancellationError())
            case .expectedShutdown:
                pendingGeneration.continuation.resume(throwing: error)
            case .unexpected:
                pendingGeneration.continuation.resume(throwing: error)
            }
        }

        if helperTerminationExpectation == .unexpected {
            AppLogger.error(Self.logCategory, "Local AI helper terminated: \(stderrTail)")
        }

        helperTerminationExpectation = .unexpected
    }

    private func helperTerminationError(stderrTail: String) -> Error {
        switch helperTerminationExpectation {
        case .generationCancelled:
            return CancellationError()
        case .expectedShutdown:
            return LocalAIRuntimeError.helperTerminated(stderrTail.isEmpty ? "Helper stopped." : stderrTail)
        case .unexpected:
            return LocalAIRuntimeError.helperTerminated(
                stderrTail.isEmpty ? "Helper stopped without a response." : stderrTail
            )
        }
    }

    private func sendCommand(_ commandFields: [String: Any]) async throws -> HelperEvent {
        try await launchHelperIfNeeded()

        let requestID = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            pendingCommands[requestID] = continuation

            do {
                var payload = commandFields
                payload["id"] = requestID
                try writeHelperCommand(payload)
            } catch {
                pendingCommands.removeValue(forKey: requestID)
                continuation.resume(throwing: error)
            }
        }
    }

    private func writeHelperCommand(_ payload: [String: Any]) throws {
        guard let helperStdin else {
            throw LocalAIRuntimeError.helperLaunchFailed("Helper stdin is unavailable.")
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        var line = data
        line.append(0x0A)
        try helperStdin.write(contentsOf: line)
    }

    private func terminateHelper(expectation: HelperTerminationExpectation) {
        helperTerminationExpectation = expectation

        guard let helperProcess else { return }
        guard helperProcess.isRunning else {
            handleHelperTermination(helperProcess)
            return
        }

        helperProcess.terminate()
        let pid = helperProcess.processIdentifier

        Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }
    }

    private func replaceRuntimeDirectory(with source: URL) throws {
        let stagedDirectory = StoragePaths.appSupport.appendingPathComponent(".ai-runtime-staged")

        if fileManager.fileExists(atPath: stagedDirectory.path) {
            try fileManager.removeItem(at: stagedDirectory)
        }

        try fileManager.copyItem(at: source, to: stagedDirectory)

        if fileManager.fileExists(atPath: StoragePaths.aiRuntimeRoot.path) {
            try fileManager.removeItem(at: StoragePaths.aiRuntimeRoot)
        }

        if fileManager.fileExists(atPath: StoragePaths.aiRuntimeVerificationFile.path) {
            try fileManager.removeItem(at: StoragePaths.aiRuntimeVerificationFile)
        }

        try fileManager.moveItem(at: stagedDirectory, to: StoragePaths.aiRuntimeRoot)
    }

    private func removeRuntimeArtifacts() {
        if fileManager.fileExists(atPath: StoragePaths.aiRuntimeRoot.path) {
            try? fileManager.removeItem(at: StoragePaths.aiRuntimeRoot)
        }

        if fileManager.fileExists(atPath: StoragePaths.aiRuntimeVerificationFile.path) {
            try? fileManager.removeItem(at: StoragePaths.aiRuntimeVerificationFile)
        }
    }

    private func helperEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    private func runCommand(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> SubprocessRunner.Output {
        try await commandRunner(executable, arguments, nil, nil, nil, timeout)
    }

    private func processLineBuffer(_ buffer: inout Data, consumeLine: (String) -> Void) {
        while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty
            else {
                continue
            }

            consumeLine(line)
        }
    }
}

private extension Data {
    func trailingText(maxLines: Int) -> String {
        guard let fullText = String(data: self, encoding: .utf8) else {
            return "No helper diagnostics were available."
        }

        let lines = fullText
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        return lines.suffix(maxLines).joined(separator: "\n")
    }
}

private enum HelperTerminationExpectation {
    case unexpected
    case expectedShutdown
    case generationCancelled
}

private struct HelperEvent: Decodable {
    let id: String?
    let event: String
    let message: String?
    let text: String?
}

private final class PendingGenerationRequest {
    let id: String
    let onChunk: @Sendable (String) -> Void
    let continuation: CheckedContinuation<String, Error>
    private(set) var response = ""

    init(
        id: String,
        onChunk: @escaping @Sendable (String) -> Void,
        continuation: CheckedContinuation<String, Error>
    ) {
        self.id = id
        self.onChunk = onChunk
        self.continuation = continuation
    }

    func append(_ text: String) {
        response += text
        onChunk(text)
    }
}
