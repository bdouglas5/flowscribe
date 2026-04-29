import Foundation
import SwiftUI

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case general
    case youtube
    case recording
    case storage
    case ai
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .youtube: "YouTube"
        case .recording: "Recording"
        case .storage: "Storage"
        case .ai: "AI"
        case .spotify: "Spotify"
        }
    }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .youtube: "play.rectangle"
        case .recording: "mic"
        case .storage: "externaldrive"
        case .ai: "sparkles"
        case .spotify: "waveform"
        }
    }

    var summary: String {
        switch self {
        case .general:
            "App-wide defaults, appearance, and export behavior."
        case .youtube:
            "How channel and playlist imports are organized."
        case .recording:
            "Capture inputs, live transcription, and saved audio."
        case .storage:
            "Disk usage, cleanup tools, and local transcript storage."
        case .ai:
            "Prompt library and on-device AI behavior."
        case .spotify:
            "Podcast connection and automatic downloads."
        }
    }
}

@Observable
final class AppSettings {
    let defaults: UserDefaults

    var speakerDetection: Bool {
        didSet { defaults.set(speakerDetection, forKey: "speakerDetection") }
    }

    var showTimestamps: Bool {
        didSet { defaults.set(showTimestamps, forKey: "showTimestamps") }
    }

    var hasCompletedFirstLaunch: Bool {
        didSet { defaults.set(hasCompletedFirstLaunch, forKey: "hasCompletedFirstLaunch") }
    }

    var autoExportEnabled: Bool {
        didSet { defaults.set(autoExportEnabled, forKey: "autoExportEnabled") }
    }

    var autoExportBookmark: Data? {
        didSet { defaults.set(autoExportBookmark, forKey: "autoExportBookmark") }
    }

    var aiAutoExportEnabled: Bool {
        didSet { defaults.set(aiAutoExportEnabled, forKey: "aiAutoExportEnabled") }
    }

    var aiAutoExportPromptID: String? {
        didSet { defaults.set(aiAutoExportPromptID, forKey: "aiAutoExportPromptID") }
    }

    var selectedAIModelID: String {
        didSet { defaults.set(selectedAIModelID, forKey: "selectedAIModelID") }
    }

    var aiAutoUnloadMinutes: Int {
        didSet { defaults.set(aiAutoUnloadMinutes, forKey: "aiAutoUnloadMinutes") }
    }

    var spotifyClientID: String? {
        didSet { defaults.set(spotifyClientID, forKey: "spotifyClientID") }
    }

    var spotifyRSSFeedCache: [String: String] {
        didSet { defaults.set(spotifyRSSFeedCache, forKey: "spotifyRSSFeedCache") }
    }

    var spotifyAutoDownloadEnabled: Bool {
        didSet { defaults.set(spotifyAutoDownloadEnabled, forKey: "spotifyAutoDownloadEnabled") }
    }

    var spotifyAutoDownloadIntervalMinutes: Int {
        didSet { defaults.set(spotifyAutoDownloadIntervalMinutes, forKey: "spotifyAutoDownloadIntervalMinutes") }
    }

    var spotifyProcessedEpisodeIDs: Set<String> {
        didSet { defaults.set(Array(spotifyProcessedEpisodeIDs), forKey: "spotifyProcessedEpisodeIDs") }
    }

