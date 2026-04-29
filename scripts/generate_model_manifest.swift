#!/usr/bin/swift

import CryptoKit
import Foundation

struct ManifestAsset: Codable {
    let path: String
    let sizeBytes: Int64
    let checksum: String
}

struct ManifestDescriptor: Codable {
    let id: String
    let displayName: String
    let providerID: String
    let revision: String
    let estimatedDownloadSizeBytes: Int64
    let estimatedMemoryBytes: Int64
    let notes: String
    let assetFiles: [ManifestAsset]
}

enum ScriptError: LocalizedError {
    case invalidArguments(String)
    case curlFailed(String)
    case manifestOutOfDate(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let detail):
            "Invalid arguments: \(detail)"
        case .curlFailed(let detail):
            "curl failed: \(detail)"
        case .manifestOutOfDate(let path):
            "Manifest is stale: \(path)"
        }
    }
}

enum GenerateModelManifest {
    struct Options {
        let id: String
        let displayName: String
        let providerID: String
        let revision: String
        let estimatedMemoryBytes: Int64
        let notes: String
        let checkManifestPath: String?

        static let defaults = Options(
            id: "gemma-e4b-4bit-local",
            displayName: "Gemma 4 E4B (4-bit)",
            providerID: "unsloth/gemma-4-E4B-it-UD-MLX-4bit",
            revision: "52a9e17e759f23e63acf486834de990060319265",
            estimatedMemoryBytes: 5_368_709_120,
            notes: "Default local Gemma 4 E4B model for Apple Silicon.",
            checkManifestPath: nil
        )

        static func parse(arguments: [String]) throws -> Options {
            var values: [String: String] = [:]
            var index = 0

            while index < arguments.count {
                let key = arguments[index]
                guard key.hasPrefix("--") else {
                    throw ScriptError.invalidArguments("Unexpected argument: \(key)")
                }
                guard index + 1 < arguments.count else {
                    throw ScriptError.invalidArguments("Missing value for \(key)")
                }
                values[key] = arguments[index + 1]
                index += 2
            }

            return Options(
                id: values["--id"] ?? defaults.id,
                displayName: values["--display-name"] ?? defaults.displayName,
                providerID: values["--provider-id"] ?? defaults.providerID,
                revision: values["--revision"] ?? defaults.revision,
                estimatedMemoryBytes: Int64(values["--estimated-memory-bytes"] ?? "") ?? defaults.estimatedMemoryBytes,
                notes: values["--notes"] ?? defaults.notes,
                checkManifestPath: values["--check"]
            )
        }
    }

    private struct ModelAPIResponse: Decodable {
        struct Sibling: Decodable {
            let rfilename: String
        }

        let siblings: [Sibling]
    }

    static func run() throws {
        let options = try Options.parse(arguments: Array(CommandLine.arguments.dropFirst()))
        let manifest = try generateManifest(options: options)
        let outputData = try encodedManifestData(manifest)

        if let checkManifestPath = options.checkManifestPath {
            let manifestURL = URL(fileURLWithPath: checkManifestPath)
            let existingData = try Data(contentsOf: manifestURL)
            let normalizedExistingData = existingData.last == 0x0A
                ? existingData
                : existingData + Data("\n".utf8)

            guard normalizedExistingData == outputData else {
                throw ScriptError.manifestOutOfDate(checkManifestPath)
            }
            return
        }

        FileHandle.standardOutput.write(outputData)
    }

    private static func generateManifest(options: Options) throws -> ManifestDescriptor {
        let assetPaths = try discoverAssetPaths(
            providerID: options.providerID,
            revision: options.revision
        )
        let assets = try assetPaths.map { try buildAsset(path: $0, options: options) }

        return ManifestDescriptor(
            id: options.id,
            displayName: options.displayName,
            providerID: options.providerID,
            revision: options.revision,
            estimatedDownloadSizeBytes: assets.reduce(0) { $0 + $1.sizeBytes },
            estimatedMemoryBytes: options.estimatedMemoryBytes,
            notes: options.notes,
            assetFiles: assets
        )
    }

    private static func discoverAssetPaths(
        providerID: String,
        revision: String
    ) throws -> [String] {
        let apiURL = URL(
            string: "https://huggingface.co/api/models/\(providerID)/revision/\(revision)"
        )!
        let responseData = try Data(contentsOf: apiURL)
        let response = try JSONDecoder().decode(ModelAPIResponse.self, from: responseData)

        let explicitAssets = Set([
            "README.md",
            "chat_template.jinja",
            "config.json",
            "generation_config.json",
            "special_tokens_map.json",
            "tokenizer.json",
            "tokenizer.model",
            "tokenizer_config.json",
            "model.safetensors",
            "model.safetensors.index.json",
        ])

        return response.siblings
            .map(\.rfilename)
            .filter { filename in
                explicitAssets.contains(filename)
                    || (filename.hasPrefix("model-") && filename.hasSuffix(".safetensors"))
            }
            .sorted()
    }

    private static func buildAsset(path: String, options: Options) throws -> ManifestAsset {
        let url = remoteURL(for: path, providerID: options.providerID, revision: options.revision)
        let headers = try headHeaders(for: url)

        let resolvedSize = headers["x-linked-size"] ?? headers["content-length"]

        if let resolvedSize,
           let sizeBytes = Int64(resolvedSize),
           let remoteDigest = linkedContentDigest(from: headers) {
            return ManifestAsset(path: path, sizeBytes: sizeBytes, checksum: remoteDigest.lowercased())
        }

        let data = try Data(contentsOf: url)
        return ManifestAsset(
            path: path,
            sizeBytes: Int64(data.count),
            checksum: sha256(of: data)
        )
    }

    private static func remoteURL(for path: String, providerID: String, revision: String) -> URL {
        URL(
            string: "https://huggingface.co/\(providerID)/resolve/\(revision)/\(path)"
        )!
    }

    private static func headHeaders(for url: URL) throws -> [String: String] {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-fsSLI", url.absoluteString]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            throw ScriptError.curlFailed(stderr.isEmpty ? stdout : stderr)
        }

        var headers: [String: String] = [:]
        for line in stdout.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            headers[key] = value
        }
        return headers
    }

    private static func linkedContentDigest(from headers: [String: String]) -> String? {
        guard let value = headers["x-linked-etag"] else {
            return nil
        }

        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard normalized.count == 64,
              normalized.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil else {
            return nil
        }

        return normalized
    }

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func encodedManifestData(_ manifest: ManifestDescriptor) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest) + Data("\n".utf8)
    }
}

try GenerateModelManifest.run()
