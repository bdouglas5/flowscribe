import Foundation

enum TranscriptMarkdownFileStorage {
    static func transcriptDirectory(transcriptID: Int64) throws -> URL {
        try StoragePaths.ensureDirectoriesExist()
        let directory = StoragePaths.transcriptFilesDirectory(transcriptID: transcriptID)
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func writeMarkdown(
        title: String,
        content: String,
        transcriptID: Int64
    ) throws -> (fileName: String, url: URL) {
        let directory = try transcriptDirectory(transcriptID: transcriptID)
        let fileName = uniqueFileName(in: directory, baseName: sanitizedFileName(from: title))
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return (fileName, url)
    }

    static func url(for file: TranscriptMarkdownFile) -> URL {
        StoragePaths.transcriptFilesDirectory(transcriptID: file.transcriptId)
            .appendingPathComponent(file.fileName, isDirectory: false)
    }

    static func read(_ file: TranscriptMarkdownFile) throws -> String {
        try String(contentsOf: url(for: file), encoding: .utf8)
    }

    static func exists(_ file: TranscriptMarkdownFile) -> Bool {
        FileManager.default.fileExists(atPath: url(for: file).path)
    }

    static func delete(_ file: TranscriptMarkdownFile) throws {
        let fileURL = url(for: file)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    static func deleteTranscriptDirectory(transcriptID: Int64) throws {
        let directory = StoragePaths.transcriptFilesDirectory(transcriptID: transcriptID)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    static func sanitizedFileName(from title: String) -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let components = title.components(separatedBy: illegalCharacters)
        let sanitized = components
            .joined(separator: "-")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = String(sanitized.prefix(100))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    static func uniqueFileName(in directory: URL, baseName: String) -> String {
        let safeBaseName = sanitizedFileName(from: baseName)
        let fm = FileManager.default
        var candidate = "\(safeBaseName).md"
        var counter = 1

        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(safeBaseName) \(counter).md"
            counter += 1
        }

        return candidate
    }
}
