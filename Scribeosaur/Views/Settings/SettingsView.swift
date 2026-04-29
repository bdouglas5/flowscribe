import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedSection: SettingsSection = .general
    @State private var showAIAdvanced = false
    @State private var showSpotifyAdvanced = false
    @State private var spotifyClientIDInput = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .foregroundStyle(ColorTokens.border)

            detailPane
        }
        .background(ColorTokens.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ColorTokens.border.opacity(0.75), lineWidth: 1)
        )
        .onAppear {
            spotifyClientIDInput = appState.settings.spotifyClientID ?? ""
            applyRequestedSection()
        }
        .onChange(of: appState.requestedSettingsSection) { _, _ in
            applyRequestedSection()
        }
        .onChange(of: selectedSection) { _, newValue in
            appState.lastSelectedSettingsSection = newValue
        }
        .task(id: selectedSection) {
            if selectedSection == .ai {
                await appState.aiService.refreshStatus()
            }

            if selectedSection == .recording {
                await appState.refreshRecordingDevices()
            }
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Preferences")
                        .font(Typography.title)
                        .foregroundStyle(ColorTokens.textPrimary)

                    Text("Clean defaults for the parts of Scribasaur people actually use.")
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, Spacing.sm)

                ForEach(SettingsSection.allCases) { section in
                    sectionButton(section)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.lg)
        }
        .frame(minWidth: 220, idealWidth: 236, maxWidth: 252)
        .background(ColorTokens.backgroundFloat)
    }

    private func sectionButton(_ section: SettingsSection) -> some View {
        Button {
            selectSection(section)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(Typography.headline)
                    .foregroundStyle(ColorTokens.textPrimary)

                Text(section.summary)
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
                    .lineLimit(2)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedSection == section ? ColorTokens.backgroundRaised : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selectedSection == section
                            ? ColorTokens.border.opacity(0.85)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                switch selectedSection {
                case .general:
                    generalSection
                case .youtube:
                    youtubeSection
                case .recording:
                    recordingSection
                case .storage:
                    storageSection
                case .ai:
                    aiSection
                case .spotify:
                    spotifySection
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ColorTokens.backgroundBase)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generalSection: some View {
        @Bindable var settings = appState.settings

        return settingsPage(
            title: "General",
            subtitle: "Set the defaults people feel every day: appearance, transcript behavior, and automatic exports."
        ) {
            settingsCard(title: "Appearance") {
                settingsBlock {
                    settingsRow(
                        "Theme",
                        description: "Choose how Scribasaur should look by default."
                    ) {
                        AppearanceModeSwitcher()
                    }

                    settingsDivider

                    settingsRow(
                        "Speaker detection",
                        description: "Identify speakers automatically when it improves readability."
                    ) {
                        Toggle("", isOn: $settings.speakerDetection)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(ColorTokens.accentBlue)
                    }

                    settingsDivider

                    settingsRow(
                        "Show timestamps",
                        description: "Open transcripts with timestamps visible unless changed later."
                    ) {
                        Toggle("", isOn: $settings.showTimestamps)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(ColorTokens.accentBlue)
                    }
                }
            }

            settingsCard(title: "Exports") {
                settingsBlock {
                    settingsRow(
                        "Save transcript automatically",
                        description: "Export a Markdown transcript as soon as processing finishes."
                    ) {
                        Toggle("", isOn: $settings.autoExportEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(ColorTokens.accentBlue)
                    }

                    settingsDivider

                    settingsRow(
                        "Run AI automatically",
                        description: "Apply a prompt from your library right after each transcript completes."
                    ) {
                        Toggle("", isOn: $settings.aiAutoExportEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(ColorTokens.accentBlue)
                    }

                    if settings.aiAutoExportEnabled {
                        settingsDivider

                        settingsRow(
                            "Prompt",
                            description: "Choose the prompt that runs automatically after each transcript."
                        ) {
                            promptPicker(
                                selection: $settings.aiAutoExportPromptID,
                                noneLabel: "None"
                            )
                        }

                        settingsInlineAction("Edit in AI Library") {
                            selectSection(.ai)
                        }
                    }

                    if settings.autoExportEnabled || settings.aiAutoExportEnabled {
                        settingsDivider

                        folderRow(
                            title: "Export folder",
                            description: "Choose where transcript and AI exports are saved.",
                            path: settings.autoExportURL?.path,
                            chooseLabel: "Choose Folder…",
                            onChoose: chooseExportFolder,
                            onClear: { settings.autoExportBookmark = nil },
                            canClear: settings.autoExportBookmark != nil
                        )
                    }
                }
            }

            settingsCard(title: "Inside Scribasaur") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(versionDescription)
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textPrimary)

                    Text("Local transcription and prompt-driven cleanup without pushing technical model choices into everyday use.")
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var youtubeSection: some View {
        @Bindable var settings = appState.settings

        return settingsPage(
            title: "YouTube",
            subtitle: "Keep channel and playlist imports predictable without burying the core options."
        ) {
            settingsCard(title: "Import Defaults") {
                settingsBlock {
                    settingsRow(
                        "Date range",
                        description: "Only include uploads from this range for new channel and playlist imports."
                    ) {
                        Picker("", selection: $settings.youtubeDateRange) {
                            ForEach(AppSettings.YouTubeDateRange.allCases, id: \.self) { range in
                                Text(range.displayName).tag(range)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }

                    settingsDivider

                    settingsRow(
                        "Group by channel",
                        description: "Show imported channel videos as collections instead of separate entries."
                    ) {
                        Toggle("", isOn: $settings.youtubeAutoGroupByChannel)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(ColorTokens.accentBlue)
                            .onChange(of: settings.youtubeAutoGroupByChannel) { _, _ in
                                appState.refreshTranscripts()
                            }
                    }
                }
            }
        }
    }

    private var recordingSection: some View {
        @Bindable var settings = appState.settings

        return settingsPage(
            title: "Recording",
            subtitle: "Choose how live capture behaves, what happens after stop, and how much original audio to keep."
        ) {
            settingsCard(title: "Live Capture") {
                settingsBlock {
                    settingsRow(
                        "Live mode",
                        description: liveModeDescription(for: settings.recordingLiveMode)
                    ) {
                        Picker("", selection: $settings.recordingLiveMode) {
                            ForEach(AppSettings.RecordingLiveMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    settingsDivider

                    settingsRow(
                        "Input device",
                        description: "Choose a microphone or follow the system default."
                    ) {
                        HStack(spacing: Spacing.sm) {
                            Picker("", selection: $settings.recordingInputDeviceID) {
                                Text("System Default").tag(String?.none)
                                ForEach(appState.recordingState.availableInputDevices) { device in
                                    Text(device.name).tag(Optional(device.id))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 260)

                            Button("Refresh") {
                                Task { await appState.refreshRecordingDevices() }
                            }
                            .buttonStyle(.secondary)
                        }
                    }
                }
            }

            settingsCard(title: "After Recording") {
                settingsBlock {
                    settingsRow(
                        "Run final offline pass",
                        description: "Replace the live transcript with a more complete offline result after recording stops."
                    ) {
                        Toggle("", isOn: $settings.recordingRunFinalPass)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(ColorTokens.accentBlue)
                    }

                    settingsDivider

                    settingsRow(
                        "Run AI after recording",
                        description: "Apply a library prompt automatically once the final transcript is ready."
                    ) {
                        Toggle("", isOn: $settings.recordingRunAIPrompt)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(ColorTokens.accentBlue)
                    }

                    if settings.recordingRunAIPrompt {
                        settingsDivider

                        settingsRow(
                            "Prompt",
                            description: "Choose the prompt that runs after each completed recording."
                        ) {
                            promptPicker(
                                selection: $settings.recordingAIPromptID,
                                noneLabel: "None"
                            )
                        }

                        settingsInlineAction("Edit in AI Library") {
                            selectSection(.ai)
                        }
                    }
                }
            }

            settingsCard(title: "Saved Audio") {
                settingsBlock {
                    settingsRow(
                        "Audio quality",
                        description: "Speech optimized keeps files smaller. Device native preserves more of the source."
                    ) {
                        Picker("", selection: $settings.recordingAudioQuality) {
                            ForEach(AppSettings.RecordingAudioQuality.allCases, id: \.self) { quality in
                                Text(quality.displayName).tag(quality)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    settingsDivider

                    settingsRow(
                        "Keep recording audio",
                        description: "Save the finalized recording instead of deleting it after transcription."
                    ) {
                        Toggle("", isOn: $settings.recordingKeepOriginalAudio)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(ColorTokens.accentBlue)
                    }

                    if settings.recordingKeepOriginalAudio {
                        settingsDivider

                        folderRow(
                            title: "Recording folder",
                            description: "Choose where finalized audio files should be kept.",
                            path: settings.recordingAudioURL?.path ?? StoragePaths.recordings.path,
                            chooseLabel: "Choose Folder…",
                            onChoose: chooseRecordingFolder,
                            onClear: { settings.recordingAudioBookmark = nil },
                            canClear: settings.recordingAudioBookmark != nil
                        )
                    }
                }
            }
        }
    }

    private var storageSection: some View {
        settingsPage(
            title: "Storage",
            subtitle: "Review what Scribasaur keeps on this Mac, clear temporary files, and manage local history."
        ) {
            settingsCard(title: "Usage") {
                settingsBlock {
                    if let repo = appState.repository {
                        storageRow("Saved transcripts", value: "\((try? repo.totalCount()) ?? 0)")
                        settingsDivider
                        storageRow(
                            "Transcript database",
                            value: ByteCountFormatter.string(
                                fromByteCount: repo.databaseSize(),
                                countStyle: .file
                            )
                        )
                        settingsDivider
                    }

                    storageRow("Helper binaries", value: formatBytes(binaryStorageBytes))
                    settingsDivider
                    storageRow("AI files", value: formatBytes(appState.aiService.modelStorageBytes))
                    settingsDivider
                    storageRow("Logs", value: formatBytes(directorySize(StoragePaths.logs)))
                }
            }

            settingsCard(title: "Cleanup") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Clear temporary imports and helper output without touching saved transcripts or exports.")
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Clear Temp Files") {
                        try? StoragePaths.clearTemp()
                    }
                    .buttonStyle(.secondary)
                }
            }

            settingsCard(title: "Danger Zone") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Delete every saved transcript from the local database. Existing exported files in other folders are not removed.")
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Delete All Transcripts", role: .destructive) {
                        let transcriptIDs = appState.transcripts.compactMap(\.id)
                        try? appState.repository?.deleteAll()
                        for transcriptID in transcriptIDs {
                            try? TranscriptMarkdownFileStorage.deleteTranscriptDirectory(transcriptID: transcriptID)
                        }
                        appState.refreshTranscripts()
                    }
                    .buttonStyle(.secondary)
                    .foregroundStyle(ColorTokens.statusError)
                }
            }
        }
    }

    private var aiSection: some View {
        settingsPage(
            title: "AI",
            subtitle: "Scribasaur keeps AI local and consumer-friendly. The prompt library is the main place you should need to touch."
        ) {
            settingsCard(title: "AI on This Mac") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(aiConsumerStatusTitle)
                                .font(Typography.title)
                                .foregroundStyle(ColorTokens.textPrimary)

                            Text(aiConsumerStatusDetail)
                                .font(Typography.body)
                                .foregroundStyle(ColorTokens.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: Spacing.md)

                        settingsPill(
                            aiConsumerStatusBadge.label,
                            color: aiConsumerStatusBadge.color
                        )
                    }

                    if appState.aiService.modelState == .provisioning
                        || appState.aiService.modelState == .loading {
                        ProgressView(value: appState.aiService.modelProgress)
                            .tint(ColorTokens.progressFill)

                        Text(appState.aiService.modelProgressLabel)
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                    }

                    if let lastError = appState.aiService.lastError,
                       appState.aiService.modelState == .failed {
                        settingsHelpText(lastError, color: ColorTokens.statusError)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        statusLine("Runs on this Mac")
                        statusLine("Private by default")
                        statusLine("Prompt library powers cleanup, summaries, and follow-up workflows")
                    }
                }
            }

            settingsCard(title: "Prompt Library") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Create, edit, and organize the prompts Scribasaur uses across the app.")
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textMuted)

                    AIPromptLibraryView()
                }
            }

            advancedDisclosure(
                title: "Advanced",
                subtitle: "Runtime controls, model repair tools, and local setup details for this Mac.",
                isExpanded: $showAIAdvanced
            ) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(appState.aiService.statusTitle)
                                .font(Typography.headline)
                                .foregroundStyle(ColorTokens.textPrimary)

                            Text(appState.aiService.statusDetail)
                                .font(Typography.body)
                                .foregroundStyle(ColorTokens.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: Spacing.md)

                        settingsPill(appState.aiService.modelState.label, color: statusBadgeColor)
                    }

                    settingsDivider

                    settingsRow(
                        "Model bundle",
                        description: "Choose which local AI bundle should power transcript prompts on this Mac."
                    ) {
                        Picker("", selection: Binding(
                            get: { appState.settings.selectedAIModelID },
                            set: { newValue in
                                appState.settings.selectedAIModelID = newValue
                                Task { await appState.aiService.refreshStatus() }
                            }
                        )) {
                            ForEach(AIModelCatalog.all) { descriptor in
                                Text(descriptor.displayName).tag(descriptor.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }

                    settingsDivider

                    storageRow("Download size", value: formatBytes(appState.aiService.selectedModelDescriptor.estimatedDownloadSizeBytes))
                    settingsDivider
                    storageRow("Memory estimate", value: formatBytes(appState.aiService.selectedModelDescriptor.estimatedMemoryBytes))
                    settingsDivider
                    storageRow("Disk usage", value: formatBytes(appState.aiService.modelStorageBytes))

                    if let lastError = appState.aiService.lastError {
                        settingsDivider
                        settingsHelpText(lastError, color: ColorTokens.statusError)
                    }

                    settingsDivider

                    settingsRow(
                        "Unload after idle",
                        description: "Set to 0 to keep AI loaded until Scribasaur quits."
                    ) {
                        HStack(spacing: Spacing.sm) {
                            TextField(
                                "",
                                value: Binding(
                                    get: { appState.settings.aiAutoUnloadMinutes },
                                    set: { appState.settings.aiAutoUnloadMinutes = $0 }
                                ),
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)

                            Text("minutes")
                                .font(Typography.caption)
                                .foregroundStyle(ColorTokens.textMuted)
                        }
                    }

                    HStack(spacing: Spacing.sm) {
                        Button(primaryModelActionTitle) {
                            Task {
                                do {
                                    try await appState.aiService.prepareSelectedModelIfNeeded()
                                } catch {
                                    appState.aiService.lastError = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.secondary)
                        .disabled(appState.aiService.isModelBusy)

                        if appState.aiService.hasRepairableModelFiles {
                            Button("Repair Model") {
                                Task {
                                    do {
                                        try await appState.aiService.provisionSelectedModelFilesIfNeeded()
                                    } catch {
                                        appState.aiService.lastError = error.localizedDescription
                                    }
                                }
                            }
                            .buttonStyle(.secondary)
                            .disabled(appState.aiService.isModelBusy)
                        }

                        Button("Unload") {
                            appState.aiService.unloadSelectedModel()
                        }
                        .buttonStyle(.secondary)
                        .disabled(!appState.aiService.isModelLoaded || appState.aiService.isModelBusy)

                        Button("Delete Files", role: .destructive) {
                            do {
                                try appState.aiService.deleteSelectedModel()
                            } catch {
                                appState.aiService.lastError = error.localizedDescription
                            }
                        }
                        .buttonStyle(.secondary)
                        .disabled(appState.aiService.modelStorageBytes == 0 || appState.aiService.isModelBusy)

                        Button("Refresh Status") {
                            Task { await appState.aiService.refreshStatus() }
                        }
                        .buttonStyle(.secondary)
                        .disabled(appState.aiService.isModelBusy)
                    }
                }
            }
        }
    }

    private var spotifySection: some View {
        settingsPage(
            title: "Spotify",
            subtitle: "Connect your podcast library, browse saved shows, and automatically pull in finished episodes."
        ) {
            settingsCard(title: "Connection") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(appState.spotifyAuthService.statusLabel)
                                .font(Typography.title)
                                .foregroundStyle(ColorTokens.textPrimary)

                            Text(spotifyConnectionDetail)
                                .font(Typography.body)
                                .foregroundStyle(ColorTokens.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: Spacing.md)

                        settingsPill(
                            spotifyStatusBadge.label,
                            color: spotifyStatusBadge.color
                        )
                    }

                    if let error = appState.spotifyAuthService.lastError {
                        settingsHelpText(error, color: ColorTokens.statusError)
                    }

                    HStack(spacing: Spacing.sm) {
                        if appState.spotifyAuthService.isAuthenticated {
                            Button("Disconnect") {
                                appState.spotifyAuthService.disconnect()
                            }
                            .buttonStyle(.secondary)
                        } else if effectiveSpotifyClientID.isEmpty {
                            Button("Finish Setup") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showSpotifyAdvanced = true
                                }
                            }
                            .buttonStyle(.secondary)
                        } else {
                            Button("Connect Spotify") {
                                connectSpotify()
                            }
                            .buttonStyle(.primary)
                            .disabled(appState.spotifyAuthService.isAuthenticating)
                        }

                        if appState.spotifyAuthService.isAuthenticating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(ColorTokens.progressFill)
                        }
                    }
                }
            }

            settingsCard(title: "Automatic Downloads") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if appState.spotifyAuthService.isAuthenticated {
                        settingsBlock {
                            settingsRow(
                                "Automatically transcribe finished episodes",
                                description: "Check saved Spotify episodes and queue newly finished listens automatically."
                            ) {
                                Toggle("", isOn: Binding(
                                    get: { appState.settings.spotifyAutoDownloadEnabled },
                                    set: { newValue in
                                        appState.settings.spotifyAutoDownloadEnabled = newValue
                                        appState.updateAutoDownloadPolling()
                                    }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .tint(ColorTokens.accentBlue)
                            }

                            if appState.settings.spotifyAutoDownloadEnabled {
                                settingsDivider

                                settingsRow(
                                    "Check frequency",
                                    description: "Choose how often Scribasaur looks for newly finished episodes."
                                ) {
                                    Picker("", selection: Binding(
                                        get: { appState.settings.spotifyAutoDownloadIntervalMinutes },
                                        set: { newValue in
                                            appState.settings.spotifyAutoDownloadIntervalMinutes = newValue
                                            appState.updateAutoDownloadPolling()
                                        }
                                    )) {
                                        Text("15 minutes").tag(15)
                                        Text("30 minutes").tag(30)
                                        Text("1 hour").tag(60)
                                        Text("2 hours").tag(120)
                                        Text("4 hours").tag(240)
                                    }
                                    .labelsHidden()
                                    .frame(width: 170)
                                }

                                settingsDivider

                                settingsRow(
                                    "Processed episodes",
                                    description: "Reset this only if you want Scribasaur to reconsider already tracked listens."
                                ) {
                                    HStack(spacing: Spacing.sm) {
                                        Text("\(appState.settings.spotifyProcessedEpisodeIDs.count)")
                                            .font(Typography.headline)
                                            .foregroundStyle(ColorTokens.textPrimary)
                                            .frame(minWidth: 32, alignment: .trailing)

                                        Button("Reset") {
                                            appState.settings.spotifyProcessedEpisodeIDs = []
                                            appState.resetSessionBaseline()
                                        }
                                        .buttonStyle(.secondary)
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Connect Spotify above to enable automatic downloads for finished episodes.")
                            .font(Typography.body)
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                }
            }

            advancedDisclosure(
                title: "Advanced",
                subtitle: "Manual client credentials for the current Spotify integration.",
                isExpanded: $showSpotifyAdvanced
            ) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    TextField("Spotify Client ID", text: $spotifyClientIDInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            persistSpotifyClientIDInput()
                        }
                        .onChange(of: spotifyClientIDInput) { _, _ in
                            persistSpotifyClientIDInput()
                        }

                    settingsHelpText(
                        "Create a Spotify app at developer.spotify.com/dashboard and use http://127.0.0.1:19836/callback as the redirect URI."
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func settingsPage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            pageHeader(title: title, subtitle: subtitle)
            content()
        }
    }

    @ViewBuilder
    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.largeTitle)
                .foregroundStyle(ColorTokens.textPrimary)

            Text(subtitle)
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let title {
                Text(title)
                    .font(Typography.headline)
                    .foregroundStyle(ColorTokens.textPrimary)
            }

            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(ColorTokens.backgroundFloat)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(ColorTokens.border.opacity(0.7), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func settingsBlock<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            content()
        }
    }

    @ViewBuilder
    private func advancedDisclosure<Content: View>(
        title: String,
        subtitle: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        settingsCard {
            DisclosureGroup(isExpanded: isExpanded) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    settingsDivider
                    content()
                }
                .padding(.top, Spacing.md)
            } label: {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(title)
                            .font(Typography.headline)
                            .foregroundStyle(ColorTokens.textPrimary)

                        Text(subtitle)
                            .font(Typography.body)
                            .foregroundStyle(ColorTokens.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Spacing.md)

                    settingsTag(isExpanded.wrappedValue ? "Open" : "Hidden")
                }
            }
        }
    }

    @ViewBuilder
    private func settingsRow<Control: View>(
        _ title: String,
        description: String? = nil,
        alignment: VerticalAlignment = .center,
        @ViewBuilder control: @escaping () -> Control
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: alignment, spacing: Spacing.lg) {
                settingsRowCopy(title, description: description)
                Spacer(minLength: Spacing.md)
                control()
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                settingsRowCopy(title, description: description)
                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func settingsRowCopy(_ title: String, description: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textPrimary)

            if let description {
                Text(description)
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func settingsInlineAction(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()

            Button(title, action: action)
                .buttonStyle(.utility)
        }
    }

    @ViewBuilder
    private func folderRow(
        title: String,
        description: String,
        path: String?,
        chooseLabel: String,
        onChoose: @escaping () -> Void,
        onClear: @escaping () -> Void,
        canClear: Bool
    ) -> some View {
        settingsRow(title, description: description, alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(path ?? "No folder selected")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 340, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(ColorTokens.backgroundRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(ColorTokens.border.opacity(0.6), lineWidth: 1)
                    )

                HStack(spacing: Spacing.sm) {
                    Button(chooseLabel, action: onChoose)
                        .buttonStyle(.secondary)

                    if canClear {
                        Button("Clear", action: onClear)
                            .buttonStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func promptPicker(
        selection: Binding<String?>,
        noneLabel: String
    ) -> some View {
        Picker("", selection: selection) {
            Text(noneLabel).tag(String?.none)
            ForEach(appState.aiService.availablePromptTemplates, id: \.id) { prompt in
                Text(prompt.title).tag(Optional(prompt.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 220)
    }

    @ViewBuilder
    private func settingsHelpText(_ text: String, color: Color = ColorTokens.textMuted) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func storageRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textPrimary)

            Spacer()

            Text(value)
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textSecondary)
        }
    }

    @ViewBuilder
    private func statusLine(_ text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(ColorTokens.progressFill)
                .frame(width: 7, height: 7)

            Text(text)
                .font(Typography.caption)
                .foregroundStyle(ColorTokens.textSecondary)
        }
    }

    @ViewBuilder
    private func settingsPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(ColorTokens.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func settingsTag(_ title: String) -> some View {
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(ColorTokens.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(ColorTokens.backgroundRaised)
            )
            .overlay(
                Capsule()
                    .stroke(ColorTokens.border.opacity(0.65), lineWidth: 1)
            )
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(ColorTokens.border.opacity(0.55))
            .frame(height: 1)
    }

    private var binaryStorageBytes: Int64 {
        directorySize(StoragePaths.bin)
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)):
            return "Version \(version) (\(build))"
        case let (.some(version), nil):
            return "Version \(version)"
        default:
            return "Version 1.0"
        }
    }

    private var aiConsumerStatusTitle: String {
        switch appState.aiService.modelState {
        case .ready:
            appState.aiService.isRunningTask ? "Working right now" : "Ready on this Mac"
        case .provisioning, .loading:
            "Getting ready"
        case .failed:
            "Needs attention"
        case .notPresent:
            "Set up when needed"
        }
    }

    private var aiConsumerStatusDetail: String {
        switch appState.aiService.modelState {
        case .ready:
            if appState.aiService.isRunningTask {
                return "Scribasaur is using your prompt library on a transcript right now."
            }
            return "Prompts from your library can run locally without extra setup or model-picking in everyday use."
        case .provisioning, .loading:
            return "Scribasaur is preparing AI on this Mac. You can keep working while it finishes."
        case .failed:
            return "AI on this Mac hit a setup issue. Open Advanced if you want to repair, reload, or reset it."
        case .notPresent:
            return "AI prepares itself the first time you use it, or you can handle setup manually from Advanced."
        }
    }

    private var aiConsumerStatusBadge: (label: String, color: Color) {
        switch appState.aiService.modelState {
        case .ready:
            return appState.aiService.isRunningTask
                ? ("Active", ColorTokens.backgroundHover)
                : ("Ready", ColorTokens.progressFill)
        case .provisioning, .loading:
            return ("Preparing", ColorTokens.accentBlueSubtle)
        case .failed:
            return ("Attention", ColorTokens.statusError)
        case .notPresent:
            return ("Setup", ColorTokens.backgroundRaised)
        }
    }

    private var statusBadgeColor: Color {
        switch appState.aiService.modelState {
        case .notPresent:
            ColorTokens.backgroundRaised
        case .provisioning:
            ColorTokens.accentBlueSubtle
        case .loading:
            ColorTokens.backgroundHover
        case .ready:
            ColorTokens.progressFill
        case .failed:
            ColorTokens.statusError
        }
    }

    private var primaryModelActionTitle: String {
        switch appState.aiService.modelState {
        case .notPresent:
            "Download and Load"
        case .provisioning:
            "Downloading…"
        case .loading:
            "Loading…"
        case .ready:
            appState.aiService.isModelLoaded ? "Reload Model" : "Load Into Memory"
        case .failed:
            appState.aiService.hasRepairableModelFiles ? "Resume Download" : "Retry Setup"
        }
    }

    private var spotifyStatusBadge: (label: String, color: Color) {
        if appState.spotifyAuthService.isAuthenticating {
            return ("Connecting", ColorTokens.backgroundHover)
        }
        if appState.spotifyAuthService.isAuthenticated {
            return ("Connected", ColorTokens.progressFill)
        }
        return ("Disconnected", ColorTokens.backgroundRaised)
    }

    private var spotifyConnectionDetail: String {
        if appState.spotifyAuthService.isAuthenticated {
            return "Your saved podcasts and finished episodes are ready to browse inside Scribasaur."
        }
        if effectiveSpotifyClientID.isEmpty {
            return "Finish setup once, then connect your Spotify account without keeping app credentials in the main flow."
        }
        return "Connect your Spotify account to browse saved podcasts and enable automatic downloads for finished listens."
    }

    private var effectiveSpotifyClientID: String {
        spotifyClientIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func liveModeDescription(for mode: AppSettings.RecordingLiveMode) -> String {
        switch mode {
        case .automatic:
            "Uses the fastest default live transcription path."
        case .streamingEnglish:
            "Best for low-latency English speech."
        case .chunkedMultilingual:
            "Best when you need broader language coverage with a little more delay."
        }
    }

    private func directorySize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return 0 }

        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )

        var total: Int64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func applyRequestedSection() {
        selectedSection = appState.consumeRequestedSettingsSection() ?? appState.lastSelectedSettingsSection
    }

    private func selectSection(_ section: SettingsSection) {
        selectedSection = section
        appState.lastSelectedSettingsSection = section
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

    private func chooseRecordingFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Recording Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            appState.settings.recordingAudioBookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    private func persistSpotifyClientIDInput() {
        appState.settings.spotifyClientID = effectiveSpotifyClientID.isEmpty ? nil : effectiveSpotifyClientID
    }

    private func connectSpotify() {
        let clientID = effectiveSpotifyClientID
        guard !clientID.isEmpty else { return }

        appState.settings.spotifyClientID = clientID
        Task {
            await appState.spotifyAuthService.authorize(clientID: clientID)
        }
    }
}
