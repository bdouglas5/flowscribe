import Foundation

@Observable
final class BinaryDownloadService {
    var isDownloading = false
    var progress: Double = 0.0
    var statusMessage = ""
    var error: String?

    private static let ffmpegURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/7z")!
    private static let ytdlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!

    var binariesReady: Bool {
        StoragePaths.ffmpegExists && StoragePaths.ytdlpExists
    }

    var allDependenciesReady: Bool {
        binariesReady
    }

    func downloadIfNeeded() async {
        let ffmpegReady = await validateFFmpeg()
        let ytDLPReady = await validateYTDLP()

        AppLogger.info(
            "Dependencies",
            "Checking dependencies. ffmpeg=\(ffmpegReady) yt-dlp=\(ytDLPReady)"
        )
        await MainActor.run {
            isDownloading = true
            error = nil
            statusMessage = "Checking dependencies..."
            progress = 0.05
        }

        do {
            if !ffmpegReady {
                try await downloadFFmpeg()
            }
            if !ytDLPReady {
                try await downloadYtdlp()
            }
            await MainActor.run {
                isDownloading = false
                statusMessage = "Dependencies ready"
                progress = 1.0
            }
            AppLogger.info("Dependencies", "All managed dependencies are ready")
        } catch {
            AppLogger.error("Dependencies", "Dependency setup failed: \(error.localizedDescription)")
            await MainActor.run {
                self.error = error.localizedDescription
                self.isDownloading = false
            }
        }
    }

    private func downloadFFmpeg() async throws {
        AppLogger.info("Dependencies", "Downloading ffmpeg")
        await MainActor.run {
            statusMessage = "Downloading ffmpeg..."
            progress = 0.1
        }

        try StoragePaths.ensureDirectoriesExist()

        let (tempURL, _) = try await URLSession.shared.download(from: Self.ffmpegURL)
        let archivePath = StoragePaths.temp.appendingPathComponent("ffmpeg.7z")
        let fm = FileManager.default
        if fm.fileExists(atPath: archivePath.path) {
            try fm.removeItem(at: archivePath)
        }
        try fm.moveItem(at: tempURL, to: archivePath)

        await MainActor.run { progress = 0.3 }

        // Extract 7z using ditto or 7z if available, fallback to direct binary download
        // Try direct binary URL as fallback
        let directURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip")!
        let (zipTemp, _) = try await URLSession.shared.download(from: directURL)
        let zipPath = StoragePaths.temp.appendingPathComponent("ffmpeg.zip")
        if fm.fileExists(atPath: zipPath.path) {
            try fm.removeItem(at: zipPath)
        }
        try fm.moveItem(at: zipTemp, to: zipPath)

        await MainActor.run { progress = 0.4 }

        // Unzip
        let extractDir = StoragePaths.temp.appendingPathComponent("ffmpeg_extract")
        if fm.fileExists(atPath: extractDir.path) {
            try fm.removeItem(at: extractDir)
        }
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzipProcess.arguments = ["-xk", zipPath.path, extractDir.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        await MainActor.run { progress = 0.45 }

        // Find the ffmpeg binary in extracted contents
        let enumerator = fm.enumerator(at: extractDir, includingPropertiesForKeys: nil)
        var foundBinary = false
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == "ffmpeg" {
                if fm.fileExists(atPath: StoragePaths.ffmpegBinary.path) {
                    try fm.removeItem(at: StoragePaths.ffmpegBinary)
                }
                try fm.moveItem(at: fileURL, to: StoragePaths.ffmpegBinary)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: StoragePaths.ffmpegBinary.path)
                foundBinary = true
                break
            }
        }

        if !foundBinary {
            throw SubprocessError.binaryNotFound("ffmpeg not found in archive")
        }

        await MainActor.run { progress = 0.5 }
        AppLogger.info("Dependencies", "ffmpeg installed at \(StoragePaths.ffmpegBinary.path)")
    }

    private func downloadYtdlp() async throws {
        AppLogger.info("Dependencies", "Downloading yt-dlp")
        await MainActor.run {
            statusMessage = "Downloading yt-dlp..."
            progress = 0.6
        }

        let (tempURL, _) = try await URLSession.shared.download(from: Self.ytdlpURL)
        let fm = FileManager.default

        if fm.fileExists(atPath: StoragePaths.ytdlpBinary.path) {
            try fm.removeItem(at: StoragePaths.ytdlpBinary)
        }
        try fm.moveItem(at: tempURL, to: StoragePaths.ytdlpBinary)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: StoragePaths.ytdlpBinary.path)

        await MainActor.run { progress = 1.0 }
        AppLogger.info("Dependencies", "yt-dlp installed at \(StoragePaths.ytdlpBinary.path)")
    }

    private func validateFFmpeg() async -> Bool {
        guard StoragePaths.ffmpegExists else { return false }
        do {
            let output = try await SubprocessRunner.run(
                executable: StoragePaths.ffmpegBinary,
                arguments: ["-version"]
            )
            return output.exitCode == 0
        } catch {
            AppLogger.error("Dependencies", "ffmpeg validation failed: \(error.localizedDescription)")
            return false
        }
    }

    private func validateYTDLP() async -> Bool {
        guard StoragePaths.ytdlpExists else { return false }
        do {
            let output = try await SubprocessRunner.run(
                executable: StoragePaths.ytdlpBinary,
                arguments: ["--version"]
            )
            return output.exitCode == 0
        } catch {
            AppLogger.error("Dependencies", "yt-dlp validation failed: \(error.localizedDescription)")
            return false
        }
    }
}
