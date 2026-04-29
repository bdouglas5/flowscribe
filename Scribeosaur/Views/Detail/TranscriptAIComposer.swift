import SwiftUI

struct TranscriptAIComposer: View {
    @Binding var prompt: String

    let isGenerating: Bool
    let statusMessage: String?
    let errorMessage: String?
    let onGenerateSummary: () -> Void
    let onGenerateCustom: () -> Void
    let onCancel: () -> Void

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("AI Documents")
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textPrimary)

                    Text("Ask Gemma to summarize, reshape, or draft documents from this transcript.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }

                Spacer()

                Button {
                    onGenerateSummary()
                } label: {
                    Label("Generate Summary", systemImage: "sparkles")
                }
                .buttonStyle(.secondary)
                .controlSize(.small)
                .disabled(isGenerating)
            }

            TextEditor(text: $prompt)
                .font(Typography.body)
                .scrollContentBackground(.hidden)
                .padding(Spacing.sm)
                .frame(minHeight: 86, maxHeight: 130)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ColorTokens.backgroundRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ColorTokens.border.opacity(0.7), lineWidth: 1)
                )
                .disabled(isGenerating)

            HStack(spacing: Spacing.sm) {
                if isGenerating {
                    Button {
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.secondary)
                    .controlSize(.small)
                }

                Button {
                    onGenerateCustom()
                } label: {
                    Label(isGenerating ? "Generating..." : "Generate", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.compactPrimary)
                .disabled(isGenerating || trimmedPrompt.isEmpty)

                Spacer()

                if let statusMessage, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                        .lineLimit(1)
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.statusError)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTokens.backgroundFloat)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ColorTokens.border.opacity(0.65), lineWidth: 1)
        )
    }
}
