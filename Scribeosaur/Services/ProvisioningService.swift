import Foundation

@Observable
final class ProvisioningService {
    var isProvisioning = false
    var progress: Double = 0.0
    var statusMessage = ""
    var error: String?
    var startupStage: ProvisioningStage = .idle
    var startupStageProgress: Double = 0.0

    private static let ffmpegURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip")!
    private static let ytdlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    private static let denoURL = URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip")!
    private static let uvURL = URL(string: "https://github.com/astral-sh/uv/releases/latest/download/uv-aarch64-apple-darwin.tar.gz")!

    var binariesReady: Bool {
        StoragePaths.ffmpegExists && StoragePaths.ytdlpExists && StoragePaths.denoExists && StoragePaths.uvExists
    }

    var allDependenciesReady: Bool {
        binariesReady
    }

    func provisionIfNeeded() async {
        let ffmpegReady = await validateFFmpeg()
        let ytDLPReady = await validateYTDLP()
        let denoReady = await validateDeno()
        let uvReady = await validateUV()

        AppLogger.info(
            "Dependencies",
            "Checking dependencies. ffmpeg=\(ffmpegReady) yt-dlp=\(ytDLPReady) deno=\(denoReady) uv=\(uvReady)"
        )

        await MainActor.run {
            isProvisioning = true
            error = nil
            statusMessage = "Checking dependencies..."
            progress = 0.05
            startupStage = .checking
            startupStageProgress = 0.05
        }

        do {
            if !ffmpegReady {
                if !(try installBundledBinaryIfPresent(
                    candidates: ["ffmpeg"],
                    destination: StoragePaths.ffmpegBinary
                )) {
                    try await downloadFFmpeg()
                }
            }

            if !ytDLPReady {
                if !(try installBundledBinaryIfPresent(
                    candidates: ["yt-dlp", "yt-dlp_macos"],
                    destination: StoragePaths.ytdlpBinary
                )) {
                    try await downloadYTDLP()
                }
            }

            if !denoReady {
                if !(try installBundledBinaryIfPresent(
                    candidates: ["deno"],
                    destination: StoragePaths.denoBinary
                )) {
                    try await downloadDeno()
                }
            }

            if !uvReady {
                if !(try installBundledBinaryIfPresent(
                    candidates: ["uv"],
                    destination: StoragePaths.uvBinary
                )) {
                    try await downloadUV()
                }
            }

            await MainActor.run {
                isProvisioning = false
                statusMessage = "Dependencies ready"
                progress = 1.0
                startupStage = .ready
                startupStageProgress = 1.0
            }
            AppLogger.info("Dependencies", "All managed dependencies are ready")
        } catch {
            AppLogger.error("Dependencies", "Dependency setup failed: \(error.localizedDescription)")
            await MainActor.run {
                self.error = error.localizedDescription
                self.isProvisioning = false
                self.startupStage = .failed
            }
        }
    }

    private func installBundledBinaryIfPresent(
        candidates: [String],
        destination: URL
    ) throws -> Bool {
        let sourceURL = candidates.compactMap { StoragePaths.bundledBinary(named: $0) }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }

        guard let sourceURL else {
            return false
        }

