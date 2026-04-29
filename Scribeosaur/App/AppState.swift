import AppKit
import Foundation
import Observation

enum AppStartupError: LocalizedError {
    case dependencyProvisioningFailed(String)

    var errorDescription: String? {
        switch self {
        case .dependencyProvisioningFailed(let reason):
            reason
        }
    }
}

private enum StartupExecutionStep {
    case idle
    case initializing
    case provisioningDependencies
    case loadingCoreModels
    case preparingAI
    case finalizing
    case failed
}

private struct StartupPresentationBlueprint {
    let phase: StartupPhase
    let headline: String
    let detail: String
    let targetProgress: Double
    let visibleStages: [StartupVisibleStage]
}

enum AppDestination: Hashable {
    case library
    case settings
}

@Observable
@MainActor
final class AppState {
    private static let lastSelectedSettingsSectionKey = "lastSelectedSettingsSection"

    let settings: AppSettings
    let provisioningService: ProvisioningService
    let aiService: GemmaService
    let spotifyAuthService: SpotifyAuthService
    private(set) var spotifyPodcastService: SpotifyPodcastService?

    private(set) var databaseManager: DatabaseManager?
    private(set) var repository: TranscriptRepository?
    private(set) var transcriptionService = TranscriptionService()
    private(set) var diarizationService = DiarizationService()
    private(set) var audioPipelineService: AudioPipelineService?
    private(set) var queueManager: QueueManager?
    private(set) var liveTranscriptionService: LiveTranscriptionService?

    private var autoDownloadTask: Task<Void, Never>?
    private var sessionBaselineEpisodeIDs: Set<String>?
    private var pendingAIAutoExports: [Int64] = []
    private var isProcessingAIAutoExports = false
    private var transcriptContextPreparer: TranscriptContextPreparer?
    private var transcriptContextTasks: [Int64: Task<Void, Never>] = [:]
    private var activeRecordingSessionID: UUID?
    private let urlResolutionCoordinator = URLResolutionCoordinator()
    private var startupPresentationTask: Task<Void, Never>?
    private var startupStep: StartupExecutionStep = .idle
    private var startupLaunchMode: StartupLaunchMode = .firstInstall
    private var startupSessionIncludesAIStages = false
    private var startupSessionShowsDownloadStage = false

    var transcripts: [Transcript] = []
    var selectedTranscriptId: Int64?
    var selectedCategory: TranscriptCategory = .all
    var selectedDateFilter: DateFilter = .allTime
    var activeSearchQuery: String = ""
    var currentMatchIndex: Int = 0
    var totalMatchCount: Int = 0
    var currentDestination: AppDestination = .library
    var isReady = false
    var isStartingUp = false
    var setupError: String?
    var startupRequiresAIModel = false
    var startupPresentation = StartupPresentationState()
    var recordingState = RecordingSessionState()
    var recordingAlertMessage: String?
    var requestedSettingsSection: SettingsSection?
    var lastSelectedSettingsSection: SettingsSection {
        didSet {
            settings.defaults.set(
                lastSelectedSettingsSection.rawValue,
                forKey: Self.lastSelectedSettingsSectionKey
            )
        }
    }

