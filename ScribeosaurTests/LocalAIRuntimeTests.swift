import Foundation
import XCTest
@testable import Scribeosaur

@MainActor
final class LocalAIRuntimeTests: XCTestCase {
    private var tempRoot: URL!

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

    func testEnsureRuntimeReadyBootstrapsFreshRuntimeAndWritesVerificationRecord() async throws {
        let commandLog = LockedArray<[String]>()
        let client = MLXLMRuntimeClient(
            bundledSeedDirectoryProvider: { nil },
            helperScriptURLProvider: { throw LocalAIRuntimeError.helperScriptMissing },
            commandRunner: { executable, arguments, _, _, _, _ in
                commandLog.append([executable.path] + arguments)

                if executable == StoragePaths.uvBinary, arguments.first == "venv" {
                    try Self.writeFakePythonLauncher(to: StoragePaths.aiRuntimePython)
                    return .init(stdout: "", stderr: "", exitCode: 0)
                }

                if executable == StoragePaths.uvBinary,
                   Array(arguments.prefix(2)) == ["pip", "install"] {
                    return .init(stdout: "", stderr: "", exitCode: 0)
                }

                if executable == StoragePaths.aiRuntimePython, arguments.first == "-c" {
                    return .init(
                        stdout: #"{"python":"3.12.9","mlx_lm":"0.31.2"}"# + "\n",
                        stderr: "",
                        exitCode: 0
                    )
                }

                XCTFail("Unexpected command: \(executable.path) \(arguments.joined(separator: " "))")
                return .init(stdout: "", stderr: "", exitCode: 1)
            }
        )

        try await client.ensureRuntimeReady()

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: StoragePaths.aiRuntimePython.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: StoragePaths.aiRuntimeVerificationFile.path))
        let runtimeNeedsPreparation = await client.runtimeNeedsPreparation()
        let recordedCommands = commandLog.snapshot()
        XCTAssertFalse(runtimeNeedsPreparation)
        XCTAssertTrue(recordedCommands.contains([StoragePaths.uvBinary.path, "venv", StoragePaths.aiRuntimeVenv.path, "--python", "3.12"]))
        XCTAssertTrue(recordedCommands.contains([
            StoragePaths.uvBinary.path,
            "pip",
            "install",
            "--python",
            StoragePaths.aiRuntimePython.path,
            "mlx-lm==0.31.2",
        ]))

        let record = try JSONDecoder().decode(
            VerifiedLocalAIRuntimeRecord.self,
            from: Data(contentsOf: StoragePaths.aiRuntimeVerificationFile)
        )
        XCTAssertEqual(record.recordVersion, 1)
        XCTAssertEqual(record.pythonMajorMinor, "3.12")
        XCTAssertEqual(record.mlxLMVersion, "0.31.2")
        XCTAssertEqual(record.helperProtocolVersion, 1)
    }

    func testEnsureRuntimeReadyInstallsBundledSeedWithoutRunningUV() async throws {
        let seedDirectory = tempRoot.appendingPathComponent("BundledRuntimeSeed")
        let seedPython = seedDirectory.appendingPathComponent("venv/bin/python")
        try Self.writeFakePythonLauncher(to: seedPython)

        let commandLog = LockedArray<[String]>()
        let client = MLXLMRuntimeClient(
            bundledSeedDirectoryProvider: { seedDirectory },
            helperScriptURLProvider: { throw LocalAIRuntimeError.helperScriptMissing },
            commandRunner: { executable, arguments, _, _, _, _ in
                commandLog.append([executable.path] + arguments)

                if executable == StoragePaths.aiRuntimePython, arguments.first == "-c" {
                    return .init(
                        stdout: #"{"python":"3.12.9","mlx_lm":"0.31.2"}"# + "\n",
                        stderr: "",
                        exitCode: 0
                    )
                }

                XCTFail("Bundled seed install should not invoke uv")
                return .init(stdout: "", stderr: "", exitCode: 1)
            }
        )

        try await client.ensureRuntimeReady()

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: StoragePaths.aiRuntimePython.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: StoragePaths.aiRuntimeVerificationFile.path))
        let recordedCommands = commandLog.snapshot()
        XCTAssertEqual(recordedCommands.count, 1)
        XCTAssertEqual(recordedCommands.first?.first, StoragePaths.aiRuntimePython.path)
        XCTAssertEqual(recordedCommands.first?[1], "-c")
    }

    func testRuntimeClientStreamsCancelsRestartsAndUnloadsHelper() async throws {
        try StoragePaths.ensureDirectoriesExist()
        try Self.writeFakePythonLauncher(to: StoragePaths.aiRuntimePython)
        try Self.writeRuntimeRecord()
        let helperScriptURL = try Self.writeFakeHelperScript(to: tempRoot.appendingPathComponent("fake_helper.sh"))

        let client = MLXLMRuntimeClient(
            bundledSeedDirectoryProvider: { nil },
            helperScriptURLProvider: { helperScriptURL },
            commandRunner: { executable, arguments, _, _, _, _ in
                if executable == StoragePaths.aiRuntimePython, arguments.first == "-c" {
                    return .init(
                        stdout: #"{"python":"3.12.9","mlx_lm":"0.31.2"}"# + "\n",
                        stderr: "",
                        exitCode: 0
                    )
                }

                XCTFail("Unexpected command during helper test: \(executable.path) \(arguments.joined(separator: " "))")
                return .init(stdout: "", stderr: "", exitCode: 1)
            }
        )

        let modelDirectory = StoragePaths.modelDirectory(for: "helper-test-model")
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        try await client.loadModel(at: modelDirectory, modelID: "helper-test-model")
        try await client.healthCheck()
        XCTAssertEqual(client.loadedModelID, "helper-test-model")

        let cancelledChunks = LockedArray<String>()
        let firstChunk = expectation(description: "received partial chunk before cancellation")
        let cancelledTask = Task {
            try await client.streamGenerate(
                messages: [LocalAIChatMessage(role: .user, content: "cancel me")],
                maxTokens: 64
            ) { chunk in
                cancelledChunks.append(chunk)
                if chunk == "partial" {
                    firstChunk.fulfill()
                }
            }
        }

        await fulfillment(of: [firstChunk], timeout: 2.0)
        client.cancelGeneration()

        do {
            _ = try await cancelledTask.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(cancelledChunks.snapshot(), ["partial"])
        }

        XCTAssertNil(client.loadedModelID)

        try await client.loadModel(at: modelDirectory, modelID: "helper-test-model")
        try await client.healthCheck()

        let streamedChunks = LockedArray<String>()
        let response = try await client.streamGenerate(
            messages: [LocalAIChatMessage(role: .user, content: "say hello")],
            maxTokens: 64
        ) { chunk in
            streamedChunks.append(chunk)
        }

        XCTAssertEqual(streamedChunks.snapshot(), ["Hello", " world"])
        XCTAssertEqual(response, "Hello world")

        await client.unloadModel()
        XCTAssertNil(client.loadedModelID)
    }

    nonisolated private static func writeFakePythonLauncher(to url: URL) throws {
        let launcher = """
        #!/bin/sh
        if [ "$1" = "-c" ]; then
          printf '%s\\n' '{"python":"3.12.9","mlx_lm":"0.31.2"}'
          exit 0
        fi
        exec "$@"
        """

        try writeExecutable(launcher, to: url)
    }

    nonisolated private static func writeRuntimeRecord() throws {
        let record = VerifiedLocalAIRuntimeRecord(
            recordVersion: 1,
            pythonMajorMinor: "3.12",
            mlxLMVersion: "0.31.2",
            helperProtocolVersion: 1,
            verifiedAt: Date()
        )
        let data = try JSONEncoder().encode(record)
        try StoragePaths.ensureDirectoriesExist()
        try data.write(to: StoragePaths.aiRuntimeVerificationFile, options: .atomic)
    }

    nonisolated private static func writeFakeHelperScript(to url: URL) throws -> URL {
        let script = """
        #!/bin/sh
        extract_id() {
          printf '%s' "$1" | sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p'
        }

        printf '%s\\n' '{"event":"ready","protocolVersion":1}'

        while IFS= read -r line; do
          id="$(extract_id "$line")"
          case "$line" in
            *'"command":"loadModel"'*)
              printf '{"id":"%s","event":"loaded"}\\n' "$id"
              ;;
            *'"command":"health"'*)
              printf '{"id":"%s","event":"healthy","loadedModelPath":"helper-test-model"}\\n' "$id"
              ;;
            *'"command":"unloadModel"'*)
              printf '{"id":"%s","event":"unloaded"}\\n' "$id"
              ;;
            *'"command":"generate"'*)
              case "$line" in
                *'cancel me'*)
                  printf '{"id":"%s","event":"token","text":"partial"}\\n' "$id"
                  sleep 10
                  ;;
                *)
                  printf '{"id":"%s","event":"token","text":"Hello"}\\n' "$id"
                  printf '{"id":"%s","event":"token","text":" world"}\\n' "$id"
                  printf '{"id":"%s","event":"done","text":"Hello world"}\\n' "$id"
                  ;;
              esac
              ;;
            *)
              printf '{"id":"%s","event":"error","message":"unsupported"}\\n' "$id"
              ;;
          esac
        done
        """

        try writeExecutable(script, to: url)
        return url
    }

    nonisolated private static func writeExecutable(_ contents: String, to url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

private final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ element: Element) {
        lock.lock()
        storage.append(element)
        lock.unlock()
    }

    func snapshot() -> [Element] {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        return snapshot
    }
}
