import Foundation

enum PromptExecutionStrategy {
    case singleShot
    case chunkMap
    case chunkReduce
}

enum TranscriptAIUtilities {
    static let maxInlineTranscriptCharacters = 18_000
    static let transcriptChunkSize = 18_000
    private static let gemmaThoughtChannelPrefix = "<|channel>thought\n"
    private static let gemmaThoughtChannelSuffix = "<channel|>"

    static func executionStrategy(
        for promptTemplate: AIPromptTemplate,
        transcriptLength: Int
    ) -> PromptExecutionStrategy {
        guard transcriptLength > maxInlineTranscriptCharacters else {
            return .singleShot
        }

        if promptTemplate.id == AIPromptTemplate.cleanUp.id {
            return .chunkMap
        }

        return .chunkReduce
    }

    static func transcriptText(from transcript: Transcript, segments: [TranscriptSegment]) -> String {
        guard !segments.isEmpty else {
            return transcript.fullText
        }

        return segments
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { segment in
                var line = ""
                if let speakerName = segment.speakerName, !speakerName.isEmpty {
                    line += "\(speakerName): "
                }
                line += segment.text
                return line
            }
            .joined(separator: "\n\n")
    }

    static func buildPrompt(
        for promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        transcriptBody: String
    ) -> String {
        """
        You are helping inside Scribeosaur, a desktop transcription app.
        Work only from the transcript below. If information is missing, say so instead of guessing.
        Return concise Markdown.

        Task:
        \(promptTemplate.body)

        Transcript metadata:
        - Title: \(transcript.title)
        - Created: \(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))
        - Speaker detection: \(transcript.speakerDetection ? "enabled" : "disabled")
        - Speakers detected: \(transcript.speakerCount)

        Transcript:
        \(transcriptBody)
        """
    }

    static func buildTranscriptChatPrompt(
        for promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        transcriptBody: String
    ) -> String {
        """
        You are helping inside Scribeosaur's Transcript Chat side panel.
        Respond like a warm, concise chat assistant, not a document generator.

        Transcript metadata:
        - Title: \(transcript.title)
        - Created: \(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))
        - Speaker detection: \(transcript.speakerDetection ? "enabled" : "disabled")
        - Speakers detected: \(transcript.speakerCount)

        Transcript:
        \(transcriptBody)

        \(promptTemplate.body)
        """
    }

    static func buildTranscriptChatChunkPrompt(
        for promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        transcriptChunk: String,
        chunkIndex: Int,
        chunkCount: Int
    ) -> String {
        """
        You are helping inside Scribeosaur's Transcript Chat side panel.
        This is one chunk from a longer transcript.
        Find details in this chunk that help answer the latest user question.
        If this chunk has no relevant details, say only: No relevant details.

        Transcript metadata:
        - Title: \(transcript.title)
        - Chunk: \(chunkIndex) of \(chunkCount)

        Transcript chunk:
        \(transcriptChunk)

        \(promptTemplate.body)
        """
    }

    static func buildTranscriptChatMergePrompt(
        for promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        chunkOutputs: [String]
    ) -> String {
        """
        You are helping inside Scribeosaur's Transcript Chat side panel.
        Respond like a warm, concise chat assistant, not a document generator.
        Use the chunk findings below to answer the latest user question.
        If the findings do not contain the answer, say that naturally.
        Do not invent transcript details.

        Transcript metadata:
        - Title: \(transcript.title)
        - Chunks analyzed: \(chunkOutputs.count)

        Chunk findings:
        \(chunkOutputs.joined(separator: "\n\n"))

        \(promptTemplate.body)
        """
    }

    static func sanitizeModelResponse(_ response: String) -> String {
        var sanitized = response.trimmingCharacters(in: .whitespacesAndNewlines)

        while sanitized.hasPrefix(gemmaThoughtChannelPrefix) {
            let contentStart = sanitized.index(
                sanitized.startIndex,
                offsetBy: gemmaThoughtChannelPrefix.count
            )

            guard let closingRange = sanitized.range(
                of: gemmaThoughtChannelSuffix,
                range: contentStart..<sanitized.endIndex
            ) else {
                return sanitized
            }

            sanitized.removeSubrange(sanitized.startIndex..<closingRange.upperBound)
            sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return sanitized
    }

    static func transcriptChunks(from transcriptBody: String) -> [String] {
        let paragraphs = transcriptBody
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else {
            return splitText(transcriptBody, maxLength: transcriptChunkSize)
        }

        var chunks: [String] = []
        var currentParagraphs: [String] = []
        var currentLength = 0

        for paragraph in paragraphs {
            if paragraph.count > transcriptChunkSize {
                if !currentParagraphs.isEmpty {
                    chunks.append(currentParagraphs.joined(separator: "\n\n"))
                    currentParagraphs = []
                    currentLength = 0
                }
                chunks.append(contentsOf: splitText(paragraph, maxLength: transcriptChunkSize))
                continue
            }

            let additionalLength = paragraph.count + (currentParagraphs.isEmpty ? 0 : 2)
            if currentLength + additionalLength > transcriptChunkSize, !currentParagraphs.isEmpty {
                chunks.append(currentParagraphs.joined(separator: "\n\n"))
                currentParagraphs = [paragraph]
                currentLength = paragraph.count
            } else {
                currentParagraphs.append(paragraph)
                currentLength += additionalLength
            }
        }

        if !currentParagraphs.isEmpty {
            chunks.append(currentParagraphs.joined(separator: "\n\n"))
        }

        return chunks
    }

    static func splitText(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }

        var chunks: [String] = []
        var remaining = text[...]

        while !remaining.isEmpty {
            let preferredEnd = remaining.index(
                remaining.startIndex,
                offsetBy: min(maxLength, remaining.count)
            )

            var splitIndex = preferredEnd
            if preferredEnd < remaining.endIndex {
                let candidateSlice = remaining[..<preferredEnd]
                if let newlineIndex = candidateSlice.lastIndex(of: "\n") {
                    splitIndex = newlineIndex
                } else if let spaceIndex = candidateSlice.lastIndex(of: " ") {
                    splitIndex = spaceIndex
                }
            }

            let rawChunk = remaining[..<splitIndex]
            let chunk = rawChunk.trimmingCharacters(in: .whitespacesAndNewlines)

            if chunk.isEmpty {
                let forcedChunk = remaining[..<preferredEnd]
                chunks.append(forcedChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                remaining = remaining[preferredEnd...]
            } else {
                chunks.append(chunk)
                remaining = remaining[splitIndex...]
            }

            remaining = remaining.drop(while: { $0.isWhitespace || $0.isNewline })
        }

        return chunks
    }
}
