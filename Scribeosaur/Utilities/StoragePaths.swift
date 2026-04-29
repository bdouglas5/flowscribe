import Foundation

enum StoragePaths {
    private static let appSupportName = "Scribeosaur"
    private static var appSupportOverride: URL?
    private static var bundledResourceRootOverride: URL?

    static var appSupport: URL {
        if let appSupportOverride {
            return appSupportOverride
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appSupportName)
    }

    static var bin: URL { appSupport.appendingPathComponent("bin") }
    static var models: URL { appSupport.appendingPathComponent("models") }
    static var aiRuntimeRoot: URL { appSupport.appendingPathComponent("ai-runtime") }
    static var aiRuntimeVenv: URL { aiRuntimeRoot.appendingPathComponent("venv") }
    static var aiRuntimePython: URL { aiRuntimeVenv.appendingPathComponent("bin/python") }
    static var aiRuntimeVerificationFile: URL { aiRuntimeRoot.appendingPathComponent(".verified.json") }
    static var database: URL { appSupport.appendingPathComponent("db") }
    static var logs: URL { appSupport.appendingPathComponent("logs") }
    static var recordings: URL { appSupport.appendingPathComponent("recordings") }
    static var transcriptFiles: URL { appSupport.appendingPathComponent("transcript-files") }
    static var temp: URL { appSupport.appendingPathComponent("temp") }

    static var databaseFile: URL { database.appendingPathComponent("scribeosaur.sqlite") }
    static var logFile: URL { logs.appendingPathComponent("scribeosaur.log") }
    static var ffmpegBinary: URL { bin.appendingPathComponent("ffmpeg") }
    static var ytdlpBinary: URL { bin.appendingPathComponent("yt-dlp") }
    static var denoBinary: URL { bin.appendingPathComponent("deno") }
    static var uvBinary: URL { bin.appendingPathComponent("uv") }

    static func modelDirectory(for modelID: String) -> URL {
        models.appendingPathComponent(modelID)
    }

    static func transcriptFilesDirectory(transcriptID: Int64) -> URL {
        transcriptFiles.appendingPathComponent(String(transcriptID), isDirectory: true)
    }

    static func modelVerificationFile(for modelID: String) -> URL {
        modelDirectory(for: modelID).appendingPathComponent(".verified.json")
    }

    static func bundledBinary(named name: String) -> URL? {
        bundledResourceRoot?
            .appendingPathComponent("Binaries", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
    }

    static func bundledModelSeedDirectory(for modelID: String) -> URL? {
        bundledResourceRoot?
            .appendingPathComponent("ModelSeed", isDirectory: true)
            .appendingPathComponent(modelID, isDirectory: true)
    }

    static func bundledAIRuntimeSeedDirectory() -> URL? {
        bundledResourceRoot?
            .appendingPathComponent("AIRuntimeSeed", isDirectory: true)
    }

    static func bundledResource(
        named name: String,
        withExtension fileExtension: String,
        subdirectory: String? = nil
    ) -> URL? {
        guard var url = bundledResourceRoot else { return nil }

        if let subdirectory, !subdirectory.isEmpty {
            url.appendPathComponent(subdirectory, isDirectory: true)
        }

        return url.appendingPathComponent("\(name).\(fileExtension)", isDirectory: false)
    }

    static func setAppSupportOverride(_ url: URL?) {
        appSupportOverride = url
    }

    static var hasAppSupportOverride: Bool {
        appSupportOverride != nil
    }

    static func setBundledResourceRootOverride(_ url: URL?) {
        bundledResourceRootOverride = url
    }

    static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        for dir in [appSupport, bin, models, aiRuntimeRoot, database, logs, recordings, transcriptFiles, temp] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    static func clearTemp() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: temp.path) {
            try fm.removeItem(at: temp)
        }
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    static var ffmpegExists: Bool {
        FileManager.default.isExecutableFile(atPath: ffmpegBinary.path)
    }

    static var ytdlpExists: Bool {
        FileManager.default.isExecutableFile(atPath: ytdlpBinary.path)
    }

    static var denoExists: Bool {
        FileManager.default.isExecutableFile(atPath: denoBinary.path)
    }

    static var uvExists: Bool {
        FileManager.default.isExecutableFile(atPath: uvBinary.path)
    }

    private static var bundledResourceRoot: URL? {
        bundledResourceRootOverride ?? Bundle.main.resourceURL
    }
}

enum AppLogLevel: String {
    case info = "INFO"
    case error = "ERROR"
}

enum AppLogger {
    private static let queue = DispatchQueue(label: "Scribeosaur.AppLogger")

    static func info(_ category: String, _ message: String) {
        write(level: .info, category: category, message: message)
    }

    static func error(_ category: String, _ message: String) {
        write(level: .error, category: category, message: message)
    }

    static func flush() {
        queue.sync {}
    }

    private static func write(level: AppLogLevel, category: String, message: String) {
        queue.async {
            do {
                try StoragePaths.ensureDirectoriesExist()

                let timestamp = ISO8601DateFormatter().string(from: Date())
                let line = "[\(timestamp)] [\(level.rawValue)] [\(category)] \(message)\n"
                let data = Data(line.utf8)
                let fm = FileManager.default

                if !fm.fileExists(atPath: StoragePaths.logFile.path) {
                    try data.write(to: StoragePaths.logFile, options: .atomic)
                    return
                }

                let handle = try FileHandle(forWritingTo: StoragePaths.logFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Avoid surfacing logging failures back into the app flow.
            }
        }
    }
}
