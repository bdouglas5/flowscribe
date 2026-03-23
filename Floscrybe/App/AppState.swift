import AppKit
import Foundation

@Observable
@MainActor
final class AppState {
    let settings = AppSettings()
    let binaryDownloadService = BinaryDownloadService()
    let codexService = CodexService()
    let spotifyAuthService = SpotifyAuthService()
    private(set) var spotifyPodcastService: SpotifyPodcastService?

    private(set) var databaseManager: DatabaseManager?
    private(set) var repository: TranscriptRepository?
    private(set) var transcriptionService = TranscriptionService()
    private(set) var diarizationService = DiarizationService()
    private(set) var queueManager: QueueManager?

    private var autoDownloadTask: Task<Void, Never>?
    private var sessionBaselineEpisodeIDs: Set<String>?
    private var pendingAIAutoExports: [Int64] = []
    private var isProcessingAIAutoExports = false

    var transcripts: [Transcript] = []
    var selectedTranscriptId: Int64?
    var selectedCategory: TranscriptCategory = .all
    var selectedDateFilter: DateFilter = .allTime
    var activeSearchQuery: String = ""
    var currentMatchIndex: Int = 0
    var totalMatchCount: Int = 0
    var isReady = false
    var setupError: String?

    var selectedTranscript: Transcript? {
        transcripts.first { $0.id == selectedTranscriptId }
    }

    @discardableResult
    func enqueueSupportedURLFromPasteboard() -> Bool {
        guard let pastedText = NSPasteboard.general.string(forType: .string) else {
            AppLogger.info("Paste", "Pasteboard did not contain plain text")
            return false
        }

        return enqueueSupportedURL(from: pastedText)
    }

    @discardableResult
    func enqueueSupportedURL(from pastedText: String) -> Bool {
        // Check for Spotify URLs first
        if let spotifyURL = SpotifyAPIService.firstSpotifyURL(in: pastedText) {
            enqueueSpotifyURL(
                spotifyURL,
                speakerDetection: settings.speakerDetection,
                speakerNames: []
            )
            return true
        }

        guard let supportedURL = YTDLPService.firstSupportedURL(in: pastedText) else {
            AppLogger.info("Paste", "Ignored pasted content because no supported URL was found")
            return false
        }

        enqueueURL(
            supportedURL,
            speakerDetection: settings.speakerDetection,
            speakerNames: []
        )
        return true
    }

    func initialize() async {
        do {
            AppLogger.info("AppState", "Initializing app state")
            try StoragePaths.ensureDirectoriesExist()
            try StoragePaths.clearTemp()
            await codexService.refreshStatus()

            let dbManager = try DatabaseManager()
            let repo = TranscriptRepository(dbQueue: dbManager.dbQueue)

            let spotifyService = SpotifyPodcastService(
                authService: spotifyAuthService,
                settings: settings
            )
            self.spotifyPodcastService = spotifyService

            // Restore Spotify session if client ID is configured
            if let clientID = settings.spotifyClientID, !clientID.isEmpty {
                spotifyAuthService.clientID = clientID
                await spotifyAuthService.restoreSession(clientID: clientID)
            }

            let pipeline = AudioPipelineService(
                transcriptionService: transcriptionService,
                diarizationService: diarizationService,
                repository: repo,
                settings: settings,
                spotifyPodcastService: spotifyService
            )

            self.databaseManager = dbManager
            self.repository = repo

            let queue = QueueManager(pipeline: pipeline)
            queue.onItemCompleted = { [weak self] transcriptId, item in
                Task { @MainActor in
                    await self?.handleAIAutoExport(transcriptId: transcriptId)
                    if let episodeID = item.spotifyMetadata?.episodeID {
                        self?.settings.markEpisodeProcessed(episodeID)
                    }
                }
            }
            self.queueManager = queue

            transcripts = try repo.fetchFiltered(category: selectedCategory, dateFilter: selectedDateFilter)
            await repairTranscriptDurationsIfNeeded()
            AppLogger.info("AppState", "Initialization complete. transcripts=\(transcripts.count)")

            if settings.spotifyAutoDownloadEnabled {
                startAutoDownloadPolling()
            }
        } catch {
            AppLogger.error("AppState", "Initialization failed: \(error.localizedDescription)")
            setupError = error.localizedDescription
        }
    }

