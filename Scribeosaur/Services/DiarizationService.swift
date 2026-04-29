import Foundation
import AVFoundation
@preconcurrency import FluidAudio

@Observable
final class DiarizationService {
    var isModelLoaded = false

    private var diarizationManager: OfflineDiarizerManager?
    private var modelLoadingTask: Task<Void, Error>?

    func loadModel() async throws {
        guard !isModelLoaded, diarizationManager == nil else { return }
        if let modelLoadingTask {
            try await modelLoadingTask.value
            return
        }

        let task = Task { @MainActor in
            let manager = OfflineDiarizerManager(config: .default)
            try await manager.prepareModels(
                directory: StoragePaths.models,
                configuration: .init(),
                forceRedownload: false
            )

            self.diarizationManager = manager
            self.isModelLoaded = true
        }
        modelLoadingTask = task

        do {
            try await task.value
        } catch {
            modelLoadingTask = nil
            throw error
        }

        modelLoadingTask = nil
    }

    struct DiarizationResult {
        let segments: [SpeakerSegment]

        struct SpeakerSegment {
            let speakerLabel: String
            let speakerIndex: Int
            let startTime: Double
            let endTime: Double
        }
    }

    func diarize(audioURL: URL, speakerCount: Int? = nil) async throws -> DiarizationResult {
        guard let diarizationManager else {
            throw DiarizationError.modelNotLoaded
        }

        let samples = try loadAudioSamples(from: audioURL)
        let result = try await diarizationManager.process(audio: samples)

        // Collect unique speaker IDs to map strings to indices
        var speakerIdMap: [String: Int] = [:]
        var nextIndex = 0
        for seg in result.segments {
            if speakerIdMap[seg.speakerId] == nil {
                speakerIdMap[seg.speakerId] = nextIndex
                nextIndex += 1
            }
        }

        let segments = result.segments.map { seg in
            DiarizationResult.SpeakerSegment(
                speakerLabel: seg.speakerId,
                speakerIndex: speakerIdMap[seg.speakerId] ?? 0,
                startTime: Double(seg.startTimeSeconds),
                endTime: Double(seg.endTimeSeconds)
            )
        }

        return DiarizationResult(segments: segments)
    }

    private func loadAudioSamples(from url: URL) throws -> [Float] {
        do {
            return try AudioConverter().resampleAudioFile(url)
        } catch {
            throw DiarizationError.audioLoadFailed(error.localizedDescription)
        }
    }
}

enum DiarizationError: LocalizedError {
    case modelNotLoaded
    case audioLoadFailed(String? = nil)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Diarization model is not loaded"
        case .audioLoadFailed(let detail):
            if let detail, !detail.isEmpty {
                return "Failed to load audio samples for diarization: \(detail)"
            }
            return "Failed to load audio samples for diarization"
        }
    }
}
