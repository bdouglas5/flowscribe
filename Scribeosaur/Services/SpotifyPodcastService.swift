import Foundation

@Observable
@MainActor
final class SpotifyPodcastService {
    let authService: SpotifyAuthService
    private let settings: AppSettings

    private(set) var savedShows: [SpotifyShow] = []
    private(set) var savedEpisodes: [SpotifyEpisode] = []
    private(set) var finishedEpisodes: [(show: SpotifyShow, episodes: [SpotifyEpisode])] = []
    private(set) var hasScannedFinished = false
    private(set) var isLoadingShows = false
    private(set) var isLoadingEpisodes = false
    private(set) var isLoadingFinished = false
    private(set) var finishedScanProgress: (current: Int, total: Int)?
    private(set) var lastError: String?

    init(authService: SpotifyAuthService, settings: AppSettings) {
        self.authService = authService
        self.settings = settings
    }

    var isConnected: Bool { authService.isAuthenticated }

    // MARK: - Browse Library

    func loadSavedShows() async {
        guard authService.isAuthenticated else { return }
        isLoadingShows = true
        lastError = nil

        do {
            let token = try await authService.validAccessToken()
            let response = try await SpotifyAPIService.getSavedShows(accessToken: token)
            let allSaved = try await SpotifyAPIService.getAllPages(firstPage: response, accessToken: token)
            savedShows = allSaved.map(\.show)
            AppLogger.info("SpotifyPodcast", "Loaded \(savedShows.count) saved shows (total: \(response.total))")
        } catch {
            lastError = error.localizedDescription
            AppLogger.error("SpotifyPodcast", "Failed to load shows: \(error.localizedDescription)")
        }

        isLoadingShows = false
    }

    func loadShowEpisodes(showID: String) async -> [SpotifyEpisode] {
        guard authService.isAuthenticated else { return [] }
        isLoadingEpisodes = true
        lastError = nil

        do {
            let episodes = try await fetchShowEpisodes(showID: showID)
            isLoadingEpisodes = false
            return episodes
        } catch {
            lastError = error.localizedDescription
            AppLogger.error("SpotifyPodcast", "Failed to load episodes: \(error.localizedDescription)")
            isLoadingEpisodes = false
            return []
        }
    }

    private func fetchShowEpisodes(showID: String) async throws -> [SpotifyEpisode] {
        let token = try await authService.validAccessToken()
        let market = authService.userCountry
        let response = try await SpotifyAPIService.getShowEpisodes(
            showID: showID,
            accessToken: token,
            market: market
        )
        let allEpisodes = try await SpotifyAPIService.getAllPages(firstPage: response, accessToken: token)
        AppLogger.info("SpotifyPodcast", "Loaded \(allEpisodes.count) episodes for show \(showID) (total: \(response.total))")
        return allEpisodes
    }

    func resetFinishedScan() {
        hasScannedFinished = false
        finishedEpisodes = []
    }

