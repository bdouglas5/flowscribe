import Foundation
import AppKit

enum ExportService {
    static func markdownContent(
        transcript: Transcript,
        segments: [TranscriptSegment],
        showTimestamps: Bool
    ) -> String {
        var md = "# \(transcript.title)\n"

        switch transcript.sourceType {
        case .url:
            md += "**Source:** [\(transcript.sourcePath)](\(transcript.sourcePath))\n"
        case .file:
            md += "**Source:** Local file\n"
        case .recording:
            md += "**Source:** Recorded in Scribeosaur\n"
        }

        md += "**Date:** \(TimeFormatting.formattedDate(transcript.createdAt))\n"

        if let duration = transcript.durationSeconds, duration > 0 {
            md += "**Duration:** \(TimeFormatting.duration(seconds: duration))\n"
        }

        if transcript.speakerDetection {
            let speakers = Set(segments.compactMap(\.speakerName)).sorted()
            if !speakers.isEmpty {
                md += "**Speakers:** \(speakers.joined(separator: ", "))\n"
            }
        }

        md += "\n---\n\n"

        for segment in segments {
            var line = ""
            if showTimestamps {
                line += "\(TimeFormatting.bracketedRange(start: segment.startTime, end: segment.endTime)) "
            }
            if let name = segment.speakerName {
                line += "\(name): "
            }
            line += segment.text
            md += line + "\n\n"
        }

        return md
    }

    static func copyToClipboard(
        segments: [TranscriptSegment],
        showTimestamps: Bool
    ) {
        let text = segments.map { segment in
            var line = ""
            if showTimestamps {
                line += "\(TimeFormatting.bracketedRange(start: segment.startTime, end: segment.endTime)) "
            }
            if let name = segment.speakerName {
                line += "\(name): "
            }
            line += segment.text
            return line
        }.joined(separator: "\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func exportMarkdown(
        transcript: Transcript,
        segments: [TranscriptSegment],
        showTimestamps: Bool
    ) {
        let content = markdownContent(
            transcript: transcript,
            segments: segments,
            showTimestamps: showTimestamps
        )

        let panel = NSSavePanel()
        panel.title = "Export Transcript"
        panel.nameFieldStringValue = "\(transcript.title).md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func exportAIMarkdown(
        transcript: Transcript,
        aiResult: TranscriptAIResult
    ) {
        let md = aiMarkdownContent(transcript: transcript, aiResult: aiResult)

        let panel = NSSavePanel()
        panel.title = "Export AI Result"
        panel.nameFieldStringValue = "\(sanitizedFileName(from: "\(transcript.title) - \(aiResult.promptTitle)")).md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func exportAllAIMarkdown(
        transcript: Transcript,
        aiResults: [TranscriptAIResult]
    ) {
        guard !aiResults.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.title = "Export AI Documents"
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { folderURL.stopAccessingSecurityScopedResource() }
        }

        for result in aiResults {
            let baseName = sanitizedFileName(from: "\(transcript.title) - \(result.promptTitle)")
            let fileURL = uniqueMarkdownURL(in: folderURL, baseName: baseName)
            let content = aiMarkdownContent(transcript: transcript, aiResult: result)
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    static func autoExport(
        transcript: Transcript,
        segments: [TranscriptSegment],
        to folderURL: URL,
        showTimestamps: Bool
    ) throws {
        let content = markdownContent(
            transcript: transcript,
            segments: segments,
            showTimestamps: showTimestamps
        )

        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { folderURL.stopAccessingSecurityScopedResource() }
        }

        let sanitized = sanitizedFileName(from: transcript.title)
        var fileURL = folderURL.appendingPathComponent("\(sanitized).md")
        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = folderURL.appendingPathComponent("\(sanitized) \(counter).md")
            counter += 1
        }

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func autoExportAIContent(
        title: String,
        promptTitle: String,
        content: String,
        to folderURL: URL
    ) throws {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { folderURL.stopAccessingSecurityScopedResource() }
        }

        let sanitized = sanitizedFileName(from: "\(title) - \(promptTitle)")
        var fileURL = folderURL.appendingPathComponent("\(sanitized).md")
        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = folderURL.appendingPathComponent("\(sanitized) \(counter).md")
            counter += 1
        }

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func aiMarkdownContent(
        transcript: Transcript,
        aiResult: TranscriptAIResult
    ) -> String {
        var md = "# \(transcript.title) - \(aiResult.promptTitle)\n"
        md += "**Date:** \(TimeFormatting.formattedDate(aiResult.createdAt))\n"
        md += "**Prompt:** \(aiResult.promptTitle)\n"
        md += "\n---\n\n"
        md += aiResult.content
        return md
    }

    private static func uniqueMarkdownURL(in folderURL: URL, baseName: String) -> URL {
        var fileURL = folderURL.appendingPathComponent("\(baseName).md")
        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = folderURL.appendingPathComponent("\(baseName) \(counter).md")
            counter += 1
        }
        return fileURL
    }

    private static func sanitizedFileName(from title: String) -> String {
        String(
            title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .prefix(100)
        )
    }
}
