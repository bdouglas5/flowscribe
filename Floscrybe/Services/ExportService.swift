import Foundation
import AppKit

enum ExportService {
    static func markdownContent(
        transcript: Transcript,
        segments: [TranscriptSegment],
        showTimestamps: Bool
    ) -> String {
        var md = "# \(transcript.title)\n"
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

    private static func sanitizedFileName(from title: String) -> String {
        String(
            title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .prefix(100)
        )
    }
}