    var autoExportURL: URL? {
        guard let bookmark = autoExportBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale {
            autoExportBookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        return url
    }

    var youtubeDateRange: YouTubeDateRange {
        didSet { defaults.set(youtubeDateRange.rawValue, forKey: "youtubeDateRange") }
    }

    var youtubeAutoGroupByChannel: Bool {
        didSet { defaults.set(youtubeAutoGroupByChannel, forKey: "youtubeAutoGroupByChannel") }
    }

    var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    var recordingInputDeviceID: String? {
        didSet { defaults.set(recordingInputDeviceID, forKey: "recordingInputDeviceID") }
    }

    var recordingLiveMode: RecordingLiveMode {
        didSet { defaults.set(recordingLiveMode.rawValue, forKey: "recordingLiveMode") }
    }

    var recordingRunFinalPass: Bool {
        didSet { defaults.set(recordingRunFinalPass, forKey: "recordingRunFinalPass") }
    }

    var recordingRunAIPrompt: Bool {
        didSet { defaults.set(recordingRunAIPrompt, forKey: "recordingRunAIPrompt") }
    }

    var recordingAIPromptID: String? {
        didSet { defaults.set(recordingAIPromptID, forKey: "recordingAIPromptID") }
    }

    var recordingAudioQuality: RecordingAudioQuality {
        didSet { defaults.set(recordingAudioQuality.rawValue, forKey: "recordingAudioQuality") }
    }

    var recordingKeepOriginalAudio: Bool {
        didSet { defaults.set(recordingKeepOriginalAudio, forKey: "recordingKeepOriginalAudio") }
    }

    var recordingAudioBookmark: Data? {
        didSet { defaults.set(recordingAudioBookmark, forKey: "recordingAudioBookmark") }
    }

    var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var recordingAudioURL: URL? {
        guard let bookmark = recordingAudioBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale {
            recordingAudioBookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        return url
    }

    enum AppearanceMode: String, CaseIterable {
        case system
        case light
        case dark

        var displayName: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    enum RecordingLiveMode: String, CaseIterable {
        case automatic
        case streamingEnglish
        case chunkedMultilingual

        var displayName: String {
            switch self {
            case .automatic: "Automatic"
            case .streamingEnglish: "English Streaming"
            case .chunkedMultilingual: "Multilingual Chunked"
            }
        }
    }

    enum RecordingAudioQuality: String, CaseIterable {
        case speechOptimized
        case high

        var displayName: String {
            switch self {
            case .speechOptimized: "Speech Optimized (16 kHz)"
            case .high: "High Quality (Device Native)"
            }
        }
    }

    enum YouTubeDateRange: String, CaseIterable {
        case allTime = "all"
        case lastYear = "year"
        case lastMonth = "month"
        case lastWeek = "week"
        case lastDay = "day"

        var displayName: String {
            switch self {
            case .allTime: "All Time"
            case .lastYear: "Last Year"
            case .lastMonth: "Last Month"
            case .lastWeek: "Last Week"
            case .lastDay: "Last Day"
            }
        }

        var ytdlpDateString: String {
            switch self {
            case .allTime: ""
            case .lastYear: "today-1year"
            case .lastMonth: "today-1month"
            case .lastWeek: "today-7days"
            case .lastDay: "today-1day"
            }
        }
    }

    func markEpisodeProcessed(_ episodeID: String) {
        spotifyProcessedEpisodeIDs.insert(episodeID)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.speakerDetection = defaults.bool(forKey: "speakerDetection")
        self.showTimestamps = defaults.bool(forKey: "showTimestamps")
        self.hasCompletedFirstLaunch = defaults.bool(forKey: "hasCompletedFirstLaunch")
        self.autoExportEnabled = defaults.bool(forKey: "autoExportEnabled")
        self.autoExportBookmark = defaults.data(forKey: "autoExportBookmark")
        self.aiAutoExportEnabled = defaults.bool(forKey: "aiAutoExportEnabled")
        self.aiAutoExportPromptID = defaults.string(forKey: "aiAutoExportPromptID")
        self.selectedAIModelID = defaults.string(forKey: "selectedAIModelID")
            ?? AIModelCatalog.defaultModel.id
        let rawUnload = defaults.integer(forKey: "aiAutoUnloadMinutes")
        self.aiAutoUnloadMinutes = rawUnload > 0 ? rawUnload : 15
        self.spotifyClientID = defaults.string(forKey: "spotifyClientID")
        self.spotifyRSSFeedCache = (defaults.dictionary(forKey: "spotifyRSSFeedCache") as? [String: String]) ?? [:]
        self.spotifyAutoDownloadEnabled = defaults.bool(forKey: "spotifyAutoDownloadEnabled")
        let rawInterval = defaults.integer(forKey: "spotifyAutoDownloadIntervalMinutes")
        self.spotifyAutoDownloadIntervalMinutes = rawInterval > 0 ? rawInterval : 30
        self.spotifyProcessedEpisodeIDs = Set(defaults.stringArray(forKey: "spotifyProcessedEpisodeIDs") ?? [])
        self.youtubeDateRange = YouTubeDateRange(
            rawValue: defaults.string(forKey: "youtubeDateRange") ?? ""
        ) ?? .allTime
        self.youtubeAutoGroupByChannel = defaults.bool(forKey: "youtubeAutoGroupByChannel")
        self.appearanceMode = AppearanceMode(
            rawValue: defaults.string(forKey: "appearanceMode") ?? ""
        ) ?? .dark
        self.recordingInputDeviceID = defaults.string(forKey: "recordingInputDeviceID")
        self.recordingLiveMode = RecordingLiveMode(
            rawValue: defaults.string(forKey: "recordingLiveMode") ?? ""
        ) ?? .automatic
        self.recordingRunFinalPass = defaults.object(forKey: "recordingRunFinalPass") == nil
            ? true
            : defaults.bool(forKey: "recordingRunFinalPass")
        self.recordingRunAIPrompt = defaults.bool(forKey: "recordingRunAIPrompt")
        self.recordingAIPromptID = defaults.string(forKey: "recordingAIPromptID")
        self.recordingAudioQuality = RecordingAudioQuality(
            rawValue: defaults.string(forKey: "recordingAudioQuality") ?? ""
        ) ?? .high
        self.recordingKeepOriginalAudio = defaults.bool(forKey: "recordingKeepOriginalAudio")
        self.recordingAudioBookmark = defaults.data(forKey: "recordingAudioBookmark")
    }
}

extension AppSettings.RecordingLiveMode {
    var resolvedRecorderMode: Self {
        switch self {
        case .automatic:
            return .streamingEnglish
        case .streamingEnglish, .chunkedMultilingual:
            return self
        }
    }

    var requiresStreamingWarmup: Bool {
        resolvedRecorderMode == .streamingEnglish
    }
}