    func loadFinishedEpisodes() async {
        guard authService.isAuthenticated else { return }
        isLoadingFinished = true
        lastError = nil

        if savedShows.isEmpty {
            await loadSavedShows()
        }

        // Phase 1: Collect episode IDs from each show (with throttling)
        var showEpisodeMap: [(show: SpotifyShow, episodeIDs: [String])] = []
        let total = savedShows.count
        finishedScanProgress = (current: 0, total: total)

        for (index, show) in savedShows.enumerated() {
            finishedScanProgress = (current: index + 1, total: total)

            do {
                let episodes = try await fetchShowEpisodes(showID: show.id)
                if !episodes.isEmpty {
                    showEpisodeMap.append((show: show, episodeIDs: episodes.map(\.id)))
                }
            } catch {
                AppLogger.error("SpotifyPodcast", "Failed to load episodes for \(show.name): \(error.localizedDescription)")
            }

            // Throttle between show fetches to avoid rate limiting
            try? await Task.sleep(for: .milliseconds(200))
        }

        // Phase 2: Batch-fetch full episode details (with resume_point) in chunks of 50
        let allIDs = showEpisodeMap.flatMap(\.episodeIDs)
        let showLookup: [String: SpotifyShow] = {
            var lookup: [String: SpotifyShow] = [:]
            for entry in showEpisodeMap {
                for id in entry.episodeIDs {
                    lookup[id] = entry.show
                }
            }
            return lookup
        }()

        var fullEpisodes: [SpotifyEpisode] = []
        let chunks = stride(from: 0, to: allIDs.count, by: 50).map {
            Array(allIDs[$0..<min($0 + 50, allIDs.count)])
        }

        AppLogger.info("SpotifyPodcast", "Batch-fetching \(allIDs.count) episodes in \(chunks.count) chunk(s)")

        for chunk in chunks {
            do {
                let token = try await authService.validAccessToken()
                let market = authService.userCountry
                var episodes = try await SpotifyAPIService.getEpisodes(
                    ids: chunk,
                    accessToken: token,
                    market: market
                )

                for i in episodes.indices {
                    if let show = showLookup[episodes[i].id] {
                        episodes[i].show = show
                    }
                }
                fullEpisodes.append(contentsOf: episodes)
            } catch {
                AppLogger.error("SpotifyPodcast", "Batch fetch failed for chunk: \(error.localizedDescription)")
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        // Phase 3: Filter for finished and group by show
        let finished = fullEpisodes.filter(\.isFullyPlayed)
        let grouped = Dictionary(grouping: finished) { $0.show?.id ?? "unknown" }
        let results = grouped.compactMap { (_, eps) -> (show: SpotifyShow, episodes: [SpotifyEpisode])? in
            guard let show = eps.first?.show else { return nil }
            return (show: show, episodes: eps)
        }

        finishedEpisodes = results.sorted {
            $0.show.name.localizedCaseInsensitiveCompare($1.show.name) == .orderedAscending
        }

        let totalFinished = finishedEpisodes.reduce(0) { $0 + $1.episodes.count }
        AppLogger.info("SpotifyPodcast", "Found \(totalFinished) finished episode(s) across \(finishedEpisodes.count) show(s)")

        finishedScanProgress = nil
        hasScannedFinished = true
        isLoadingFinished = false
    }

    func loadSavedEpisodes() async {
        guard authService.isAuthenticated else { return }
        isLoadingEpisodes = true
        lastError = nil

        do {
            let token = try await authService.validAccessToken()
            let market = authService.userCountry
            let response = try await SpotifyAPIService.getSavedEpisodes(
                accessToken: token,
                market: market
            )
            let allSaved = try await SpotifyAPIService.getAllPages(firstPage: response, accessToken: token)
            savedEpisodes = allSaved.map(\.episode)

            let withResumePoint = savedEpisodes.filter { $0.resumePoint != nil }.count
            let fullyPlayed = savedEpisodes.filter(\.isFullyPlayed).count
            AppLogger.info("SpotifyPodcast", "Loaded \(savedEpisodes.count) saved episodes — \(withResumePoint) with resume data, \(fullyPlayed) fully played (market: \(market ?? "none"))")

            let apiFullyPlayed = savedEpisodes.filter { $0.resumePoint?.fullyPlayed == true }.count
            let heuristicOnly = fullyPlayed - apiFullyPlayed
            AppLogger.info("SpotifyPodcast", "Fully played breakdown: \(apiFullyPlayed) via API flag, \(heuristicOnly) via ≥90% heuristic")
        } catch {
            lastError = error.localizedDescription
            AppLogger.error("SpotifyPodcast", "Failed to load saved episodes: \(error.localizedDescription)")
        }

        isLoadingEpisodes = false
    }

    // MARK: - Resolve Episode from URL

    func resolveEpisode(id: String) async throws -> SpotifyEpisode {
        let token = try await authService.validAccessToken()
        return try await SpotifyAPIService.getEpisode(id: id, accessToken: token)
    }

    func resolveShow(id: String) async throws -> SpotifyShow {
        let token = try await authService.validAccessToken()
        return try await SpotifyAPIService.getShow(id: id, accessToken: token)
    }

    // MARK: - Download Audio via RSS

    func downloadAudio(
        episodeName: String,
        showName: String,
        showID: String,
        publisherName: String,
        durationSeconds: Double,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (audioFile: URL, title: String) {
        // Check RSS feed cache
        let cachedFeed = settings.spotifyRSSFeedCache[showID]

        if cachedFeed == "EXCLUSIVE" {
            throw SpotifyServiceError.spotifyExclusive(showName)
        }

        let feedURL: URL
        if let cachedURLString = cachedFeed, let cached = URL(string: cachedURLString) {
            feedURL = cached
        } else {
            feedURL = try await PodcastRSSService.resolveRSSFeed(
                showName: showName,
                publisher: publisherName
            )
            // Cache the result
            await MainActor.run {
                settings.spotifyRSSFeedCache[showID] = feedURL.absoluteString
            }
        }

        // Fetch and match episode
        let rssEpisodes = try await PodcastRSSService.fetchEpisodes(feedURL: feedURL)

        guard let matchedEpisode = PodcastRSSService.matchEpisode(
            spotifyTitle: episodeName,
            spotifyDurationSeconds: durationSeconds,
            in: rssEpisodes
        ) else {
            throw SpotifyServiceError.episodeNotFoundInRSS(episodeName)
        }

        AppLogger.info(
            "SpotifyPodcast",
            "Matched \"\(episodeName)\" to RSS episode \"\(matchedEpisode.title)\""
        )

        // Download the audio
        let audioFile = try await PodcastRSSService.downloadAudio(
            episodeAudioURL: matchedEpisode.audioURL,
            fileName: episodeName,
            onProgress: onProgress
        )

        return (audioFile, episodeName)
    }

    // MARK: - Exclusive Check

    func isShowExclusive(_ showID: String) -> Bool {
        settings.spotifyRSSFeedCache[showID] == "EXCLUSIVE"
    }

    func markShowExclusive(_ showID: String) {
        settings.spotifyRSSFeedCache[showID] = "EXCLUSIVE"
    }

    func clearExclusiveCache(for showID: String) {
        settings.spotifyRSSFeedCache.removeValue(forKey: showID)
    }

    // MARK: - Create Queue Items

    func createQueueItem(
        from episode: SpotifyEpisode,
        show: SpotifyShow,
        speakerDetection: Bool,
        speakerNames: [String]
    ) -> QueueItem {
        let item = QueueItem(
            title: episode.name,
            sourceURL: URL(string: episode.externalUrls?.spotify ?? "https://open.spotify.com/episode/\(episode.id)"),
            sourceType: .url,
            remoteSource: .spotify,
            collectionID: nil,
            collectionTitle: nil,
            collectionType: nil,
            collectionItemIndex: nil,
            speakerDetection: speakerDetection,
            speakerNames: speakerNames
        )
        item.thumbnailURL = episode.bestImageURL?.absoluteString
        item.spotifyMetadata = SpotifyQueueMetadata(
            episodeID: episode.id,
            showID: show.id,
            showName: show.name,
            publisherName: show.publisher,
            episodeDurationMs: episode.durationMs
        )
        return item
    }

    func createQueueItems(
        from episodes: [SpotifyEpisode],
        show: SpotifyShow,
        speakerDetection: Bool,
        speakerNames: [String]
    ) -> [QueueItem] {
        let collectionID = UUID().uuidString
        return episodes.enumerated().map { index, episode in
            let item = QueueItem(
                title: episode.name,
                sourceURL: URL(string: episode.externalUrls?.spotify ?? "https://open.spotify.com/episode/\(episode.id)"),
                sourceType: .url,
                remoteSource: .spotify,
                collectionID: collectionID,
                collectionTitle: show.name,
                collectionType: .show,
                collectionItemIndex: index + 1,
                thumbnailURL: episode.bestImageURL?.absoluteString,
                speakerDetection: speakerDetection,
                speakerNames: speakerNames
            )
            item.spotifyMetadata = SpotifyQueueMetadata(
                episodeID: episode.id,
                showID: show.id,
                showName: show.name,
                publisherName: show.publisher,
                episodeDurationMs: episode.durationMs
            )
            return item
        }
    }
}
