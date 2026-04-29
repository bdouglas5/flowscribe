import Foundation

protocol ModelAssetDownloading {
    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws
}

struct CurlModelAssetDownloader: ModelAssetDownloading {
    private let curlURL: URL
    private let fileManager: FileManager

    init(
        curlURL: URL = URL(fileURLWithPath: "/usr/bin/curl"),
        fileManager: FileManager = .default
    ) {
        self.curlURL = curlURL
        self.fileManager = fileManager
    }

    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let process = Process()
        let stderrPipe = Pipe()

        process.executableURL = curlURL
        process.arguments = [
            "--fail",
            "--location",
            "--continue-at", "-",
            "--output", destinationURL.path,
            remoteURL.absoluteString
        ]
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        try process.run()

        while process.isRunning {
            onProgress(fileSize(at: destinationURL))
            try? await Task.sleep(for: .milliseconds(250))
        }

        onProgress(fileSize(at: destinationURL))

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw SubprocessError.executionFailed(
                stderr.isEmpty ? "curl failed to download \(remoteURL.lastPathComponent)" : stderr,
                process.terminationStatus
            )
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
