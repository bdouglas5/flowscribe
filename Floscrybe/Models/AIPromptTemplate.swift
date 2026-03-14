import Foundation

struct AIPromptTemplate: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable {
        case builtIn
        case custom
    }

    var id: String
    var title: String
    var body: String
    var kind: Kind

    var isDeletable: Bool {
        kind == .custom
    }

    var allowsTitleEditing: Bool {
        kind == .custom
    }

    static let cleanUp = AIPromptTemplate(
        id: "builtin.clean-up",
        title: "Clean Up",
        body: """
        Rewrite the transcript into clean readable notes.
        Preserve meaning, remove obvious filler, keep important named entities,
        and retain speaker attribution when it helps readability.
        """,
        kind: .builtIn
    )

    static let summary = AIPromptTemplate(
        id: "builtin.summary",
        title: "Summary",
        body: """
        Summarize the transcript in markdown with:
        1. a one-paragraph overview
        2. 4-6 key points
        3. important decisions or unresolved questions, if any
        """,
        kind: .builtIn
    )

    static let actionItems = AIPromptTemplate(
        id: "builtin.action-items",
        title: "Action Items",
        body: """
        Extract action items in markdown.
        For each item, include owner and due date only when the transcript states them.
        If no action items are present, say that explicitly.
        """,
        kind: .builtIn
    )

    static var defaultTemplates: [AIPromptTemplate] {
        [cleanUp, summary, actionItems]
    }

    static func newCustomPrompt() -> AIPromptTemplate {
        AIPromptTemplate(
            id: "custom.\(UUID().uuidString.lowercased())",
            title: "Custom Prompt",
            body: """
            Describe what you want Codex to do with this transcript.
            Return concise Markdown.
            """,
            kind: .custom
        )
    }
}