    func loadModels() async {
        setupError = nil
        do {
            AppLogger.info(
                "AppState",
                "Loading models. speakerDetection=\(settings.speakerDetection)"
            )
            try await transcriptionService.loadModel()
            if settings.speakerDetection {
                try await diarizationService.loadModel()
            }
            await MainActor.run { isReady = true }
            AppLogger.info("AppState", "Models loaded successfully")
        } catch {
            AppLogger.error("AppState", "Model loading failed: \(error.localizedDescription)")
            setupError = error.localizedDescription
        }
    }

    func ensureDiarizationLoaded() async {
        guard !diarizationService.isModelLoaded else { return }
        try? await diarizationService.loadModel()
    }

    func refreshTranscripts() {
        guard let repository else { return }
        transcripts = (try? repository.fetchFiltered(
            category: selectedCategory,
            dateFilter: selectedDateFilter
        )) ?? []
        activeSearchQuery = ""
        currentMatchIndex = 0
        totalMatchCount = 0
    }

    func searchTranscripts(query: String) {
        guard let repository else { return }
        transcripts = (try? repository.fetchFiltered(
            category: selectedCategory,
            dateFilter: selectedDateFilter,
            searchQuery: query
        )) ?? []
        activeSearchQuery = query
        currentMatchIndex = 0
    }

    func navigateToNextMatch() {
        guard totalMatchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % totalMatchCount
    }

