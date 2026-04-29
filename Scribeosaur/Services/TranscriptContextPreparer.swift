import CryptoKit
import Foundation

struct PreparedTranscriptContextChunk: Equatable, Sendable {
    let sortOrder: Int
    let content: String
    let summary: String
}

struct PreparedTranscriptContext: Equatable, Sendable {
    let transcriptId: Int64
    let contentHash: String
    let normalizedText: String
    let memorySummary: String
    let chunks: [PreparedTranscriptContextChunk]
    let updatedAt: Date

    var isLongTranscript: Bool {
        normalizedText.count > TranscriptAIUtilities.maxInlineTranscriptCharacters
    }

    func transcriptBody(maxCharacters: Int = TranscriptAIUtilities.maxInlineTranscriptCharacters) -> String {
        guard isLongTranscript else {
            return normalizedText
        }

        var body = """
        Prepared transcript memory:

        Overall memory summary:
        \(memorySummary)

        Chunk summaries:
        \(chunks.map { "- Chunk \($0.sortOrder + 1): \($0.summary)" }.joined(separator: "\n"))
        """

        let excerptBudget = max(maxCharacters - body.count - 400, 0)
        guard excerptBudget > 0 else { return body }

        var excerpts: [String] = []
        var usedCharacters = 0

        for chunk in chunks {
            guard usedCharacters < excerptBudget else { break }
            let remaining = excerptBudget - usedCharacters
            let excerpt = String(chunk.content.prefix(remaining))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !excerpt.isEmpty else { continue }
            excerpts.append("""
            ## Cached source chunk \(chunk.sortOrder + 1)
            \(excerpt)
            """)
            usedCharacters += excerpt.count
        }

        if !excerpts.isEmpty {
            body += "\n\nCached source excerpts:\n\(excerpts.joined(separator: "\n\n"))"
        }

        return body
    }
}

@MainActor
final class TranscriptContextPreparer {
    private let repository: TranscriptRepository
    private let isAIServiceBusy: @MainActor () -> Bool
    private let busyRetryDelay: Duration

    init(
        repository: TranscriptRepository,
        busyRetryDelay: Duration = .seconds(2),
        isAIServiceBusy: @escaping @MainActor () -> Bool = { false }
    ) {
        self.repository = repository
        self.isAIServiceBusy = isAIServiceBusy
        self.busyRetryDelay = busyRetryDelay
    }

    func preparedContext(
        transcript: Transcript,
        segments: [TranscriptSegment]
    ) throws -> PreparedTranscriptContext? {
        guard let transcriptId = transcript.id else { return nil }

        let normalizedText = Self.normalizedTranscriptText(from: transcript, segments: segments)
        let contentHash = Self.contentHash(for: normalizedText)

        guard let stored = try repository.fetchContextCacheWithChunks(transcriptId: transcriptId),
              stored.cache.status == .ready,
              stored.cache.contentHash == contentHash
        else {
            return nil
        }

        return PreparedTranscriptContext(
            transcriptId: transcriptId,
            contentHash: contentHash,
            normalizedText: stored.cache.normalizedText,
            memorySummary: stored.cache.memorySummary,
            chunks: stored.chunks.map {
                PreparedTranscriptContextChunk(
                    sortOrder: $0.sortOrder,
                    content: $0.content,
                    summary: $0.summary
                )
            },
            updatedAt: stored.cache.updatedAt
        )
    }

    func prepareIfNeeded(
        transcript: Transcript,
        segments: [TranscriptSegment],
        waitForUserAI: Bool
    ) async {
        guard let transcriptId = transcript.id else { return }

        let normalizedText = Self.normalizedTranscriptText(from: transcript, segments: segments)
        let contentHash = Self.contentHash(for: normalizedText)

        do {
            if let existing = try repository.fetchContextCache(transcriptId: transcriptId),
               existing.status == .ready,
               existing.contentHash == contentHash {
                return
            }

            if waitForUserAI {
                while isAIServiceBusy() && !Task.isCancelled {
                    try? await Task.sleep(for: busyRetryDelay)
                }
            }
            guard !Task.isCancelled else { return }

            var preparingCache = TranscriptContextCache(
                id: nil,
                transcriptId: transcriptId,
                contentHash: contentHash,
                status: .preparing,
                normalizedText: normalizedText,
                memorySummary: "",
                errorMessage: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            try repository.replaceContextCache(&preparingCache, chunks: [])

            var built = Self.buildCachePayload(
                transcript: transcript,
                transcriptId: transcriptId,
                normalizedText: normalizedText,
                contentHash: contentHash
            )
            try repository.replaceContextCache(&built.cache, chunks: built.chunks)
        } catch {
            do {
                var failedCache = TranscriptContextCache(
                    id: nil,
                    transcriptId: transcriptId,
                    contentHash: contentHash,
                    status: .failed,
                    normalizedText: normalizedText,
                    memorySummary: "",
                    errorMessage: error.localizedDescription,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                try repository.replaceContextCache(&failedCache, chunks: [])
            } catch {
                AppLogger.error(
                    "TranscriptContext",
                    "Failed to persist context failure for transcript \(transcriptId): \(error.localizedDescription)"
                )
            }

            AppLogger.error(
                "TranscriptContext",
                "Failed to prepare context for transcript \(transcriptId): \(error.localizedDescription)"
            )
        }
    }

    static func normalizedTranscriptText(
        from transcript: Transcript,
        segments: [TranscriptSegment]
    ) -> String {
        let rawText = TranscriptAIUtilities.transcriptText(from: transcript, segments: segments)
        let normalizedLineEndings = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalizedLineEndings
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return lines
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contentHash(for normalizedText: String) -> String {
        let digest = SHA256.hash(data: Data(normalizedText.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func buildCachePayload(
        transcript: Transcript,
        transcriptId: Int64,
        normalizedText: String,
        contentHash: String
    ) -> (cache: TranscriptContextCache, chunks: [TranscriptContextChunk]) {
        let chunks = TranscriptAIUtilities.transcriptChunks(from: normalizedText)
        let now = Date()
        let chunkRecords = chunks.enumerated().map { index, chunk in
            TranscriptContextChunk(
                id: nil,
                cacheId: 0,
                transcriptId: transcriptId,
                sortOrder: index,
                content: chunk,
                summary: lightweightSummary(for: chunk, index: index, total: chunks.count),
                createdAt: now
            )
        }

        let summary = overallSummary(
            transcript: transcript,
            normalizedText: normalizedText,
            chunkSummaries: chunkRecords.map(\.summary)
        )

        let cache = TranscriptContextCache(
            id: nil,
            transcriptId: transcriptId,
            contentHash: contentHash,
            status: .ready,
            normalizedText: normalizedText,
            memorySummary: summary,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now
        )
        return (cache, chunkRecords)
    }

    private static func lightweightSummary(for chunk: String, index: Int, total: Int) -> String {
        let collapsed = chunk
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = String(collapsed.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines)
        return total == 1
            ? excerpt
            : "Part \(index + 1) of \(total): \(excerpt)"
    }

    private static func overallSummary(
        transcript: Transcript,
        normalizedText: String,
        chunkSummaries: [String]
    ) -> String {
        let source = chunkSummaries.isEmpty ? normalizedText : chunkSummaries.joined(separator: " ")
        let excerpt = String(source.prefix(1_600)).trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        \(transcript.title)
        Cached transcript memory with \(chunkSummaries.count) chunk\(chunkSummaries.count == 1 ? "" : "s").
        \(excerpt)
        """
    }
}
