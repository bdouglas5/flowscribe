import AppKit
import SwiftUI

struct TranscriptToolbar: View {
    @Environment(AppState.self) private var appState

    let transcript: Transcript
    let segments: [TranscriptSegment]
    @Binding var showTimestamps: Bool
    let selectedTab: TranscriptDetailView.DetailTab
    let selectedAIResult: TranscriptAIResult?
    let isGeneratingAI: Bool
    let onRunPrompt: (AIPromptTemplate) -> Void
    let onShowAITab: () -> Void

    var body: some View {
        let isThisTranscriptRunning = isGeneratingAI || appState.codexService.activeTaskTranscriptId == transcript.id
        let isAnyAIRunning = isGeneratingAI || appState.codexService.isRunningTask

        HStack(spacing: Spacing.sm) {
            Button {
                if selectedTab == .ai, let aiResult = selectedAIResult {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(aiResult.content, forType: .string)
                } else {
                    ExportService.copyToClipboard(
                        segments: segments,
                        showTimestamps: showTimestamps
                    )
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(Typography.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(ColorTokens.textPrimary)

            toolbarDivider

            Button {
                if selectedTab == .ai, let aiResult = selectedAIResult {
                    ExportService.exportAIMarkdown(
                        transcript: transcript,
                        aiResult: aiResult
                    )
                } else {
                    ExportService.exportMarkdown(
                        transcript: transcript,
                        segments: segments,
                        showTimestamps: showTimestamps
                    )
                }
            } label: {
                Label("Export .md", systemImage: "square.and.arrow.up")
                    .font(Typography.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(ColorTokens.textPrimary)

            toolbarDivider

            Menu {
                if appState.codexService.isSignedIn {
                    Section("Run Prompt") {
                        ForEach(appState.codexService.availablePromptTemplates) { prompt in
                            Button(prompt.title) {
                                onShowAITab()
                                onRunPrompt(prompt)
                            }
                            .disabled(isAnyAIRunning)
                        }
                    }
                } else {
                    Button("Sign in with ChatGPT in Settings to run AI prompts.") {}
                        .disabled(true)
                }

                Divider()

                Button("Show Saved AI") {
                    onShowAITab()
                }

                Button("Open AI Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            } label: {
                Label(isThisTranscriptRunning ? "Running..." : "AI", systemImage: "sparkles")
                    .font(Typography.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(ColorTokens.textPrimary)

            toolbarDivider

            HStack(spacing: Spacing.xs) {
                Text("Timestamps")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textSecondary)
                Toggle("", isOn: $showTimestamps)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .tint(ColorTokens.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(ColorTokens.backgroundRaised)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .shadow(color: .black.opacity(0.04), radius: 1, y: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(ColorTokens.border, lineWidth: 0.5)
        )
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(ColorTokens.border)
            .frame(width: 1, height: 16)
    }
}
