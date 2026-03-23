import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isCustomModel = false
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general, storage, spotify, ai, about

        var title: String {
            switch self {
            case .general: "General"
            case .storage: "Storage"
            case .spotify: "Spotify"
            case .ai: "AI"
            case .about: "About"
            }
        }

        var icon: String {
            switch self {
            case .general: "gear"
            case .storage: "internaldrive"
            case .spotify: "antenna.radiowaves.left.and.right"
            case .ai: "sparkles"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab title
            Text(selectedTab.title)
                .font(Typography.title)
                .foregroundStyle(ColorTokens.textPrimary)
                .padding(.top, Spacing.md)

            // Icon toolbar
            HStack(spacing: Spacing.md) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: Spacing.xs) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18))
                            Text(tab.title)
                                .font(Typography.caption)
                        }
                        .foregroundStyle(
                            selectedTab == tab
                                ? ColorTokens.accentBlue
                                : ColorTokens.textMuted
                        )
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab
                                    ? ColorTokens.accentBlueSubtle
                                    : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Spacing.sm)

            Divider()

            // Content
            ScrollView {
                switch selectedTab {
                case .general:
                    generalTab
                case .storage:
                    storageTab
                case .spotify:
                    SpotifySettingsSection()
                case .ai:
                    aiTab
                case .about:
                    aboutTab
                }
            }
        }
        .frame(width: 680, height: 620)
        .onAppear {
            let current = appState.settings.codexModel
            isCustomModel = current != nil && !CodexModelOption.isCurated(current)
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        @Bindable var settings = appState.settings

        return VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Appearance")
            settingsCard {
                HStack {
                    Text("Mode")
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Spacer()
                    Picker("", selection: $settings.appearanceMode) {
                        ForEach(AppSettings.AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            sectionHeader("Transcription")
            settingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle("Speaker Detection", isOn: $settings.speakerDetection)
                    Text("When enabled, speakers are auto-labeled as Speaker 1, Speaker 2, and so on.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                        .padding(.top, Spacing.xxs)

                    Divider()
                        .padding(.vertical, Spacing.sm)

                    Toggle("Show Timestamps by Default", isOn: $settings.showTimestamps)
                }
            }

            sectionHeader("Export")
            settingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle("Auto-export transcripts as Markdown", isOn: $settings.autoExportEnabled)

                    Divider()
                        .padding(.vertical, Spacing.sm)

                    Toggle("Run AI prompt and export result", isOn: $settings.aiAutoExportEnabled)
                        .disabled(!appState.codexService.isSignedIn)

                    if settings.aiAutoExportEnabled {
                        Picker("AI Prompt", selection: $settings.aiAutoExportPromptID) {
                            Text("None").tag(String?.none)
                            ForEach(appState.codexService.availablePromptTemplates, id: \.id) { template in
                                Text(template.title).tag(Optional(template.id))
                            }
                        }
                        .padding(.top, Spacing.xs)

                        Text("After each transcription completes, the selected AI prompt will run automatically and its output will be saved as a separate Markdown file in the export folder.")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                            .padding(.top, Spacing.xxs)
                    }

                    if !appState.codexService.isSignedIn {
                        Text("Sign in to Codex in the AI tab to enable AI auto-export.")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                            .padding(.top, Spacing.xs)
                    }
                }
            }

            if settings.autoExportEnabled || settings.aiAutoExportEnabled {
                HStack {
                    if let url = settings.autoExportURL {
                        Text(url.path)
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(ColorTokens.backgroundFloat)
                            )
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

            sectionHeader("YouTube")
            settingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Channel/playlist date filter")
                            .font(Typography.body)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        Picker("", selection: $settings.youtubeDateRange) {
                            ForEach(AppSettings.YouTubeDateRange.allCases, id: \.self) { range in
                                Text(range.displayName).tag(range)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    Text("When adding a YouTube channel or playlist, only include videos uploaded within this time range.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                        .padding(.top, Spacing.xxs)

                    Divider()
                        .padding(.vertical, Spacing.sm)

                    Toggle("Group videos by channel", isOn: $settings.youtubeAutoGroupByChannel)
                        .onChange(of: settings.youtubeAutoGroupByChannel) { _, _ in
                            appState.refreshTranscripts()
                        }
                }
            }
        }
        .padding(Spacing.md)
    }

    // MARK: - Storage Tab

    private var storageTab: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Database")
            settingsCard {
                VStack(spacing: Spacing.sm) {
                    if let repo = appState.repository {
                        HStack {
                            Text("Transcripts")
                                .font(Typography.body)
                                .foregroundStyle(ColorTokens.textPrimary)
                            Spacer()
                            Text("\((try? repo.totalCount()) ?? 0)")
                                .font(Typography.body)
                                .foregroundStyle(ColorTokens.textSecondary)
                        }

                        Divider()

                        HStack {
                            Text("Database Size")
                                .font(Typography.body)
                                .foregroundStyle(ColorTokens.textPrimary)
                            Spacer()
                            Text(ByteCountFormatter.string(
                                fromByteCount: repo.databaseSize(),
                                countStyle: .file
                            ))
                            .font(Typography.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                        }
                    }
                }
            }

            sectionHeader("Actions")
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Button("Clear Temp Files") {
                        try? StoragePaths.clearTemp()
                    }
                    .buttonStyle(.secondary)

                    Divider()

                    Button("Delete All Transcripts", role: .destructive) {
                        try? appState.repository?.deleteAll()
                        appState.refreshTranscripts()
                    }
                    .foregroundStyle(ColorTokens.statusError)
                }
            }
        }
        .padding(Spacing.md)
    }

    // MARK: - AI Tab

    private var aiTab: some View {
        @Bindable var settings = appState.settings

        return VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Connection")
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
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

                    Divider()

                    HStack {
                        Text("CLI Path")
                            .font(Typography.body)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: Spacing.xs) {
                            if let customPath = appState.settings.codexCustomBinaryPath, !customPath.isEmpty {
                                Text(customPath)
                                    .font(Typography.mono)
                                    .foregroundStyle(ColorTokens.textSecondary)
                                    .textSelection(.enabled)
                                Text("Custom path")
                                    .font(Typography.caption)
                                    .foregroundStyle(ColorTokens.textMuted)
                            } else if let binaryPath = appState.codexService.codexBinaryPath {
                                Text(binaryPath)
                                    .font(Typography.mono)
                                    .foregroundStyle(ColorTokens.textSecondary)
                                    .textSelection(.enabled)
                                Text("Auto-detected")
                                    .font(Typography.caption)
                                    .foregroundStyle(ColorTokens.textMuted)
                            } else {
                                Text("Not found")
                                    .font(Typography.mono)
                                    .foregroundStyle(ColorTokens.statusError)
                            }

                            HStack(spacing: Spacing.xs) {
                                Button("Browse...") {
                                    chooseCodexBinary()
                                }
                                .buttonStyle(.secondary)

                                if appState.settings.codexCustomBinaryPath != nil {
                                    Button("Reset to Auto-Detect") {
                                        appState.settings.codexCustomBinaryPath = nil
                                        Task { await appState.codexService.refreshStatus() }
                                    }
                                    .buttonStyle(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

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
                        .buttonStyle(.secondary)
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
            }

            sectionHeader("How It Works")
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Floscrybe does not embed a raw OpenAI API key. It uses the first-party local Codex CLI session already signed in on this Mac, then runs transcript tools through `codex exec` in read-only mode.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)

                    Text("When you run a transcript tool, the selected transcript content is sent to OpenAI through your Codex session.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }

            sectionHeader("Available Tools")
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Clean Up")
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Text("Fixes grammar, punctuation, and repetition while keeping the original meaning.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)

                    Divider()

                    Text("Summary")
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Text("Generates a concise markdown summary with key takeaways.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)

                    Divider()

                    Text("Action Items")
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Text("Extracts explicit follow-ups, owners, and due dates when they appear in the transcript.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }

            sectionHeader("Execution")
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("Model")
                            .font(Typography.body)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        Picker("", selection: Binding<String?>(
                            get: {
                                let current = settings.codexModel
                                if current == nil { return nil }
                                if CodexModelOption.isCurated(current) { return current }
                                return CodexModelOption.customSentinel
                            },
                            set: { newValue in
                                if newValue == nil {
                                    settings.codexModel = nil
                                    isCustomModel = false
                                } else if newValue == CodexModelOption.customSentinel {
                                    isCustomModel = true
                                } else {
                                    settings.codexModel = newValue
                                    isCustomModel = false
                                }
                            }
                        )) {
                            Text("CLI Default").tag(String?.none)

                            ForEach(CodexModelOption.Tier.allCases, id: \.self) { tier in
                                Section(tier.rawValue) {
                                    ForEach(CodexModelOption.all.filter { $0.tier == tier }) { model in
                                        Text(model.displayName).tag(Optional(model.id))
                                    }
                                }
                            }

                            Divider()
                            Text("Custom...").tag(Optional(CodexModelOption.customSentinel))
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }

                    if isCustomModel {
                        HStack {
                            Text("Custom Model")
                                .font(Typography.body)
                                .foregroundStyle(ColorTokens.textPrimary)
                            Spacer()
                            TextField(
                                "Enter model name",
                                text: Binding(
                                    get: { settings.codexModel ?? "" },
                                    set: { settings.codexModel = $0.isEmpty ? nil : $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        }
                    }

                    Text("Select which model to pass via --model to codex exec.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)

                    Divider()

                    HStack {
                        Text("Timeout (seconds)")
                            .font(Typography.body)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        TextField(
                            "300",
                            value: $settings.codexTimeoutSeconds,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    }
                    Text("Maximum seconds to wait for a single Codex execution. Default is 300.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }

            sectionHeader("Prompt Library")
            settingsCard {
                AIPromptLibraryView()
            }

            sectionHeader("Official Docs")
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Link(destination: URL(string: "https://developers.openai.com/codex/cli")!) {
                        Label("Codex CLI", systemImage: "link")
                    }

                    Divider()

                    Link(destination: URL(string: "https://help.openai.com/en/articles/11369540")!) {
                        Label("Using Codex with your ChatGPT plan", systemImage: "link")
                    }

                    Divider()

                    Link(destination: URL(string: "https://help.openai.com/en/articles/8156019")!) {
                        Label("ChatGPT billing vs API billing", systemImage: "link")
                    }
                }
            }
        }
        .padding(Spacing.md)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.headline)
            .foregroundStyle(ColorTokens.textPrimary)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ColorTokens.backgroundFloat)
            )
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

    private func chooseCodexBinary() {
        let panel = NSOpenPanel()
        panel.title = "Select Codex CLI Binary"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            appState.settings.codexCustomBinaryPath = url.path
            Task { await appState.codexService.refreshStatus() }
        }
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
