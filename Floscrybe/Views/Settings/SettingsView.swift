import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        TabView {
            Form {
                Section("Transcription") {
                    Toggle("Speaker Detection", isOn: $settings.speakerDetection)
                    Text("When enabled, speakers are auto-labeled as Speaker 1, Speaker 2, and so on.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)

                    Toggle("Show Timestamps by Default", isOn: $settings.showTimestamps)
                }

                Section("Export") {
                    Toggle("Auto-export transcripts as Markdown", isOn: $settings.autoExportEnabled)

                    Toggle("Run AI prompt and export result", isOn: $settings.aiAutoExportEnabled)
                        .disabled(!appState.codexService.isSignedIn)

                    if settings.aiAutoExportEnabled {
                        Picker("AI Prompt", selection: $settings.aiAutoExportPromptID) {
                            Text("None").tag(String?.none)
                            ForEach(appState.codexService.availablePromptTemplates, id: \.id) { template in
                                Text(template.title).tag(Optional(template.id))
                            }
                        }

                        Text("After each transcription completes, the selected AI prompt will run automatically and its output will be saved as a separate Markdown file in the export folder.")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                    }

                    if !appState.codexService.isSignedIn {
                        Text("Sign in to Codex in the AI tab to enable AI auto-export.")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                    }

                    if settings.autoExportEnabled || settings.aiAutoExportEnabled {
                        HStack {
                            if let url = settings.autoExportURL {
                                Text(url.path)
                                    .font(Typography.caption)
                                    .foregroundStyle(ColorTokens.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("No folder selected")
                                    .font(Typography.caption)
                                    .foregroundStyle(ColorTokens.textMuted)
                            }

                            Spacer()

                            Button("Choose Folder...") {
                                chooseExportFolder()
                            }
                            .buttonStyle(.secondary)

                            if settings.autoExportBookmark != nil {
                                Button("Clear") {
                                    settings.autoExportBookmark = nil
                                }
                                .buttonStyle(.secondary)
                            }
                        }
                    }
                }

                Section("YouTube") {
                    Picker("Channel/playlist date filter", selection: $settings.youtubeDateRange) {
                        ForEach(AppSettings.YouTubeDateRange.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    Text("When adding a YouTube channel or playlist, only include videos uploaded within this time range.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }

            Form {
                Section("Database") {
                    if let repo = appState.repository {
                        LabeledContent("Transcripts") {
                            Text("\((try? repo.totalCount()) ?? 0)")
                        }
                        LabeledContent("Database Size") {
                            Text(ByteCountFormatter.string(
                                fromByteCount: repo.databaseSize(),
                                countStyle: .file
                            ))
                        }
                    }
                }

                Section("Actions") {
                    Button("Clear Temp Files") {
                        try? StoragePaths.clearTemp()
                    }
                    .buttonStyle(.secondary)

                    Button("Delete All Transcripts", role: .destructive) {
                        try? appState.repository?.deleteAll()
                        appState.refreshTranscripts()
                    }
                    .foregroundStyle(ColorTokens.statusError)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Storage", systemImage: "internaldrive")
            }

            aiTab
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            VStack(spacing: Spacing.md) {
                Spacer()

                Image(systemName: "waveform.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(ColorTokens.textSecondary)

                Text("Floscrybe")
                    .font(Typography.title)
                    .foregroundStyle(ColorTokens.textPrimary)

                Text("Version 1.0")
                    .font(Typography.body)
                    .foregroundStyle(ColorTokens.textMuted)

                Text("Local transcription with optional Codex-powered cleanup and summaries")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)

                Spacer()
            }
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 680, height: 620)
    }

    private var aiTab: some View {
        Form {
            Section("Connection") {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(appState.codexService.statusTitle)
                            .font(Typography.headline)
                            .foregroundStyle(ColorTokens.textPrimary)

                        Text(appState.codexService.statusDetail)
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                    }

                    Spacer()

                    statusBadge
                }

                if let binaryPath = appState.codexService.codexBinaryPath {
                    LabeledContent("CLI Path") {
                        Text(binaryPath)
                            .font(Typography.mono)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .textSelection(.enabled)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Button("Refresh Status") {
                        Task { await appState.codexService.refreshStatus() }
                    }
                    .buttonStyle(.secondary)

                    Button {
                        Task { await appState.codexService.signInWithChatGPT() }
                    } label: {
                        if appState.codexService.isAuthenticating {
                            Label("Signing In...", systemImage: "person.badge.key")
                        } else {
                            Label("Sign In with ChatGPT", systemImage: "person.badge.key")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!appState.codexService.isInstalled || appState.codexService.isAuthenticating)

                    Button {
                        Task { await appState.codexService.runHealthCheck() }
                    } label: {
                        if appState.codexService.isRunningHealthCheck {
                            Label("Checking...", systemImage: "checkmark.seal")
                        } else {
                            Label("Run Health Check", systemImage: "checkmark.seal")
                        }
                    }
                    .buttonStyle(.secondary)
                    .disabled(!appState.codexService.isSignedIn || appState.codexService.isRunningHealthCheck)

                    Button("Sign Out") {
                        Task { await appState.codexService.signOut() }
                    }
                    .buttonStyle(.secondary)
                    .disabled(
                        !appState.codexService.isSignedIn || appState.codexService.isAuthenticating
                    )
                }

                if appState.codexService.isAuthenticating || appState.codexService.isRunningHealthCheck {
                    ProgressView()
                        .tint(ColorTokens.progressFill)
                }

                if let healthCheckResponse = appState.codexService.lastHealthCheckResponse,
                   let checkedAt = appState.codexService.lastHealthCheckAt {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Last health check: \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)

                        Text(healthCheckResponse)
                            .font(Typography.mono)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .textSelection(.enabled)
                    }
                }

                if let lastError = appState.codexService.lastError {
                    Text(lastError)
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.statusError)
                }
            }

            Section("How It Works") {
                Text("Floscrybe does not embed a raw OpenAI API key. It uses the first-party local Codex CLI session already signed in on this Mac, then runs transcript tools through `codex exec` in read-only mode.")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)

                Text("When you run a transcript tool, the selected transcript content is sent to OpenAI through your Codex session.")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
            }

            Section("Available Tools") {
                Text("Clean Up")
                    .font(Typography.headline)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("Fixes grammar, punctuation, and repetition while keeping the original meaning.")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)

                Text("Summary")
                    .font(Typography.headline)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("Generates a concise markdown summary with key takeaways.")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)

                Text("Action Items")
                    .font(Typography.headline)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("Extracts explicit follow-ups, owners, and due dates when they appear in the transcript.")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
            }

            Section("Prompt Library") {
                AIPromptLibraryView()
            }

            Section("Official Docs") {
                Link(destination: URL(string: "https://developers.openai.com/codex/cli")!) {
                    Label("Codex CLI", systemImage: "link")
                }

                Link(destination: URL(string: "https://help.openai.com/en/articles/11369540")!) {
                    Label("Using Codex with your ChatGPT plan", systemImage: "link")
                }

                Link(destination: URL(string: "https://help.openai.com/en/articles/8156019")!) {
                    Label("ChatGPT billing vs API billing", systemImage: "link")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusBadge: some View {
        Text(appState.codexService.connectionLabel)
            .font(Typography.caption)
            .foregroundStyle(ColorTokens.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(statusBadgeColor)
            .clipShape(Capsule())
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            appState.settings.autoExportBookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    private var statusBadgeColor: Color {
        switch appState.codexService.connectionState {
        case .checking:
            ColorTokens.backgroundHover
        case .unavailable:
            ColorTokens.statusError
        case .signedOut:
            ColorTokens.backgroundFloat
        case .signedIn:
            ColorTokens.progressFill
        }
    }
}
