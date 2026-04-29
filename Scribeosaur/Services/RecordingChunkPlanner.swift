import Foundation

struct RecordingChunkPlanner {
    private(set) var speechStartedAt: Double?

    let maxChunkDuration: Double
    let maxSilenceDuration: Double

    init(
        maxChunkDuration: Double = 12.0,
        maxSilenceDuration: Double = 0.9
    ) {
        self.maxChunkDuration = maxChunkDuration
        self.maxSilenceDuration = maxSilenceDuration
    }

    mutating func registerVoiceActivity(at elapsedSeconds: Double) {
        if speechStartedAt == nil {
            speechStartedAt = elapsedSeconds
        }
    }

    mutating func reset() {
        speechStartedAt = nil
    }

    mutating func shouldFlushChunk(
        at elapsedSeconds: Double,
        speechActive: Bool,
        currentChunkDuration: Double,
        currentSilenceDuration: Double
    ) -> Bool {
        if speechStartedAt == nil, speechActive {
            speechStartedAt = elapsedSeconds
        }

        guard speechStartedAt != nil else { return false }

        if currentChunkDuration >= maxChunkDuration {
            speechStartedAt = nil
            return true
        }

        if !speechActive,
           currentChunkDuration > 0,
           currentSilenceDuration >= maxSilenceDuration {
            speechStartedAt = nil
            return true
        }

        return false
    }
}