    func navigateToPreviousMatch() {
        guard totalMatchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + totalMatchCount) % totalMatchCount
    }

    func deleteTranscript(id: Int64) {
        guard let repository else { return }
        try? repository.delete(id: id)
        if selectedTranscriptId == id {
            selectedTranscriptId = nil
        }
        refreshTranscripts()
    }

    func deleteCollection(id: String) {
        guard let repository else { return }
        try? repository.deleteCollection(id: id)
        if let selectedTranscript, selectedTranscript.collectionID == id {
            selectedTranscriptId = nil
        }
        refreshTranscripts()
    }

    func enqueueFiles(urls: [URL], speakerDetection: Bool, speakerNames: [String]) {
        guard let queueManager else { return }
        let effectiveSpeakerNames = defaultSpeakerNames(
            for: speakerNames,
            enabled: speakerDetection
        )

        let items = urls.compactMap { url -> QueueItem? in
            guard FFmpegService.isSupported(url) else { return nil }
            return QueueItem(
                title: url.deletingPathExtension().lastPathComponent,
                sourceURL: url,
                sourceType: .file,
                speakerDetection: speakerDetection,
                speakerNames: effectiveSpeakerNames
            )
        }

        AppLogger.info("Queue", "Enqueuing \(items.count) local file(s)")
        queueManager.enqueue(items)

        // Watch for completions
        Task {
            await watchQueue()
        }
    }

    func enqueueURL(_ urlString: String, speakerDetection: Bool, speakerNames: [String]) {
        guard let queueManager else { return }
        AppLogger.info("Queue", "Resolving URL \(urlString)")
        let placeholder = QueueItem(
            title: urlString,
            sourceURL: URL(string: urlString),
            sourceType: .url,
            speakerDetection: speakerDetection,
            speakerNames: defaultSpeakerNames(for: speakerNames, enabled: speakerDetection)
        )
        placeholder.status = .resolving

        queueManager.enqueue(placeholder)

        Task {
            do {
                let resolvedItems = try await YTDLPService.resolveQueueItems(
                    url: urlString,
                    speakerDetection: speakerDetection,
                    speakerNames: defaultSpeakerNames(for: speakerNames, enabled: speakerDetection),
                    dateRange: settings.youtubeDateRange
                )

                await MainActor.run {
                    queueManager.replace(placeholder, with: resolvedItems)
                }
                AppLogger.info("Queue", "Resolved URL into \(resolvedItems.count) queue item(s)")
                await watchQueue()
            } catch {
                AppLogger.error("Queue", "URL resolution failed for \(urlString): \(error.localizedDescription)")
                await MainActor.run {
                    placeholder.status = .failed
                    placeholder.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func enqueueSpotifyURL(_ urlString: String, speakerDetection: Bool, speakerNames: [String]) {
        guard let queueManager, let spotifyPodcastService else { return }
        guard spotifyPodcastService.isConnected else {
            AppLogger.error("Queue", "Cannot enqueue Spotify URL — not connected to Spotify")
            return
        }

        AppLogger.info("Queue", "Resolving Spotify URL \(urlString)")
        let placeholder = QueueItem(
            title: urlString,
            sourceURL: URL(string: urlString),
            sourceType: .url,
            remoteSource: .spotify,
            speakerDetection: speakerDetection,
            speakerNames: defaultSpeakerNames(for: speakerNames, enabled: speakerDetection)
        )
        placeholder.status = .resolving
        queueManager.enqueue(placeholder)

        Task {
            do {
                guard let target = SpotifyURLTarget.parse(from: urlString) else {
                    throw SpotifyServiceError.invalidURL
                }

                switch target {
                case .episode(let id):
                    let episode = try await spotifyPodcastService.resolveEpisode(id: id)

                    // The /episodes/{id} endpoint embeds the show; fall back to a separate lookup
                    let resolvedShow: SpotifyShow
                    if let embeddedShow = episode.show {
                        resolvedShow = embeddedShow
                    } else {
                        throw SpotifyServiceError.apiError(0, "Episode has no associated show")
                    }

                    let item = spotifyPodcastService.createQueueItem(
                        from: episode,
                        show: resolvedShow,
                        speakerDetection: speakerDetection,
                        speakerNames: defaultSpeakerNames(for: speakerNames, enabled: speakerDetection)
                    )

                    await MainActor.run {
                        queueManager.replace(placeholder, with: [item])
                    }

                case .show(let id):
                    let show = try await spotifyPodcastService.resolveShow(id: id)
                    let episodes = await spotifyPodcastService.loadShowEpisodes(showID: id)
                    let items = spotifyPodcastService.createQueueItems(
                        from: episodes,
                        show: show,
                        speakerDetection: speakerDetection,
                        speakerNames: defaultSpeakerNames(for: speakerNames, enabled: speakerDetection)
                    )

                    await MainActor.run {
                        queueManager.replace(placeholder, with: items)
                    }
                }

                AppLogger.info("Queue", "Resolved Spotify URL into queue items")
                await watchQueue()
            } catch {
                AppLogger.error("Queue", "Spotify URL resolution failed: \(error.localizedDescription)")
                await MainActor.run {
                    placeholder.status = .failed
                    placeholder.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func enqueueSpotifyEpisodes(
        _ episodes: [SpotifyEpisode],
        show: SpotifyShow,
        speakerDetection: Bool,
        speakerNames: [String]
    ) {
        guard let queueManager, let spotifyPodcastService else { return }

        for episode in episodes {
            settings.markEpisodeProcessed(episode.id)
        }

        let items = spotifyPodcastService.createQueueItems(
            from: episodes,
            show: show,
            speakerDetection: speakerDetection,
            speakerNames: defaultSpeakerNames(for: speakerNames, enabled: speakerDetection)
        )

        AppLogger.info("Queue", "Enqueuing \(items.count) Spotify episode(s) from \(show.name)")
        queueManager.enqueue(items)

        Task {
            await watchQueue()
        }
    }

    func cancelQueueItem(_ item: QueueItem) {
        AppLogger.info("Queue", "Cancelling queue item \(item.title)")
        queueManager?.cancel(item)
    }

    func retryQueueItem(_ item: QueueItem) {
        AppLogger.info("Queue", "Retrying queue item \(item.title)")
        if let transcriptId = item.resultTranscriptId {
            try? repository?.delete(id: transcriptId)
            if selectedTranscriptId == transcriptId {
                selectedTranscriptId = nil
            }
            item.resultTranscriptId = nil
            refreshTranscripts()
        }

        queueManager?.retry(item)

        Task {
            await watchQueue()
        }
    }

    private func defaultSpeakerNames(for speakerNames: [String], enabled: Bool) -> [String] {
        guard enabled else { return [] }
        if !speakerNames.isEmpty {
            return speakerNames.enumerated().map { index, name in
                name.isEmpty ? "Speaker \(index + 1)" : name
            }
        }
        return []
    }

    func updateAutoDownloadPolling() {
        if settings.spotifyAutoDownloadEnabled {
            startAutoDownloadPolling()
        } else {
            stopAutoDownloadPolling()
        }
    }

    private func startAutoDownloadPolling() {
        autoDownloadTask?.cancel()
        autoDownloadTask = Task { [weak self] in
            await self?.checkForFinishedEpisodes()

            while !Task.isCancelled {
                guard let self else { return }
                let seconds = max(self.settings.spotifyAutoDownloadIntervalMinutes, 1) * 60
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self.checkForFinishedEpisodes()
            }
        }
    }

    private func stopAutoDownloadPolling() {
        autoDownloadTask?.cancel()
        autoDownloadTask = nil
    }

    func resetSessionBaseline() {
        sessionBaselineEpisodeIDs = nil
    }

    private func checkForFinishedEpisodes() async {
        guard settings.spotifyAutoDownloadEnabled,
              let spotifyPodcastService,
              spotifyPodcastService.isConnected,
              queueManager != nil
        else { return }

        AppLogger.info("AutoDownload", "Checking for new finished episodes...")
        await spotifyPodcastService.loadSavedEpisodes()

        let allFinishedIDs = Set(
            spotifyPodcastService.savedEpisodes
                .filter(\.isFullyPlayed)
                .map(\.id)
        )

        if sessionBaselineEpisodeIDs == nil {
            sessionBaselineEpisodeIDs = allFinishedIDs
            AppLogger.info("AutoDownload", "Recorded baseline of \(allFinishedIDs.count) already-finished episode(s)")
            return
        }

        let newFinished = spotifyPodcastService.savedEpisodes
            .filter(\.isFullyPlayed)
            .filter { !sessionBaselineEpisodeIDs!.contains($0.id) }
            .filter { !settings.spotifyProcessedEpisodeIDs.contains($0.id) }
            .filter { $0.show != nil }

        guard !newFinished.isEmpty else {
            AppLogger.info("AutoDownload", "No new finished episodes found")
            return
        }

        AppLogger.info("AutoDownload", "Found \(newFinished.count) new finished episode(s)")

        let grouped = Dictionary(grouping: newFinished) { $0.show!.id }
        for (_, episodes) in grouped {
            guard let show = episodes.first?.show else { continue }
            if spotifyPodcastService.isShowExclusive(show.id) {
                for ep in episodes { settings.markEpisodeProcessed(ep.id) }
                continue
            }
            enqueueSpotifyEpisodes(episodes, show: show,
                speakerDetection: settings.speakerDetection, speakerNames: [])
        }
    }

    private func handleAIAutoExport(transcriptId: Int64) async {
        guard settings.aiAutoExportEnabled,
              settings.aiAutoExportPromptID != nil,
              settings.autoExportURL != nil,
              codexService.isSignedIn,
              repository != nil
        else { return }

        pendingAIAutoExports.append(transcriptId)
        AppLogger.info("AIAutoExport", "Queued transcript \(transcriptId) for AI auto-export (\(pendingAIAutoExports.count) pending)")
        await drainAIAutoExportQueue()
    }

    private func drainAIAutoExportQueue() async {
        guard !isProcessingAIAutoExports else { return }
        isProcessingAIAutoExports = true
        defer { isProcessingAIAutoExports = false }

        while !pendingAIAutoExports.isEmpty {
            // Wait if a manual AI task has priority
            while codexService.isRunningTask {
                try? await Task.sleep(for: .seconds(2))
            }

            let transcriptId = pendingAIAutoExports.removeFirst()
            await executeAIAutoExport(transcriptId: transcriptId)
        }
    }

    private func executeAIAutoExport(transcriptId: Int64) async {
        guard let promptID = settings.aiAutoExportPromptID,
              let folderURL = settings.autoExportURL,
              let repo = repository
        else { return }

        guard let promptTemplate = codexService.availablePromptTemplates.first(where: { $0.id == promptID }) else {
            AppLogger.error("AIAutoExport", "Selected prompt template not found: \(promptID)")
            return
        }

        do {
            guard let transcript = try repo.fetch(id: transcriptId) else {
                AppLogger.error("AIAutoExport", "Transcript not found: \(transcriptId)")
                return
            }
            let segments = try repo.fetchSegments(transcriptId: transcriptId)

            let resultContent = try await codexService.runTranscriptTask(
                promptTemplate,
                transcript: transcript,
                segments: segments
            )

            var aiResult = TranscriptAIResult(
                transcriptId: transcriptId,
                promptID: promptTemplate.id,
                promptTitle: promptTemplate.title,
                promptBody: promptTemplate.body,
                content: resultContent,
                createdAt: Date()
            )
            try repo.saveAIResult(&aiResult)

            try ExportService.autoExportAIContent(
                title: transcript.title,
                promptTitle: promptTemplate.title,
                content: resultContent,
                to: folderURL
            )

            AppLogger.info("AIAutoExport", "Exported AI result for '\(transcript.title)' with prompt '\(promptTemplate.title)'")
        } catch {
            AppLogger.error("AIAutoExport", "Failed for transcript \(transcriptId): \(error.localizedDescription)")
        }
    }

    private func watchQueue() async {
        // Poll for completed items and refresh transcript list
        while queueManager?.isProcessing == true {
            try? await Task.sleep(for: .seconds(1))
            refreshTranscripts()
        }
        refreshTranscripts()
    }

    private func repairTranscriptDurationsIfNeeded() async {
        guard let repository else { return }

        let candidates = transcripts.filter { ($0.durationSeconds ?? 0) <= 0 }
        guard !candidates.isEmpty else { return }

        var repairedCount = 0

        for transcript in candidates {
            guard let transcriptID = transcript.id else { continue }

            let repairedDuration = await inferredDuration(
                for: transcript,
                repository: repository
            )

            guard let repairedDuration, repairedDuration > 0 else { continue }

            do {
                try repository.updateStatus(
                    transcriptID,
                    status: transcript.status,
                    durationSeconds: repairedDuration
                )
                repairedCount += 1
            } catch {
                AppLogger.error(
                    "AppState",
                    "Failed to repair duration for transcript \(transcriptID): \(error.localizedDescription)"
                )
            }
        }

        guard repairedCount > 0 else { return }

        transcripts = (try? repository.fetchFiltered(category: selectedCategory, dateFilter: selectedDateFilter)) ?? transcripts
        AppLogger.info("AppState", "Repaired durations for \(repairedCount) transcript(s)")
    }

    private func inferredDuration(
        for transcript: Transcript,
        repository: TranscriptRepository
    ) async -> Double? {
        if transcript.sourceType == .file {
            let sourceURL = URL(fileURLWithPath: transcript.sourcePath)
            if FileManager.default.fileExists(atPath: sourceURL.path),
               let detectedDuration = try? await FFmpegService.audioDuration(of: sourceURL),
               detectedDuration > 0 {
                return detectedDuration
            }
        }

        guard let transcriptID = transcript.id,
              let maxEndTime = (try? repository.fetchSegments(transcriptId: transcriptID))?.map(\.endTime).max(),
              maxEndTime > 0
        else {
            return nil
        }

        return maxEndTime
    }
}
