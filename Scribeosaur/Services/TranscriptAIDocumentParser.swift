import Foundation

struct TranscriptAIDocument: Equatable {
    var title: String
    var content: String
}

enum TranscriptAIDocumentParser {
    private static let documentHeadingPattern = #"(?m)^##\s+Document\s+\d+\s*:\s*(.+)$"#

    static func documents(from response: String, fallbackTitle: String = "Custom Summary") -> [TranscriptAIDocument] {
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResponse.isEmpty else { return [] }

        guard let regex = try? NSRegularExpression(pattern: documentHeadingPattern) else {
            return [TranscriptAIDocument(title: fallbackTitle, content: trimmedResponse)]
        }

        let fullRange = NSRange(trimmedResponse.startIndex..<trimmedResponse.endIndex, in: trimmedResponse)
        let matches = regex.matches(in: trimmedResponse, range: fullRange)

        guard !matches.isEmpty else {
            return [TranscriptAIDocument(title: fallbackTitle, content: trimmedResponse)]
        }

        return matches.enumerated().compactMap { index, match in
            guard let headingRange = Range(match.range, in: trimmedResponse),
                  let titleRange = Range(match.range(at: 1), in: trimmedResponse)
            else {
                return nil
            }

            let contentStart = headingRange.upperBound
            let contentEnd: String.Index
            if index + 1 < matches.count,
               let nextRange = Range(matches[index + 1].range, in: trimmedResponse) {
                contentEnd = nextRange.lowerBound
            } else {
                contentEnd = trimmedResponse.endIndex
            }

            let title = String(trimmedResponse[titleRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(trimmedResponse[contentStart..<contentEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let content = "## \(title)\n\n\(body)"
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return TranscriptAIDocument(
                title: title.isEmpty ? "Document \(index + 1)" : title,
                content: content
            )
        }
    }
}
