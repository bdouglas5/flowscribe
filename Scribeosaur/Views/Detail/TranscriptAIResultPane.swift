import AppKit
import SwiftUI

struct TranscriptAIResultPane: View {
    let results: [TranscriptAIResult]
    @Binding var selectedResultID: Int64?
    let isGenerating: Bool
    let statusMessage: String?
    let errorMessage: String?
    let onDelete: (Int64) -> Void
    let onExportAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                if results.isEmpty {
                    Text("No AI output saved for this transcript yet.")
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textMuted)
                } else {
                    Picker("Saved Output", selection: $selectedResultID) {
                        ForEach(results) { result in
                            if let resultID = result.id {
                                Text(resultLabel(for: result)).tag(Optional(resultID))
                            }
                        }
                    }
                    .pickerStyle(.menu)
                }

                Spacer()

                Button("Copy") {
                    copySelectedResult()
                }
                .buttonStyle(.secondary)
                .disabled(selectedResult == nil)

                Button("Delete") {
                    if let id = selectedResult?.id {
                        onDelete(id)
                    }
                }
                .buttonStyle(.secondary)
                .disabled(selectedResult == nil)

                Button("Export All") {
                    onExportAll()
                }
                .buttonStyle(.secondary)
                .disabled(results.isEmpty)
            }

            if isGenerating {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ProgressView("Generating AI output...")
                        .tint(ColorTokens.progressFill)

                    if let statusMessage, !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.statusError)
            }

            if let selectedResult {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(selectedResult.promptTitle)
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textPrimary)

                    Text("Saved \(selectedResult.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)

                    ScrollView {
                        Text(selectedResult.content)
                            .font(Typography.body)
                            .foregroundStyle(ColorTokens.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(ColorTokens.backgroundRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else if !isGenerating {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("AI output appears here after you run a prompt.")
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textMuted)

                    Text("Use the AI menu in the bottom toolbar to run a built-in or custom prompt.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectedResult: TranscriptAIResult? {
        guard let selectedResultID else { return nil }
        return results.first { $0.id == selectedResultID }
    }

    private func resultLabel(for result: TranscriptAIResult) -> String {
        "\(result.promptTitle) · \(result.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func copySelectedResult() {
        guard let selectedResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedResult.content, forType: .string)
    }
}
