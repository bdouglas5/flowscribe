import Foundation

struct CodexModelOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let tier: Tier

    enum Tier: String, CaseIterable {
        case lightweight = "Lightweight"
        case standard = "Standard"
        case advanced = "Advanced"
    }

    static let all: [CodexModelOption] = [
        // Lightweight – cheaper, faster
        CodexModelOption(id: "gpt-5.1-codex-mini", displayName: "GPT-5.1 Codex Mini", tier: .lightweight),
        CodexModelOption(id: "gpt-5.4-mini", displayName: "GPT-5.4 Mini", tier: .lightweight),

        // Standard – balanced cost and capability
        CodexModelOption(id: "gpt-5.1-codex-max", displayName: "GPT-5.1 Codex Max", tier: .standard),
        CodexModelOption(id: "gpt-5.2", displayName: "GPT-5.2", tier: .standard),
        CodexModelOption(id: "gpt-5.2-codex", displayName: "GPT-5.2 Codex", tier: .standard),

        // Advanced – most capable
        CodexModelOption(id: "gpt-5.3-codex", displayName: "GPT-5.3 Codex", tier: .advanced),
        CodexModelOption(id: "gpt-5.4", displayName: "GPT-5.4", tier: .advanced),
    ]

    /// The sentinel value used in the Picker to indicate custom model entry.
    static let customSentinel = "__custom__"

    /// Whether a given model ID matches a curated entry.
    static func isCurated(_ modelID: String?) -> Bool {
        guard let modelID else { return false }
        return all.contains { $0.id == modelID }
    }
}
