import Foundation

enum TimeFormatting {
    static func timestamp(from seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    static func bracketedTimestamp(from seconds: Double) -> String {
        "[\(timestamp(from: seconds))]"
    }

    static func bracketedRange(start: Double, end: Double) -> String {
        "[\(timestamp(from: start)) - \(timestamp(from: end))]"
    }

    static func duration(seconds: Double) -> String {
        timestamp(from: seconds)
    }

    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func relativeDate(_ date: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: .now)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func formattedDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
