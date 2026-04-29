import Foundation

enum TranscriptCategory: String, CaseIterable, Identifiable {
    case all
    case youtube
    case spotify
    case localAudio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "All"
        case .youtube: "YouTube"
        case .spotify: "Spotify"
        case .localAudio: "Local Audio"
        }
    }

    static func category(for transcript: Transcript) -> TranscriptCategory {
        if transcript.remoteSource == .spotify { return .spotify }
        if transcript.remoteSource == .youtube { return .youtube }
        return .localAudio
    }

    static func category(for item: QueueItem) -> TranscriptCategory {
        if item.remoteSource == .spotify { return .spotify }
        if item.remoteSource == .youtube { return .youtube }
        if item.sourceType == .file || item.sourceType == .recording { return .localAudio }
        return .localAudio
    }
}

enum DateFilter: String, CaseIterable, Identifiable {
    case allTime
    case today
    case thisWeek
    case thisMonth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allTime: "All Time"
        case .today: "Today"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .allTime:
            return nil
        case .today:
            return calendar.startOfDay(for: now)
        case .thisWeek:
            return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
        case .thisMonth:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        }
    }
}