        try StoragePaths.ensureDirectoriesExist()
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: sourceURL, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)

        AppLogger.info("Dependencies", "Installed bundled binary \(sourceURL.lastPathComponent)")
        return true
    }

    private func downloadFFmpeg() async throws {
        AppLogger.info("Dependencies", "Downloading ffmpeg")
        await MainActor.run {
            statusMessage = "Downloading ffmpeg..."
            progress = 0.15
            startupStage = .preparingResources
            startupStageProgress = 0.15
        }

        try StoragePaths.ensureDirectoriesExist()

        let (zipTemp, _) = try await URLSession.shared.download(from: Self.ffmpegURL)
        let zipPath = StoragePaths.temp.appendingPathComponent("ffmpeg.zip")
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: zipPath.path) {
            try fileManager.removeItem(at: zipPath)
        }
        try fileManager.moveItem(at: zipTemp, to: zipPath)

        let extractDir = StoragePaths.temp.appendingPathComponent("ffmpeg_extract")
        if fileManager.fileExists(atPath: extractDir.path) {
            try fileManager.removeItem(at: extractDir)
        }
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

        await MainActor.run {
            progress = 0.35
            startupStage = .preparingResources
            startupStageProgress = 0.35
        }

        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzipProcess.arguments = ["-xk", zipPath.path, extractDir.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        guard unzipProcess.terminationStatus == 0 else {
            throw SubprocessError.executionFailed("Failed to unzip ffmpeg archive.", unzipProcess.terminationStatus)
        }

        await MainActor.run {
            progress = 0.45
            startupStage = .preparingResources
            startupStageProgress = 0.45
        }

        let enumerator = fileManager.enumerator(at: extractDir, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.lastPathComponent == "ffmpeg" else { continue }

            if fileManager.fileExists(atPath: StoragePaths.ffmpegBinary.path) {
                try fileManager.removeItem(at: StoragePaths.ffmpegBinary)
            }
            try fileManager.moveItem(at: fileURL, to: StoragePaths.ffmpegBinary)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: StoragePaths.ffmpegBinary.path
            )
            AppLogger.info("Dependencies", "ffmpeg installed at \(StoragePaths.ffmpegBinary.path)")
            return
        }

        throw SubprocessError.binaryNotFound("ffmpeg not found in downloaded archive")
    }

    private func downloadYTDLP() async throws {
        AppLogger.info("Dependencies", "Downloading yt-dlp")
        await MainActor.run {
            statusMessage = "Downloading yt-dlp..."
            progress = 0.65
            startupStage = .preparingResources
            startupStageProgress = 0.65
        }

        let (tempURL, _) = try await URLSession.shared.download(from: Self.ytdlpURL)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: StoragePaths.ytdlpBinary.path) {
            try fileManager.removeItem(at: StoragePaths.ytdlpBinary)
        }
        try fileManager.moveItem(at: tempURL, to: StoragePaths.ytdlpBinary)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: StoragePaths.ytdlpBinary.path)

        await MainActor.run {
            progress = 0.95
            startupStage = .finalizing
            startupStageProgress = 0.95
        }
        AppLogger.info("Dependencies", "yt-dlp installed at \(StoragePaths.ytdlpBinary.path)")
    }

    private func downloadDeno() async throws {
        AppLogger.info("Dependencies", "Downloading deno")
        await MainActor.run {
            statusMessage = "Downloading deno..."
            progress = 0.75
            startupStage = .preparingResources
            startupStageProgress = 0.75
        }

        try StoragePaths.ensureDirectoriesExist()

        let (zipTemp, _) = try await URLSession.shared.download(from: Self.denoURL)
        let zipPath = StoragePaths.temp.appendingPathComponent("deno.zip")
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: zipPath.path) {
            try fileManager.removeItem(at: zipPath)
        }
        try fileManager.moveItem(at: zipTemp, to: zipPath)

        let extractDir = StoragePaths.temp.appendingPathComponent("deno_extract")
        if fileManager.fileExists(atPath: extractDir.path) {
            try fileManager.removeItem(at: extractDir)
        }
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzipProcess.arguments = ["-xk", zipPath.path, extractDir.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        guard unzipProcess.terminationStatus == 0 else {
            throw SubprocessError.executionFailed("Failed to unzip deno archive.", unzipProcess.terminationStatus)
        }

        let denoSource = extractDir.appendingPathComponent("deno")
        guard fileManager.fileExists(atPath: denoSource.path) else {
            throw SubprocessError.binaryNotFound("deno not found in downloaded archive")
        }

        if fileManager.fileExists(atPath: StoragePaths.denoBinary.path) {
            try fileManager.removeItem(at: StoragePaths.denoBinary)
        }
        try fileManager.moveItem(at: denoSource, to: StoragePaths.denoBinary)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: StoragePaths.denoBinary.path)

        await MainActor.run {
            progress = 0.9
            startupStage = .finalizing
            startupStageProgress = 0.9
        }
        AppLogger.info("Dependencies", "deno installed at \(StoragePaths.denoBinary.path)")
    }

    private func downloadUV() async throws {
        AppLogger.info("Dependencies", "Downloading uv")
        await MainActor.run {
            statusMessage = "Downloading uv..."
            progress = 0.9
            startupStage = .finalizing
            startupStageProgress = 0.9
        }

        try StoragePaths.ensureDirectoriesExist()

        let (archiveTemp, _) = try await URLSession.shared.download(from: Self.uvURL)
        let archivePath = StoragePaths.temp.appendingPathComponent("uv.tar.gz")
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: archivePath.path) {
            try fileManager.removeItem(at: archivePath)
        }
        try fileManager.moveItem(at: archiveTemp, to: archivePath)

        let extractDir = StoragePaths.temp.appendingPathComponent("uv_extract")
        if fileManager.fileExists(atPath: extractDir.path) {
            try fileManager.removeItem(at: extractDir)
        }
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let tarProcess = Process()
        tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProcess.arguments = ["-xzf", archivePath.path, "-C", extractDir.path]
        try tarProcess.run()
        tarProcess.waitUntilExit()

        guard tarProcess.terminationStatus == 0 else {
            throw SubprocessError.executionFailed("Failed to extract uv archive.", tarProcess.terminationStatus)
        }

        let enumerator = fileManager.enumerator(at: extractDir, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.lastPathComponent == "uv" else { continue }

            if fileManager.fileExists(atPath: StoragePaths.uvBinary.path) {
                try fileManager.removeItem(at: StoragePaths.uvBinary)
            }
            try fileManager.moveItem(at: fileURL, to: StoragePaths.uvBinary)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: StoragePaths.uvBinary.path
            )
            await MainActor.run {
                progress = 1.0
                startupStage = .ready
                startupStageProgress = 1.0
            }
            AppLogger.info("Dependencies", "uv installed at \(StoragePaths.uvBinary.path)")
            return
        }

        throw SubprocessError.binaryNotFound("uv not found in downloaded archive")
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

    private func validateDeno() async -> Bool {
        guard StoragePaths.denoExists else { return false }
        do {
            let output = try await SubprocessRunner.run(
                executable: StoragePaths.denoBinary,
                arguments: ["--version"]
            )
            return output.exitCode == 0
        } catch {
            AppLogger.error("Dependencies", "deno validation failed: \(error.localizedDescription)")
            return false
        }
    }

    private func validateUV() async -> Bool {
        guard StoragePaths.uvExists else { return false }
        do {
            let output = try await SubprocessRunner.run(
                executable: StoragePaths.uvBinary,
                arguments: ["--version"]
            )
            return output.exitCode == 0
        } catch {
            AppLogger.error("Dependencies", "uv validation failed: \(error.localizedDescription)")
            return false
        }
    }
}
