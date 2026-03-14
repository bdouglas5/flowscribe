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
