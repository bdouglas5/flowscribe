import Foundation

enum StoragePaths {
    private static let appSupportName = "Floscrybe"

    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appSupportName)
    }

    static var bin: URL { appSupport.appendingPathComponent("bin") }
    static var models: URL { appSupport.appendingPathComponent("models") }
    static var database: URL { appSupport.appendingPathComponent("db") }
    static var logs: URL { appSupport.appendingPathComponent("logs") }
    static var temp: URL { appSupport.appendingPathComponent("temp") }

    static var databaseFile: URL { database.appendingPathComponent("floscrybe.sqlite") }
    static var logFile: URL { logs.appendingPathComponent("floscrybe.log") }
    static var ffmpegBinary: URL { bin.appendingPathComponent("ffmpeg") }
    static var ytdlpBinary: URL { bin.appendingPathComponent("yt-dlp") }

    static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        for dir in [appSupport, bin, models, database, logs, temp] {
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
}

enum AppLogLevel: String {
    case info = "INFO"
    case error = "ERROR"
}

enum AppLogger {
    private static let queue = DispatchQueue(label: "Floscrybe.AppLogger")

    static func info(_ category: String, _ message: String) {
        write(level: .info, category: category, message: message)
    }

    static func error(_ category: String, _ message: String) {
        write(level: .error, category: category, message: message)
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
