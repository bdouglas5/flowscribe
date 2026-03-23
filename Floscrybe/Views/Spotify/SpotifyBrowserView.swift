import SwiftUI

struct SpotifyBrowserView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool

    @State private var selectedShow: SpotifyShow?
    @State private var showEpisodes: [SpotifyEpisode] = []
    @State private var selectedEpisodes: Set<String> = []
    @State private var showFinishedOnly = false
    @State private var browseMode: BrowseMode = .shows
    @State private var expandedShows: Set<String> = []
    @State private var finishedSortOrder: FinishedSortOrder = .title

    private enum BrowseMode: String, CaseIterable {
        case shows = "Shows"
        case savedEpisodes = "Saved Episodes"
        case finished = "Finished"
    }

    private enum FinishedSortOrder: String, CaseIterable {
        case title = "By Title"
        case recentRelease = "By Recent"
    }

    private var spotifyService: SpotifyPodcastService? {
        appState.spotifyPodcastService
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if selectedShow != nil {
                showDetailView
            } else {
                libraryView
            }
        }
        .frame(width: 600, height: 500)
        .background(ColorTokens.backgroundFloat)
        .task {
            await spotifyService?.loadSavedShows()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if selectedShow != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedShow = nil
                        showEpisodes = []
                        selectedEpisodes = []
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            Text(selectedShow?.name ?? "Spotify Podcasts")
                .font(Typography.title)
                .foregroundStyle(ColorTokens.textPrimary)
                .lineLimit(1)

            Spacer()

            if selectedShow != nil, !selectedEpisodes.isEmpty {
                Button("Transcribe \(selectedEpisodes.count) Episode\(selectedEpisodes.count == 1 ? "" : "s")") {
                    transcribeSelected()
                }
                .buttonStyle(.primary)
            }

            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.secondary)
        }
        .padding(Spacing.md)
    }

    // MARK: - Library View

    private var libraryView: some View {
        VStack(spacing: 0) {
            Picker("Browse", selection: $browseMode) {
                ForEach(BrowseMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .onChange(of: browseMode) { _, newMode in
                if newMode == .savedEpisodes {
                    Task { await spotifyService?.loadSavedEpisodes() }
                } else if newMode == .finished, spotifyService?.hasScannedFinished != true {
                    Task { await spotifyService?.loadFinishedEpisodes() }
                }
            }

            switch browseMode {
            case .shows:
                showsListView
            case .savedEpisodes:
                savedEpisodesListView
            case .finished:
                finishedEpisodesListView
            }
        }
    }

    private var showsListView: some View {
        Group {
            if spotifyService?.isLoadingShows == true {
                loadingView
            } else if let error = spotifyService?.lastError {
                errorView(message: error) {
                    Task { await spotifyService?.loadSavedShows() }
                }
            } else if let shows = spotifyService?.savedShows, !shows.isEmpty {
                List {
                    ForEach(shows) { show in
                        SpotifyShowRow(
                            show: show,
                            isExclusive: spotifyService?.isShowExclusive(show.id) == true
                        )
                        .onTapGesture {
                            selectShow(show)
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                emptyView(message: "No saved shows found. Follow podcasts in Spotify to see them here.")
            }
        }
    }

    private var savedEpisodesListView: some View {
        Group {
            if spotifyService?.isLoadingEpisodes == true {
                loadingView
            } else if let error = spotifyService?.lastError {
                errorView(message: error) {
                    Task { await spotifyService?.loadSavedEpisodes() }
                }
            } else if let episodes = spotifyService?.savedEpisodes, !episodes.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Toggle("Finished only", isOn: $showFinishedOnly)
                            .toggleStyle(.checkbox)
                            .font(Typography.caption)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)

                    List {
                        ForEach(filteredSavedEpisodes(episodes)) { episode in
                            SpotifyEpisodeRow(episode: episode)
                                .onTapGesture {
                                    transcribeSingleEpisode(episode)
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                emptyView(message: "No saved episodes found.")
            }
        }
    }

    private var finishedEpisodesGrouped: [(show: SpotifyShow, episodes: [SpotifyEpisode])] {
        guard let groups = spotifyService?.finishedEpisodes else { return [] }
        switch finishedSortOrder {
        case .title:
            return groups.sorted {
                $0.show.name.localizedCaseInsensitiveCompare($1.show.name) == .orderedAscending
            }
        case .recentRelease:
            return groups.map { group in
                (show: group.show, episodes: group.episodes.sorted { $0.releaseDate > $1.releaseDate })
            }
            .sorted {
                ($0.episodes.first?.releaseDate ?? "") > ($1.episodes.first?.releaseDate ?? "")
            }
        }
    }

    private var finishedEpisodesListView: some View {
        Group {
            if spotifyService?.isLoadingFinished == true, finishedEpisodesGrouped.isEmpty {
                finishedLoadingView
            } else if let error = spotifyService?.lastError, finishedEpisodesGrouped.isEmpty {
                errorView(message: error) {
                    Task { await spotifyService?.loadFinishedEpisodes() }
                }
            } else if !finishedEpisodesGrouped.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: Spacing.sm) {
                        Picker("Sort", selection: $finishedSortOrder) {
                            ForEach(FinishedSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)

                        Spacer()

                        if spotifyService?.isLoadingFinished == true {
                            ProgressView()
                                .controlSize(.small)
                                .tint(ColorTokens.progressFill)
                        }

                        Button {
                            spotifyService?.resetFinishedScan()
                            Task { await spotifyService?.loadFinishedEpisodes() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(spotifyService?.isLoadingFinished == true)
                        .help("Refresh finished episodes")
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)

                    List {
                        ForEach(finishedEpisodesGrouped, id: \.show.id) { group in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedShows.contains(group.show.id) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedShows.insert(group.show.id)
                                        } else {
                                            expandedShows.remove(group.show.id)
                                        }
                                    }
                                )
                            ) {
                                ForEach(group.episodes) { episode in
                                    SpotifyEpisodeRow(episode: episode)
                                        .onTapGesture {
                                            transcribeSingleEpisode(episode)
                                        }
                                }
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    AsyncImage(url: group.show.bestImageURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray.opacity(0.3)
                                    }
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                    Text(group.show.name)
                                        .font(Typography.headline)
                                        .foregroundStyle(ColorTokens.textPrimary)

                                    Text("\(group.episodes.count)")
                                        .font(Typography.caption)
                                        .foregroundStyle(ColorTokens.textMuted)

                                    Spacer()

                                    Button("Transcribe All") {
                                        transcribeFinishedGroup(group.episodes, show: group.show)
                                    }
                                    .buttonStyle(.secondary)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                emptyView(message: "No finished episodes found. Episodes you've fully listened to in Spotify will appear here.")
            }
        }
    }

    // MARK: - Show Detail

    private var showDetailView: some View {
        Group {
            if spotifyService?.isLoadingEpisodes == true {
                loadingView
            } else if let error = spotifyService?.lastError {
                errorView(message: error) {
                    guard let show = selectedShow else { return }
                    Task { showEpisodes = await spotifyService?.loadShowEpisodes(showID: show.id) ?? [] }
                }
            } else if !showEpisodes.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Button(selectedEpisodes.count == showEpisodes.count ? "Deselect All" : "Select All") {
                            if selectedEpisodes.count == showEpisodes.count {
                                selectedEpisodes.removeAll()
                            } else {
                                selectedEpisodes = Set(showEpisodes.filter { !isEpisodeExclusive($0) }.map(\.id))
                            }
                        }
                        .buttonStyle(.secondary)
                        .font(Typography.caption)

                        Spacer()

                        Text("\(showEpisodes.count) episodes")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)

                    List {
                        ForEach(showEpisodes) { episode in
                            let exclusive = isEpisodeExclusive(episode)
                            HStack(spacing: Spacing.sm) {
                                if !exclusive {
                                    Image(systemName: selectedEpisodes.contains(episode.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(
                                            selectedEpisodes.contains(episode.id)
                                                ? ColorTokens.progressFill
                                                : ColorTokens.textMuted
                                        )
                                        .font(.system(size: 16))
                                }

                                SpotifyEpisodeRow(episode: episode, isExclusive: exclusive)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !exclusive else { return }
                                if selectedEpisodes.contains(episode.id) {
                                    selectedEpisodes.remove(episode.id)
                                } else {
                                    selectedEpisodes.insert(episode.id)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                emptyView(message: "No episodes found.")
            }
        }
    }

    // MARK: - Shared Components

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            ProgressView()
                .tint(ColorTokens.progressFill)
            Text("Loading...")
                .font(Typography.caption)
                .foregroundStyle(ColorTokens.textMuted)
            Spacer()
        }
    }

    private var finishedLoadingView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            ProgressView()
                .tint(ColorTokens.progressFill)
            if let progress = spotifyService?.finishedScanProgress {
                Text("Scanning show \(progress.current) of \(progress.total)...")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
            } else {
                Text("Loading...")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
            }
            Spacer()
        }
    }

    private func emptyView(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 32))
                .foregroundStyle(ColorTokens.textMuted)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            Spacer()
        }
    }

    private func errorView(message: String, retryAction: @escaping () -> Void) -> some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(ColorTokens.statusError)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            Button("Retry") { retryAction() }
                .buttonStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func selectShow(_ show: SpotifyShow) {
        selectedShow = show
        selectedEpisodes = []
        Task {
            showEpisodes = await spotifyService?.loadShowEpisodes(showID: show.id) ?? []
        }
    }

    private func transcribeSelected() {
        guard let show = selectedShow else { return }
        let episodes = showEpisodes.filter { selectedEpisodes.contains($0.id) }
        guard !episodes.isEmpty else { return }

        appState.enqueueSpotifyEpisodes(
            episodes,
            show: show,
            speakerDetection: appState.settings.speakerDetection,
            speakerNames: []
        )
        isPresented = false
    }

    private func transcribeFinishedGroup(_ episodes: [SpotifyEpisode], show: SpotifyShow) {
        appState.enqueueSpotifyEpisodes(
            episodes,
            show: show,
            speakerDetection: appState.settings.speakerDetection,
            speakerNames: []
        )
        isPresented = false
    }

    private func transcribeSingleEpisode(_ episode: SpotifyEpisode) {
        guard let show = episode.show else { return }

        appState.enqueueSpotifyEpisodes(
            [episode],
            show: show,
            speakerDetection: appState.settings.speakerDetection,
            speakerNames: []
        )
        isPresented = false
    }

    // MARK: - Helpers

    private func isEpisodeExclusive(_ episode: SpotifyEpisode) -> Bool {
        guard let show = selectedShow else { return false }
        return spotifyService?.isShowExclusive(show.id) == true
    }

    private func filteredSavedEpisodes(_ episodes: [SpotifyEpisode]) -> [SpotifyEpisode] {
        if showFinishedOnly {
            return episodes.filter(\.isFullyPlayed)
        }
        return episodes
    }
}
