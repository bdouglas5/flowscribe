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

    private let minSidebarWidth: CGFloat = 200
    private let maxSidebarWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            // Global top bar
            topBar

            // Sidebar + Detail panel
            HStack(spacing: 0) {
                if !isSidebarCollapsed {
                    SidebarView()
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading))

                    // Resizable divider
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
        .animation(.easeInOut(duration: 0.2), value: isSidebarCollapsed)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                DropZoneOverlay()
            }
        }
        .sheet(isPresented: $showURLInput) {
            URLInputDialog(isPresented: $showURLInput)
        }
        .sheet(isPresented: $showSpotifyBrowser) {
            SpotifyBrowserView(isPresented: $showSpotifyBrowser)
        }
        .background(ColorTokens.backgroundBase)
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            // Brand (flush left after traffic light clearance)
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ColorTokens.textPrimary)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text("F")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ColorTokens.buttonPrimaryText)
                    }

                Text("Floscrybe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ColorTokens.textPrimary)
            }

            Spacer()

            // Processing status (when active)
            if let activeItem = appState.queueManager?.activeItem {
                ProcessingStatusBar(item: activeItem)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: appState.queueManager?.activeItem != nil)
            }

            Spacer()

            // Action buttons (right)
            HStack(spacing: Spacing.sm) {
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
                    Text("Floscrybe")
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
}
