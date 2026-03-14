import AppKit
import SwiftUI

struct TranscriptToolbar: View {
    @Environment(AppState.self) private var appState

    let transcript: Transcript
    let segments: [TranscriptSegment]
    @Binding var showTimestamps: Bool
    let isGeneratingAI: Bool
    let onRunPrompt: (AIPromptTemplate) -> Void
    let onShowAITab: () -> Void

    var body: some View {
        let isAIRunning = isGeneratingAI || appState.codexService.isRunningTask

        HStack(spacing: Spacing.md) {
            Button {
                ExportService.copyToClipboard(
                    segments: segments,
                    showTimestamps: showTimestamps
                )
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.secondary)

            Button {
                ExportService.exportMarkdown(
                    transcript: transcript,
                    segments: segments,
                    showTimestamps: showTimestamps
                )
            } label: {
                Label("Export .md", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.secondary)

            Menu {
                if appState.codexService.isSignedIn {
                    Section("Run Prompt") {
                        ForEach(appState.codexService.availablePromptTemplates) { prompt in
                            Button(prompt.title) {
                                onShowAITab()
                                onRunPrompt(prompt)
                            }
                            .disabled(isAIRunning)
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
                Label(isAIRunning ? "Running AI..." : "AI", systemImage: "sparkles")
            }
            .buttonStyle(.secondary)

            Spacer()

            Toggle(isOn: $showTimestamps) {
                Label("Timestamps", systemImage: "clock")
            }
            .toggleStyle(.switch)
            .tint(ColorTokens.textSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(ColorTokens.backgroundRaised)
    }
}
