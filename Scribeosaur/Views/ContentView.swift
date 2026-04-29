import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var isDropTargeted = false
    @State private var showURLInput = false
    @State private var showSpotifyBrowser = false
    @State private var sidebarWidth: CGFloat = 220
    @State private var isSidebarCollapsed = false
    @State private var dragStartWidth: CGFloat?
    @State private var microphoneButtonFrame: CGRect = .zero

    private let minSidebarWidth: CGFloat = 200
    private let maxSidebarWidth: CGFloat = 300
    private let recordingDropdownWidth: CGFloat = 304

    var body: some View {
        VStack(spacing: 0) {
            activeTopBar
            activeWorkspace
        }
        .animation(.easeInOut(duration: 0.2), value: isSidebarCollapsed)
        .animation(.spring(response: 0.22, dampingFraction: 0.92), value: appState.recordingState.showsRecorderPopover)
        .coordinateSpace(name: "contentView")
        .onPreferenceChange(MicrophoneButtonFramePreferenceKey.self) { frame in
            microphoneButtonFrame = frame
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                DropZoneOverlay()
            }
        }
        .overlay(alignment: .topLeading) {
            if appState.recordingState.showsRecorderPopover, !microphoneButtonFrame.isEmpty {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.black.opacity(0.001))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.cancelRecordingArm()
                            }

                        RecordingArmDropdown(
                            state: appState.recordingState,
                            inputName: recordingInputName,
                            modeName: appState.settings.recordingLiveMode.displayName,
                            onOpenSettings: {
                                appState.openSettings(section: .recording)
                            },
                            onStart: {
                                Task { await appState.startRecording() }
                            },
                            onCancel: {
                                appState.cancelRecordingArm()
                            }
                        )
                        .offset(
                            x: recordingDropdownX(in: proxy.size.width),
                            y: microphoneButtonFrame.maxY + 10
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                    }
                }
            }
        }
        .sheet(isPresented: $showURLInput) {
            URLInputDialog(isPresented: $showURLInput)
        }
        .sheet(isPresented: $showSpotifyBrowser) {
            SpotifyBrowserView(isPresented: $showSpotifyBrowser)
        }
        .alert(
            "Recording Unavailable",
            isPresented: Binding(
                get: { appState.recordingAlertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        appState.dismissRecordingAlert()
                    }
                }
            )
        ) {
            Button("OK") {
                appState.dismissRecordingAlert()
            }
        } message: {
            Text(appState.recordingAlertMessage ?? "")
        }
        .background(ColorTokens.backgroundBase)
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var activeTopBar: some View {
        switch appState.currentDestination {
        case .library:
            libraryTopBar
        case .settings:
            settingsTopBar
        }
    }

    @ViewBuilder
    private var activeWorkspace: some View {
        switch appState.currentDestination {
        case .library:
            libraryWorkspace
        case .settings:
            settingsWorkspace
        }
    }

    private var libraryTopBar: some View {
        HStack(spacing: Spacing.sm) {
            // Brand (flush left after traffic light clearance)
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ColorTokens.textPrimary)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text("S")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ColorTokens.buttonPrimaryText)
                    }

                Text("Scribeosaur")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ColorTokens.textPrimary)
            }

            Spacer()

            // Processing status (when active)
            if appState.recordingState.phase == .recording {
                recordingStatusBar
            } else if appState.recordingState.phase == .finalizing {
                recordingFinalizingBar
            } else if let activeItem = appState.queueManager?.activeItem {
                ProcessingStatusBar(item: activeItem)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: appState.queueManager?.activeItem != nil)
            }

            Spacer()

            // Action buttons (right)
            HStack(spacing: Spacing.sm) {
                Button {
                    switch appState.recordingState.phase {
                    case .idle, .failed:
                        Task { await appState.armRecording() }
                    case .armed:
                        appState.cancelRecordingArm()
                    case .recording:
                        Task { await appState.stopRecording() }
                    case .preflighting, .finalizing:
                        break
                    }
                } label: {
                    Image(systemName: microphoneButtonSymbol)
                        .font(.system(size: 16))
                        .foregroundStyle(
                            appState.recordingState.phase == .recording
                                ? ColorTokens.statusError
                                : ColorTokens.textSecondary
                        )
                        .frame(width: 36, height: 36)
                        .background(
                            appState.recordingState.phase == .recording
                                ? ColorTokens.backgroundFloat
                                : ColorTokens.backgroundFloat,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .help(microphoneButtonHelp)
                .disabled(appState.recordingState.phase == .finalizing || appState.recordingState.phase == .preflighting)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MicrophoneButtonFramePreferenceKey.self,
                            value: proxy.frame(in: .named("contentView"))
                        )
                    }
                )

                if appState.spotifyPodcastService?.isConnected == true {
                    Button {
                        showSpotifyBrowser = true
                    } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16))
                            .foregroundStyle(ColorTokens.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(ColorTokens.backgroundFloat, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Browse Spotify Podcasts")
                }

                Button {
                    showURLInput = true
                } label: {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 16))
                        .foregroundStyle(ColorTokens.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(ColorTokens.backgroundFloat, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Paste URL (⌘V or ⇧⌘V)")
            }
        }
        .frame(height: 44)
        .padding(.leading, 76) // Traffic light clearance
        .padding(.trailing, Spacing.md)
        .background(ColorTokens.backgroundBase)
    }

    private var settingsTopBar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                appState.closeSettings()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(ColorTokens.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ColorTokens.backgroundFloat)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ColorTokens.border.opacity(0.75), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ColorTokens.textPrimary)

                Text("Preferences")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ColorTokens.textMuted)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 10)
                .fill(Color.clear)
                .frame(width: 72, height: 32)
        }
        .frame(height: 52)
        .padding(.leading, 76)
        .padding(.trailing, Spacing.md)
        .background(ColorTokens.backgroundBase)
        .overlay(alignment: .bottom) {
            Divider()
                .foregroundStyle(ColorTokens.border)
        }
    }

    private var libraryWorkspace: some View {
        HStack(spacing: 0) {
            if !isSidebarCollapsed {
                SidebarView()
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading))

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 5)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragStartWidth == nil {
                                    dragStartWidth = sidebarWidth
                                }
                                let newWidth = (dragStartWidth ?? sidebarWidth) + value.translation.width
                                sidebarWidth = min(maxSidebarWidth, max(minSidebarWidth, newWidth))
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                            }
                    )
            }

            VStack(spacing: 0) {
                detailHeader

                if let transcript = appState.selectedTranscript {
                    TranscriptDetailView(transcript: transcript)
                } else {
                    EmptyDetailView()
                }
            }
            .background(ColorTokens.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 16, y: 4)
            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 0.5)
            .padding([.trailing, .bottom], Spacing.sm)
        }
    }

    private var settingsWorkspace: some View {
        SettingsView()
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.sm)
            .background(ColorTokens.backgroundBase)
    }

    // MARK: - Detail Header

    private var detailHeader: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                isSidebarCollapsed.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(ColorTokens.textMuted)
            .help(isSidebarCollapsed ? "Show Sidebar" : "Hide Sidebar")

            Spacer()
        }
        .overlay {
            if let transcript = appState.selectedTranscript {
                HStack(spacing: 4) {
                    Text("Scribeosaur")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(ColorTokens.textMuted)
                    Text(transcript.title)
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .overlay(alignment: .bottom) {
            Divider()
                .foregroundStyle(ColorTokens.border)
        }
    }

    // MARK: - Drop Handler

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []

        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                if FFmpegService.isSupported(url) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            appState.enqueueFiles(
                urls: urls,
                speakerDetection: appState.settings.speakerDetection,
                speakerNames: []
            )
        }
    }

    private var recordingStatusBar: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(ColorTokens.statusError)
                .frame(width: 10, height: 10)

            Text("Recording \(TimeFormatting.duration(seconds: appState.recordingState.elapsedSeconds))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ColorTokens.textSecondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(ColorTokens.backgroundFloat, in: Capsule())
    }

    private var recordingFinalizingBar: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)

            Text(appState.recordingState.finalizationStep ?? "Finalizing recording…")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ColorTokens.textSecondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(ColorTokens.backgroundFloat, in: Capsule())
    }

    private var microphoneButtonSymbol: String {
        switch appState.recordingState.phase {
        case .recording:
            return "stop.fill"
        case .armed:
            return "xmark"
        case .idle, .preflighting, .finalizing, .failed:
            return "mic.fill"
        }
    }

    private var microphoneButtonHelp: String {
        switch appState.recordingState.phase {
        case .recording:
            return "Stop Recording"
        case .armed:
            return "Cancel Recording"
        case .idle, .preflighting, .finalizing, .failed:
            return "New Recording"
        }
    }

    private var recordingInputName: String {
        guard let selectedID = appState.recordingState.selectedInputDeviceID,
              let device = appState.recordingState.availableInputDevices.first(where: { $0.id == selectedID })
        else {
            return "System Default"
        }

        return device.name
    }

    private func recordingDropdownX(in availableWidth: CGFloat) -> CGFloat {
        let idealX = microphoneButtonFrame.maxX - recordingDropdownWidth
        let minX = Spacing.md
        let maxX = max(minX, availableWidth - recordingDropdownWidth - Spacing.md)
        return min(max(idealX, minX), maxX)
    }
}

private struct MicrophoneButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
