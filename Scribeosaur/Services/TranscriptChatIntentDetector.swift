import Foundation

enum TranscriptChatIntentDetector {
    private static let greetingWords = [
        "hello",
        "hi",
        "hey",
        "hiya",
        "howdy",
    ]
    private static let thanksWords = [
        "thanks",
        "thank",
        "thx",
        "ty",
    ]
    private static let questionWords = [
        "what",
        "when",
        "where",
        "who",
        "why",
        "how",
        "which",
    ]
    private static let creationWords = [
        "create",
        "write",
        "make",
        "generate",
        "draft",
        "build",
    ]
    private static let fileWords = [
        "markdown",
        "file",
        "doc",
        "document",
        "summary",
        "notes",
        "checklist",
        "outline",
    ]

    static func localAssistantReply(for message: String) -> String? {
        let normalized = normalizedMessage(message)
        let words = words(in: message)

        if isSimpleGreeting(words: words) {
            return "Hi. Ask me anything about this transcript, or ask me to create Markdown notes, summaries, outlines, or checklists when you need a document."
        }

        if isSimpleThanks(normalized: normalized, words: words) {
            return "You're welcome. Ask me anything else about this transcript when you're ready."
        }

        if isCapabilityQuestion(normalized: normalized, words: words) {
            return "I can answer questions about this transcript and create Markdown documents when you ask for notes, summaries, outlines, or checklists."
        }

        return nil
    }

    static func shouldCreateMarkdownFile(for message: String) -> Bool {
        let words = words(in: message)

        return !creationWords.allSatisfy { !words.contains($0) }
            && !fileWords.allSatisfy { !words.contains($0) }
    }

    private static func normalizedMessage(_ message: String) -> String {
        message
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func words(in message: String) -> Set<String> {
        Set(
            message
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }

    private static func isSimpleGreeting(words: Set<String>) -> Bool {
        guard words.count <= 3, !greetingWords.allSatisfy({ !words.contains($0) }) else {
            return false
        }

        return questionWords.allSatisfy { !words.contains($0) }
    }

    private static func isSimpleThanks(normalized: String, words: Set<String>) -> Bool {
        guard words.count <= 4, !thanksWords.allSatisfy({ !words.contains($0) }) else {
            return false
        }

        return normalized == "thank you"
            || normalized == "thanks"
            || normalized == "thanks again"
            || normalized == "thx"
            || normalized == "ty"
    }

    private static func isCapabilityQuestion(normalized: String, words: Set<String>) -> Bool {
        normalized == "help"
            || normalized == "what can you do"
            || normalized == "what do you do"
            || normalized == "how can you help"
            || normalized == "how do i use this"
            || words == ["can", "you", "help"]
    }
}
