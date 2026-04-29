import Foundation

enum SubprocessError: LocalizedError {
    case binaryNotFound(String)
    case executionFailed(String, Int32)
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            "Binary not found at \(path)"
        case .executionFailed(let output, let code):
            "Process exited with code \(code): \(output)"
        case .timedOut(let seconds):
            "Process timed out after \(Int(seconds.rounded())) seconds"
        }
    }
}

enum SubprocessRunner {
    struct Output {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        standardInput: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Output {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            AppLogger.error("Subprocess", "Binary not found at \(executable.path)")
            throw SubprocessError.binaryNotFound(executable.path)
        }

        AppLogger.info(
            "Subprocess",
            "Running \(executable.lastPathComponent) \(arguments.joined(separator: " "))"
        )

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment {
                process.environment = environment
            }
            if let workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            let stdinPipe = Pipe()
            if standardInput != nil {
                process.standardInput = stdinPipe
            }

            let lock = NSLock()
            var didResume = false
            var timeoutWorkItem: DispatchWorkItem?

            func finish(_ result: Result<Output, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                timeoutWorkItem?.cancel()
                continuation.resume(with: result)
            }

            process.terminationHandler = { proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                finish(.success(Output(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: proc.terminationStatus
                )))
            }

            do {
                if let timeout {
                    let workItem = DispatchWorkItem {
                        guard process.isRunning else { return }
                        AppLogger.error(
                            "Subprocess",
                            "\(executable.lastPathComponent) timed out after \(Int(timeout.rounded())) seconds"
                        )
                        process.terminate()
                        finish(.failure(SubprocessError.timedOut(timeout)))
                    }
                    timeoutWorkItem = workItem
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + timeout,
                        execute: workItem
                    )
                }

                try process.run()
                if let standardInput {
                    let inputData = Data(standardInput.utf8)
                    let stdinHandle = stdinPipe.fileHandleForWriting
                    DispatchQueue.global(qos: .userInitiated).async {
                        try? stdinHandle.write(contentsOf: inputData)
                        try? stdinHandle.close()
                    }
                }
            } catch {
                AppLogger.error(
                    "Subprocess",
                    "Failed to launch \(executable.lastPathComponent): \(error.localizedDescription)"
                )
                finish(.failure(error))
            }
        }
    }

    static func runStreaming(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        onOutputLine: @escaping @Sendable (String) -> Void,
        timeout: TimeInterval? = nil
    ) async throws -> Output {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            AppLogger.error("Subprocess", "Binary not found at \(executable.path)")
            throw SubprocessError.binaryNotFound(executable.path)
        }

        AppLogger.info(
            "Subprocess",
            "Running (streaming) \(executable.lastPathComponent) \(arguments.joined(separator: " "))"
        )

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment {
                process.environment = environment
            }
            if let workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBuffer = LineBuffer { line in onOutputLine(line) }
            let stderrBuffer = LineBuffer { line in onOutputLine(line) }
            let accumulatedStdout = AccumulatedData()
            let accumulatedStderr = AccumulatedData()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                accumulatedStdout.append(data)
                stdoutBuffer.append(data)
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                accumulatedStderr.append(data)
                stderrBuffer.append(data)
            }

            let lock = NSLock()
            var didResume = false
            var timeoutWorkItem: DispatchWorkItem?

            func finish(_ result: Result<Output, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                timeoutWorkItem?.cancel()
                continuation.resume(with: result)
            }

            process.terminationHandler = { proc in
                // Nil out handlers to break retain cycles
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                // Read any remaining data
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !remainingStdout.isEmpty {
                    accumulatedStdout.append(remainingStdout)
                    stdoutBuffer.append(remainingStdout)
                }
                if !remainingStderr.isEmpty {
                    accumulatedStderr.append(remainingStderr)
                    stderrBuffer.append(remainingStderr)
                }

                // Flush remaining partial lines
                stdoutBuffer.flush()
                stderrBuffer.flush()

                let stdout = String(data: accumulatedStdout.data, encoding: .utf8) ?? ""
                let stderr = String(data: accumulatedStderr.data, encoding: .utf8) ?? ""

                finish(.success(Output(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: proc.terminationStatus
                )))
            }

            do {
                if let timeout {
                    let workItem = DispatchWorkItem {
                        guard process.isRunning else { return }
                        AppLogger.error(
                            "Subprocess",
                            "\(executable.lastPathComponent) timed out after \(Int(timeout.rounded())) seconds"
                        )
                        process.terminate()
                        finish(.failure(SubprocessError.timedOut(timeout)))
                    }
                    timeoutWorkItem = workItem
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + timeout,
                        execute: workItem
                    )
                }

                try process.run()
            } catch {
                AppLogger.error(
                    "Subprocess",
                    "Failed to launch \(executable.lastPathComponent): \(error.localizedDescription)"
                )
                finish(.failure(error))
            }
        }
    }

    /// Thread-safe line buffer that splits on `\n` and `\r`, emitting complete lines via a callback.
    private final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private let onLine: (String) -> Void

        init(onLine: @escaping (String) -> Void) {
            self.onLine = onLine
        }

        func append(_ data: Data) {
            lock.lock()
            buffer.append(data)
            lock.unlock()
            emitLines()
        }

        func flush() {
            lock.lock()
            let remaining = buffer
            buffer.removeAll()
            lock.unlock()
            if !remaining.isEmpty, let line = String(data: remaining, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                onLine(line)
            }
        }

        private func emitLines() {
            while true {
                lock.lock()
                guard let splitIndex = buffer.firstIndex(where: { $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") }) else {
                    lock.unlock()
                    return
                }
                let lineData = buffer[buffer.startIndex..<splitIndex]
                // Skip past the delimiter (and a following \n if preceded by \r)
                var nextIndex = buffer.index(after: splitIndex)
                if buffer[splitIndex] == UInt8(ascii: "\r"),
                   nextIndex < buffer.endIndex,
                   buffer[nextIndex] == UInt8(ascii: "\n") {
                    nextIndex = buffer.index(after: nextIndex)
                }
                buffer.removeSubrange(buffer.startIndex..<nextIndex)
                lock.unlock()

                if let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                    onLine(line)
                }
            }
        }
    }

    /// Thread-safe accumulated data for building the full output string.
    private final class AccumulatedData: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var data = Data()

        func append(_ newData: Data) {
            lock.lock()
            data.append(newData)
            lock.unlock()
        }
    }

    static func runChecked(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        standardInput: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> String {
        let output = try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            standardInput: standardInput,
            timeout: timeout
        )
        guard output.exitCode == 0 else {
            let message = output.stderr.isEmpty ? output.stdout : output.stderr
            AppLogger.error(
                "Subprocess",
                "\(executable.lastPathComponent) failed with code \(output.exitCode): \(message)"
            )
            if !output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AppLogger.error("Subprocess", "\(executable.lastPathComponent) stdout: \(output.stdout)")
            }
            if !output.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AppLogger.error("Subprocess", "\(executable.lastPathComponent) stderr: \(output.stderr)")
            }
            throw SubprocessError.executionFailed(message, output.exitCode)
        }
        if !output.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppLogger.info("Subprocess", "\(executable.lastPathComponent) stderr: \(output.stderr)")
        }
        return output.stdout
    }
}