    init(
        settings: AppSettings? = nil,
        provisioningService: ProvisioningService? = nil,
        aiService: GemmaService? = nil,
        spotifyAuthService: SpotifyAuthService? = nil
    ) {
        self.settings = settings ?? AppSettings()
        self.provisioningService = provisioningService ?? ProvisioningService()
        self.aiService = aiService ?? GemmaService()
        self.spotifyAuthService = spotifyAuthService ?? SpotifyAuthService()
        self.lastSelectedSettingsSection = SettingsSection(
            rawValue: self.settings.defaults.string(forKey: Self.lastSelectedSettingsSectionKey) ?? ""
        ) ?? .general
    }

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
            try await initializeCoreState()
        } catch {
            AppLogger.error("AppState", "Initialization failed: \(error.localizedDescription)")
            setupError = error.localizedDescription
        }
    }

    func startApplication(
        initializeCore: (() async throws -> Void)? = nil,
        provisionDependencies: (() async throws -> Void)? = nil,
        loadCoreModels: (() async throws -> Void)? = nil,
        prepareAIModel: (() async throws -> Void)? = nil
    ) async {
        guard !isStartingUp else { return }

        isStartingUp = true
        isReady = false
        setupError = nil
        startupRequiresAIModel = false
        startupStep = .initializing
        startupLaunchMode = settings.hasCompletedFirstLaunch ? .returningQuickCheck : .firstInstall
        startupSessionIncludesAIStages = startupLaunchMode == .firstInstall
        startupSessionShowsDownloadStage = false
        startupPresentation.beginSession(
            now: Date(),
            launchMode: startupLaunchMode,
            visibleStages: startupVisibleStages
        )
        startStartupPresentationMonitor()
        refreshStartupPresentation(now: Date())

        defer {
            isStartingUp = false
            stopStartupPresentationMonitor()
        }

        do {
            if let initializeCore {
                try await initializeCore()
            } else {
                try await initializeCoreState()
            }

            try await performStartupSetup(
                markReadyOnCompletion: false,
                provisionDependencies: provisionDependencies,
                loadCoreModels: loadCoreModels,
                prepareAIModel: prepareAIModel
            )

            startupStep = .finalizing
            refreshStartupPresentation(now: Date())
            await enforceMinimumStartupVisibilityIfNeeded()
            startupPresentation.complete(now: Date())
            try? await Task.sleep(
                for: startupLaunchMode == .firstInstall ? .milliseconds(350) : .milliseconds(180)
            )

            isReady = true
            startupStep = .idle
        } catch {
            AppLogger.error("AppState", "Application startup failed: \(error.localizedDescription)")
            setupError = error.localizedDescription
            startupStep = .failed
            startupPresentation.fail(details: error.localizedDescription, now: Date())
        }
    }

    func runStartupSetup(
        provisionDependencies: (() async throws -> Void)? = nil,
        loadCoreModels: (() async throws -> Void)? = nil,
        prepareAIModel: (() async throws -> Void)? = nil
    ) async {
        setupError = nil
        isReady = false

        do {
            try await performStartupSetup(
                markReadyOnCompletion: true,
                provisionDependencies: provisionDependencies,
                loadCoreModels: loadCoreModels,
                prepareAIModel: prepareAIModel
            )
        } catch {
            AppLogger.error("AppState", "Startup setup failed: \(error.localizedDescription)")
            setupError = error.localizedDescription
        }
    }

    private func initializeCoreState() async throws {
        setupError = nil
        AppLogger.info("AppState", "Initializing app state")
        try StoragePaths.ensureDirectoriesExist()
        try StoragePaths.clearTemp()
        await aiService.refreshStatus()

        let dbManager = try DatabaseManager()
        let repo = TranscriptRepository(dbQueue: dbManager.dbQueue)

        let spotifyService = SpotifyPodcastService(
            authService: spotifyAuthService,
            settings: settings
        )
        self.spotifyPodcastService = spotifyService

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
        let liveTranscription = LiveTranscriptionService(transcriptionService: transcriptionService)
        await liveTranscription.setEventHandler { [weak self] event in
            self?.handleRecordingEvent(event)
        }

        self.databaseManager = dbManager
        self.repository = repo
        self.transcriptContextPreparer = TranscriptContextPreparer(repository: repo) { [weak self] in
            self?.aiService.isRunningTask ?? false
        }
        self.audioPipelineService = pipeline

        let queue = QueueManager(pipeline: pipeline)
        queue.onItemCompleted = { [weak self] transcriptId, item in
            Task { @MainActor in
                self?.scheduleTranscriptContextPreparation(transcriptId: transcriptId)
                await self?.handleAIAutoExport(transcriptId: transcriptId)
                if let episodeID = item.spotifyMetadata?.episodeID {
                    self?.settings.markEpisodeProcessed(episodeID)
                }
            }
        }
        self.queueManager = queue
        self.liveTranscriptionService = liveTranscription

        transcripts = try repo.fetchFiltered(category: selectedCategory, dateFilter: selectedDateFilter)
        scheduleRecentTranscriptContextPreparation()
        await repairTranscriptDurationsIfNeeded()
        await refreshRecordingDevices()
        Task { [weak self] in
            await self?.prewarmRecordingModels()
        }
        AppLogger.info("AppState", "Initialization complete. transcripts=\(transcripts.count)")

        if settings.spotifyAutoDownloadEnabled {
            startAutoDownloadPolling()
        }
    }

    private func performStartupSetup(
        markReadyOnCompletion: Bool,
        provisionDependencies: (() async throws -> Void)?,
        loadCoreModels: (() async throws -> Void)?,
        prepareAIModel: (() async throws -> Void)?
    ) async throws {
        let shouldPrepareAIModel: Bool
        if !settings.hasCompletedFirstLaunch {
            shouldPrepareAIModel = true
        } else {
            shouldPrepareAIModel = await aiService.selectedModelNeedsStartupPreparation()
        }
        startupRequiresAIModel = shouldPrepareAIModel
        startupSessionIncludesAIStages = startupLaunchMode == .firstInstall || shouldPrepareAIModel
        AppLogger.info(
            "AppState",
            "Running startup setup. requiresAIStartup=\(shouldPrepareAIModel) persistedFirstLaunch=\(settings.hasCompletedFirstLaunch) speakerDetection=\(settings.speakerDetection)"
        )

        startupStep = .provisioningDependencies
        refreshStartupPresentation(now: Date())
        if let provisionDependencies {
            try await provisionDependencies()
        } else {
            try await provisionDependenciesForStartup()
        }

        startupStep = .loadingCoreModels
        refreshStartupPresentation(now: Date())
        if let loadCoreModels {
            try await loadCoreModels()
        } else {
            try await loadCoreModelsForStartup()
        }

        if shouldPrepareAIModel {
            startupStep = .preparingAI
            refreshStartupPresentation(now: Date())
            if let prepareAIModel {
                try await prepareAIModel()
            } else {
                try await aiService.prepareSelectedModelIfNeeded()
            }
            settings.hasCompletedFirstLaunch = true
        }

        startupStep = .finalizing
        startupRequiresAIModel = false
        if markReadyOnCompletion {
            isReady = true
        }
        AppLogger.info("AppState", "Startup setup complete. aiPrepared=\(shouldPrepareAIModel)")
    }

    private func provisionDependenciesForStartup() async throws {
        await provisioningService.provisionIfNeeded()
        if let error = provisioningService.error {
            throw AppStartupError.dependencyProvisioningFailed(error)
        }
    }

    private func loadCoreModelsForStartup() async throws {
        AppLogger.info(
            "AppState",
            "Loading startup models. speakerDetection=\(settings.speakerDetection)"
        )
        try await transcriptionService.loadModel()
        if settings.speakerDetection {
            try await diarizationService.loadModel()
        }
        AppLogger.info("AppState", "Startup models loaded successfully")
    }

    private func startStartupPresentationMonitor() {
        startupPresentationTask?.cancel()
        startupPresentationTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, !self.isReady, self.setupError == nil {
                self.refreshStartupPresentation(now: Date())
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func stopStartupPresentationMonitor() {
        startupPresentationTask?.cancel()
        startupPresentationTask = nil
    }

    private func enforceMinimumStartupVisibilityIfNeeded() async {
        guard startupLaunchMode == .returningQuickCheck,
              let minimumVisibleUntil = startupPresentation.minimumVisibleUntil
        else {
            return
        }

        let remaining = minimumVisibleUntil.timeIntervalSinceNow
        guard remaining > 0 else { return }

        try? await Task.sleep(for: .milliseconds(Int((remaining * 1_000).rounded(.up))))
        refreshStartupPresentation(now: Date())
    }

    private func refreshStartupPresentation(now: Date) {
        if let setupError {
            startupPresentation.fail(details: setupError, now: now)
            return
        }

        if aiService.startupStage == .downloadingAssets {
            startupSessionShowsDownloadStage = true
        }

        let blueprint = startupPresentationBlueprint(now: now)
        startupPresentation.update(
            phase: blueprint.phase,
            headline: blueprint.headline,
            detail: blueprint.detail,
            targetProgress: blueprint.targetProgress,
            visibleStages: blueprint.visibleStages,
            now: now
        )
    }

    private func startupPresentationBlueprint(now: Date) -> StartupPresentationBlueprint {
        let elapsed = now.timeIntervalSince(startupPresentation.sessionStartedAt ?? now)
        let visibleStages = startupVisibleStages

        switch startupStep {
        case .idle, .initializing:
            let initializationProgress = min(
                startupLaunchMode == .firstInstall ? 0.08 : 0.20,
                0.02 + (elapsed * (startupLaunchMode == .firstInstall ? 0.02 : 0.10))
            )
            return StartupPresentationBlueprint(
                phase: .preparingWorkspace,
                headline: startupLaunchMode == .firstInstall
                    ? "A private transcript studio is taking shape."
                    : "Running a quick readiness pass.",
                detail: startupLaunchMode == .firstInstall
                    ? "First setup can take a few minutes on a new install."
                    : "Checking the essentials before you jump back in.",
                targetProgress: initializationProgress,
                visibleStages: visibleStages
            )

        case .provisioningDependencies:
            return StartupPresentationBlueprint(
                phase: .preparingWorkspace,
                headline: startupLaunchMode == .firstInstall
                    ? "Getting the workspace ready for its first real session."
                    : "Checking the transcript workspace and helper layer.",
                detail: startupLaunchMode == .firstInstall
                    ? "Scribeosaur is preparing the local pieces that make imports and recordings feel seamless."
                    : "This short pass keeps imports, recordings, and exports dependable.",
                targetProgress: mappedProgress(
                    provisioningService.startupStageProgress,
                    within: StartupPhase.preparingWorkspace
                ),
                visibleStages: visibleStages
            )

        case .loadingCoreModels:
            return StartupPresentationBlueprint(
                phase: .tuningTranscription,
                headline: startupLaunchMode == .firstInstall
                    ? "Teaching the new workspace to listen fast."
                    : "Checking the transcription stack before you begin.",
                detail: startupLaunchMode == .firstInstall
                    ? "Audio input, transcription, and speaker-aware tools are warming into place."
                    : "A quick warm-up helps the next transcript feel responsive right away.",
                targetProgress: mappedProgress(startupCoreProgress, within: .tuningTranscription),
                visibleStages: visibleStages
            )

        case .preparingAI:
            return StartupPresentationBlueprint(
                phase: .unlockingSmartTools,
                headline: startupLaunchMode == .firstInstall
                    ? "Bringing the on-device finishing layer online."
                    : "Refreshing the on-device tools you rely on.",
                detail: localAITaskDetail,
                targetProgress: mappedProgress(startupAIProgress, within: .unlockingSmartTools),
                visibleStages: visibleStages
            )

        case .finalizing:
            return StartupPresentationBlueprint(
                phase: .finalChecks,
                headline: startupLaunchMode == .firstInstall
                    ? "Putting the final touch on your new workspace."
                    : "Finishing the readiness pass.",
                detail: startupLaunchMode == .firstInstall
                    ? "You’re moments away from the full experience."
                    : "Opening Scribeosaur as soon as the final check lands.",
                targetProgress: 0.98,
                visibleStages: visibleStages
            )

        case .failed:
            return StartupPresentationBlueprint(
                phase: startupPresentation.phase,
                headline: startupPresentation.headline,
                detail: startupPresentation.detail,
                targetProgress: startupPresentation.displayProgress,
                visibleStages: startupPresentation.visibleStages
            )
        }
    }

    private var startupCoreProgress: Double {
        let transcriptionProgress = transcriptionService.isModelLoaded
            ? 1.0
            : max(transcriptionService.modelLoadProgress, 0.08)

        guard settings.speakerDetection else {
            return min(transcriptionProgress, 1.0)
        }

        if diarizationService.isModelLoaded {
            return 1.0
        }

        if transcriptionService.isModelLoaded {
            return 0.82
        }

        return min(transcriptionProgress * 0.82, 0.82)
    }

    private var startupAIProgress: Double {
        let measuredProgress = max(aiService.startupStageProgress, aiService.modelProgress)

        switch aiService.startupStage {
        case .idle:
            return startupRequiresAIModel ? max(measuredProgress, 0.06) : 1.0
        case .preparingRuntime:
            return max(measuredProgress, 0.10)
        case .preparingAssets:
            return max(measuredProgress, 0.18)
        case .downloadingAssets:
            return max(measuredProgress, 0.22)
        case .verifyingAssets:
            return max(measuredProgress, 0.88)
        case .loading:
            return 0.96
        case .ready:
            return 1.0
        case .failed:
            return min(max(measuredProgress, 0.10), 0.96)
        }
    }

    private var localAITaskDetail: String {
        switch aiService.startupStage {
        case .preparingRuntime:
            startupLaunchMode == .firstInstall
                ? "Setting up the local AI tools that keep transcript work private on this Mac."
                : "Checking the local AI layer before you jump back into summaries and exports."
        case .preparingAssets, .downloadingAssets, .verifyingAssets:
            startupLaunchMode == .firstInstall
                ? "First setup can take a few minutes on a new install."
                : "Refreshing the local AI model only because this Mac needs a quick repair."
        case .loading:
            startupLaunchMode == .firstInstall
                ? "Loading on-device summaries so the first transcript feels complete from the start."
                : "Warming the on-device tools that support summaries, notes, and exports."
        case .ready, .idle:
            startupLaunchMode == .firstInstall
                ? "Polishing the on-device tools that help you refine and export with ease."
                : "Everything is nearly ready for the next transcript."
        case .failed:
            "Holding your place while Scribeosaur gets back on track."
        }
    }

    private var startupVisibleStages: [StartupVisibleStage] {
        StartupPresentationState.stages(
            for: startupLaunchMode,
            modelSizeLabel: startupModelDownloadSizeLabel,
            includesAIStages: startupSessionIncludesAIStages,
            includesDownloadStage: startupSessionShowsDownloadStage
        )
    }

    private var startupModelDownloadSizeLabel: String {
        let bytes = aiService.selectedModelDescriptor.estimatedDownloadSizeBytes
        guard bytes > 0 else { return StartupPresentationState.defaultModelSizeLabel }

        let gibibytes = Double(bytes) / 1_000_000_000
        let rounded = max(1, Int(gibibytes.rounded()))
        return "\(rounded) GB"
    }

    private func mappedProgress(_ normalizedProgress: Double, within phase: StartupPhase) -> Double {
        let range = phase.progressRange
        let clamped = min(max(normalizedProgress, 0), 1)
        return range.lowerBound + ((range.upperBound - range.lowerBound) * clamped)
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

    func preparedTranscriptContext(
        for transcript: Transcript,
        segments: [TranscriptSegment]
    ) -> PreparedTranscriptContext? {
        guard let transcriptContextPreparer else { return nil }
        return try? transcriptContextPreparer.preparedContext(
            transcript: transcript,
            segments: segments
        )
    }

    func prepareTranscriptContextIfNeeded(
        transcript: Transcript,
        segments: [TranscriptSegment],
        waitForUserAI: Bool = true
    ) async {
        await transcriptContextPreparer?.prepareIfNeeded(
            transcript: transcript,
            segments: segments,
            waitForUserAI: waitForUserAI
        )
    }

    func scheduleTranscriptContextPreparation(transcriptId: Int64) {
        guard transcriptContextTasks[transcriptId] == nil else { return }

        transcriptContextTasks[transcriptId] = Task { @MainActor [weak self] in
            defer {
                self?.transcriptContextTasks[transcriptId] = nil
            }
            await self?.prepareTranscriptContext(transcriptId: transcriptId, waitForUserAI: true)
        }
    }

    private func scheduleRecentTranscriptContextPreparation(limit: Int = 3) {
        for transcriptId in transcripts.prefix(limit).compactMap(\.id) {
            scheduleTranscriptContextPreparation(transcriptId: transcriptId)
        }
    }

    private func prepareTranscriptContext(
        transcriptId: Int64,
        waitForUserAI: Bool
    ) async {
        guard let repository,
              let transcript = try? repository.fetch(id: transcriptId)
        else {
            return
        }

        let segments = (try? repository.fetchSegments(transcriptId: transcriptId)) ?? []
        await prepareTranscriptContextIfNeeded(
            transcript: transcript,
            segments: segments,
            waitForUserAI: waitForUserAI
        )
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
        transcriptContextTasks[id]?.cancel()
        transcriptContextTasks[id] = nil
        try? repository.delete(id: id)
        try? TranscriptMarkdownFileStorage.deleteTranscriptDirectory(transcriptID: id)
        if selectedTranscriptId == id {
            selectedTranscriptId = nil
        }
        refreshTranscripts()
    }

    func deleteCollection(id: String) {
        guard let repository else { return }
        let transcriptIDs = transcripts
            .filter { $0.collectionID == id }
            .compactMap(\.id)
        for transcriptID in transcriptIDs {
            transcriptContextTasks[transcriptID]?.cancel()
            transcriptContextTasks[transcriptID] = nil
        }
        try? repository.deleteCollection(id: id)
        for transcriptID in transcriptIDs {
            try? TranscriptMarkdownFileStorage.deleteTranscriptDirectory(transcriptID: transcriptID)
        }
        if let selectedTranscript, selectedTranscript.collectionID == id {
            selectedTranscriptId = nil
        }
        refreshTranscripts()
    }

    func refreshRecordingDevices() async {
        guard let liveTranscriptionService else { return }
        _ = await liveTranscriptionService.refreshInputDevices(
            preferredID: settings.recordingInputDeviceID
        )
    }

    func prewarmRecordingModels() async {
        guard let liveTranscriptionService else { return }
        await liveTranscriptionService.prewarmRecordingModels(
            for: settings.recordingLiveMode,
            captureSource: .microphone
        )
    }

    func armRecording() async {
        guard let liveTranscriptionService else { return }

        activeRecordingSessionID = nil
        resetRecordingState(to: .armed, statusMessage: "Ready to record")

        let selectedDeviceID = await liveTranscriptionService.armRecorder(
            preferredInputDeviceID: settings.recordingInputDeviceID,
            mode: settings.recordingLiveMode,
            captureSource: .microphone
        )

        if let selectedDeviceID {
            recordingState.selectedInputDeviceID = selectedDeviceID
        }
    }

    func cancelRecordingArm() {
        guard recordingState.phase == .armed else { return }
        activeRecordingSessionID = nil
        resetRecordingState()
    }

    func startRecording() async {
        guard let queueManager, let liveTranscriptionService else { return }
        guard recordingState.phase == .armed else { return }

        if recordingState.warmupState.isPreparing {
            recordingAlertMessage = "Recorder is still preparing. Wait a moment and try again."
            return
        }

        if queueManager.activeItem != nil {
            recordingAlertMessage = "Finish the current queue item before starting a recording."
            return
        }

        if aiService.isRunningTask {
            recordingAlertMessage = "Wait for the current AI task to finish before starting a recording."
            return
        }

        let sessionID = UUID()
        activeRecordingSessionID = sessionID
        queueManager.suspend()
        resetRecordingState(to: .preflighting, statusMessage: "Preparing recording…")

        do {
            let selectedDeviceID = try await liveTranscriptionService.startRecording(
                sessionID: sessionID,
                preferredInputDeviceID: settings.recordingInputDeviceID,
                mode: settings.recordingLiveMode,
                captureSource: .microphone
            )
            if let selectedDeviceID {
                recordingState.selectedInputDeviceID = selectedDeviceID
                settings.recordingInputDeviceID = selectedDeviceID
            }
        } catch {
            activeRecordingSessionID = nil
            queueManager.resume()
            resetRecordingState(to: .failed, errorMessage: error.localizedDescription)
            recordingAlertMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard let liveTranscriptionService,
              let audioPipelineService,
              let sessionID = activeRecordingSessionID
        else { return }

        resetRecordingState(
            to: .finalizing,
            statusMessage: "Finalizing recording…",
            finalizationProgress: 0.05,
            finalizationStep: "Stopping microphone…"
        )

        do {
            let capture = try await liveTranscriptionService.stopRecording()
            let title = recordingTitle(from: Date())

            let transcriptID = try await audioPipelineService.finalizeRecording(
                title: title,
                audioURL: capture.audioURL,
                liveText: capture.liveText,
                liveSegments: capture.draftSegments,
                speakerDetection: settings.speakerDetection,
                speakerNames: [],
                runFinalPass: settings.recordingRunFinalPass
            ) { [weak self] step, progress in
                Task { @MainActor in
                    guard self?.activeRecordingSessionID == sessionID else { return }
                    self?.recordingState.finalizationStep = step
                    self?.recordingState.finalizationProgress = progress
                }
            }

            activeRecordingSessionID = nil
            refreshTranscripts()
            selectedTranscriptId = transcriptID
            scheduleTranscriptContextPreparation(transcriptId: transcriptID)

            if settings.recordingRunAIPrompt {
                await handleRecordingAIPrompt(transcriptId: transcriptID)
            }

            queueManager?.resume()
            resetRecordingState()
        } catch {
            activeRecordingSessionID = nil
            queueManager?.resume()
            resetRecordingState(to: .failed, errorMessage: error.localizedDescription)
            recordingAlertMessage = error.localizedDescription
        }
    }

    func dismissRecordingAlert() {
        recordingAlertMessage = nil
        if recordingState.phase == .failed {
            resetRecordingState()
        }
    }

    func openSettings(section: SettingsSection? = nil) {
        let destination = section ?? lastSelectedSettingsSection
        requestedSettingsSection = destination
        currentDestination = .settings

        if destination == .recording, recordingState.phase == .armed {
            cancelRecordingArm()
        }
    }

    func closeSettings() {
        currentDestination = .library
    }

    func consumeRequestedSettingsSection() -> SettingsSection? {
        let section = requestedSettingsSection
        requestedSettingsSection = nil
        return section
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
        guard let normalizedURL = URLResolutionCoordinator.normalizedURLString(from: urlString) else {
            return
        }
        if let existingItem = activeRemoteQueueItem(matching: normalizedURL) {
            AppLogger.info("Queue", "Skipping duplicate queued URL \(normalizedURL)")
            if let transcriptId = existingItem.resultTranscriptId {
                selectedTranscriptId = transcriptId
            }
            return
        }
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

        Task { [self] in
            do {
                let effectiveSpeakerNames = self.defaultSpeakerNames(
                    for: speakerNames,
                    enabled: speakerDetection
                )
                let resolvedItems = try await urlResolutionCoordinator.resolve(
                    normalizedURL: normalizedURL
                ) {
                    try await YTDLPService.resolveQueueItems(
                        url: urlString,
                        speakerDetection: speakerDetection,
                        speakerNames: effectiveSpeakerNames,
                        dateRange: self.settings.youtubeDateRange
                    )
                }

                await MainActor.run {
                    queueManager.replace(
                        placeholder,
                        with: resolvedItems.map(self.makeQueueItem(from:))
                    )
                }
                AppLogger.info("Queue", "Resolved URL into \(resolvedItems.count) queue item(s)")
                await watchQueue()
            } catch {
                AppLogger.error("Queue", "URL resolution failed for \(urlString): \(error.localizedDescription)")
                let presentation = QueueErrorPresentation.make(from: error, remoteSource: .youtube)
                await MainActor.run {
                    placeholder.status = .failed
                    placeholder.errorMessage = presentation.technicalMessage
                    placeholder.userFacingError = presentation.userMessage
                    placeholder.recoveryAction = presentation.recoveryAction
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

        if item.recoveryAction == .repairYouTubeSupport {
            Task {
                await provisioningService.provisionIfNeeded()
                guard provisioningService.error == nil else { return }
                await MainActor.run {
                    item.recoveryAction = .retry
                    item.userFacingError = nil
                    item.errorMessage = nil
                }
                retryQueueItem(item)
            }
            return
        }

        if let transcriptId = item.resultTranscriptId {
            transcriptContextTasks[transcriptId]?.cancel()
            transcriptContextTasks[transcriptId] = nil
            try? repository?.delete(id: transcriptId)
            try? TranscriptMarkdownFileStorage.deleteTranscriptDirectory(transcriptID: transcriptId)
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

    private func activeRemoteQueueItem(matching normalizedURL: String) -> QueueItem? {
        queueManager?.items.first { item in
            guard let sourceURL = item.sourceURL,
                  let existingNormalized = URLResolutionCoordinator.normalizedURLString(
                    from: sourceURL.absoluteString
                  )
            else {
                return false
            }

            return existingNormalized == normalizedURL
                && item.status != .completed
                && item.status != .failed
        }
    }

    private func makeQueueItem(from resolvedItem: ResolvedRemoteQueueItem) -> QueueItem {
        QueueItem(
            title: resolvedItem.title,
            sourceURL: resolvedItem.sourceURL,
            sourceType: resolvedItem.sourceType,
            remoteSource: resolvedItem.remoteSource,
            collectionID: resolvedItem.collectionID,
            collectionTitle: resolvedItem.collectionTitle,
            collectionType: resolvedItem.collectionType,
            collectionItemIndex: resolvedItem.collectionItemIndex,
            thumbnailURL: resolvedItem.thumbnailURL,
            speakerDetection: resolvedItem.speakerDetection,
            speakerNames: resolvedItem.speakerNames
        )
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
            while aiService.isRunningTask {
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

        guard let promptTemplate = aiService.availablePromptTemplates.first(where: { $0.id == promptID }) else {
            AppLogger.error("AIAutoExport", "Selected prompt template not found: \(promptID)")
            return
        }

        do {
            guard let transcript = try repo.fetch(id: transcriptId) else {
                AppLogger.error("AIAutoExport", "Transcript not found: \(transcriptId)")
                return
            }
            let segments = try repo.fetchSegments(transcriptId: transcriptId)

            let resultContent = try await aiService.runTranscriptTask(
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
        if transcript.sourceType == .file || transcript.sourceType == .recording {
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

    func handleRecordingEvent(_ event: LiveRecordingEvent) {
        guard event.applies(to: activeRecordingSessionID) else { return }

        switch event.payload {
        case .devicesUpdated(let devices, let selectedID):
            recordingState.availableInputDevices = devices
            if let selectedID {
                recordingState.selectedInputDeviceID = selectedID
            }
        case .warmupStatusChanged(let state, let message):
            recordingState.warmupState = state
            recordingState.warmupMessage = message
        case .statusChanged(let message):
            recordingState.statusMessage = message
        case .levelChanged(let level):
            recordingState.audioLevel = level
        case .elapsedChanged(let elapsed):
            recordingState.elapsedSeconds = elapsed
        case .recordingStarted(let selectedDeviceID):
            recordingState.phase = .recording
            recordingState.statusMessage = "Recording"
            if let selectedDeviceID {
                recordingState.selectedInputDeviceID = selectedDeviceID
            }
        }
    }

    private func handleRecordingAIPrompt(transcriptId: Int64) async {
        guard settings.recordingRunAIPrompt,
              let promptID = settings.recordingAIPromptID,
              settings.autoExportURL != nil,
              let promptTemplate = aiService.availablePromptTemplates.first(where: { $0.id == promptID }),
              let repository
        else { return }

        do {
            guard let transcript = try repository.fetch(id: transcriptId) else { return }
            let segments = try repository.fetchSegments(transcriptId: transcriptId)
            let resultContent = try await aiService.runTranscriptTask(
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
            try repository.saveAIResult(&aiResult)

            if let exportURL = settings.autoExportURL {
                try ExportService.autoExportAIContent(
                    title: transcript.title,
                    promptTitle: promptTemplate.title,
                    content: resultContent,
                    to: exportURL
                )
            }
        } catch {
            AppLogger.error("Recording", "Recording AI prompt failed: \(error.localizedDescription)")
        }
    }

    private func resetRecordingState(
        to phase: RecordingSessionState.Phase = .idle,
        statusMessage: String? = nil,
        errorMessage: String? = nil,
        finalizationProgress: Double = 0,
        finalizationStep: String? = nil
    ) {
        let previousState = recordingState
        var nextState = RecordingSessionState()
        nextState.resetPresentationState(preservingConfigurationFrom: previousState)
        nextState.phase = phase
        nextState.statusMessage = statusMessage
        nextState.errorMessage = errorMessage
        nextState.finalizationProgress = finalizationProgress
        nextState.finalizationStep = finalizationStep
        recordingState = nextState
    }

    private func recordingTitle(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Recording \(formatter.string(from: date))"
    }
}
