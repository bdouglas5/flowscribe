import Foundation

struct QueueErrorPresentation {
    let technicalMessage: String
    let userMessage: String
    let recoveryAction: QueueItem.RecoveryAction

    static func make(
        from error: Error,
        remoteSource: Transcript.RemoteSource?
    ) -> QueueErrorPresentation {
        let technicalMessage = error.localizedDescription

        if isDependencyIssue(error: error, remoteSource: remoteSource) {
            return QueueErrorPresentation(
                technicalMessage: technicalMessage,
                userMessage: "Scribosaur couldn't start its YouTube helpers. Repair YouTube Support, then retry.",
                recoveryAction: .repairYouTubeSupport
            )
        }

        if case SubprocessError.timedOut = error {
            return QueueErrorPresentation(
                technicalMessage: technicalMessage,
                userMessage: "This source took too long to respond. Retry the download.",
                recoveryAction: .retry
            )
        }

        return QueueErrorPresentation(
            technicalMessage: technicalMessage,
            userMessage: technicalMessage,
            recoveryAction: .retry
        )
    }

    private static func isDependencyIssue(
        error: Error,
        remoteSource: Transcript.RemoteSource?
    ) -> Bool {
        guard remoteSource == .youtube else { return false }

        if case SubprocessError.binaryNotFound = error {
            return true
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("js runtime")
            || message.contains("deno")
            || message.contains("yt-dlp")
            || message.contains("ffmpeg")
            || message.contains("binary not found")
    }
}
