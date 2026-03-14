import Foundation

final class AudioPipelineService {
    private let transcriptionService: TranscriptionService
    private let diarizationService: DiarizationService
    private let repository: TranscriptRepository
    private let settings: AppSettings

    init(transcriptionService: TranscriptionService,
         diarizationService: DiarizationService,
         repository: TranscriptRepository,
         settings: AppSettings) {
        self.transcriptionService = transcriptionService
        self.diarizationService = diarizationService
        self.repository = repository
        self.settings = settings
    }

    func process(item: QueueItem) async throws -> Int64 {
        AppLogger.info("Pipeline", "Starting pipeline for \(item.title)")
        try await transcriptionService.ensureModelLoaded()

        var transcriptId: Int64?
        var tempAudioURL: URL?

        do {
            // 1. Resolve audio file
            let audioURL: URL
            var title = item.title
            var sourcePath = item.sourceURL?.absoluteString ?? ""

            if item.sourceType == .url {
                await MainActor.run { item.status = .downloading }
                let result = try await YTDLPService.downloadAudio(for: item)
                audioURL = result.audioFile
                title = result.title
                await MainActor.run {
                    item.title = result.title
                }
                AppLogger.info("Pipeline", "Downloaded remote audio for \(title) to \(audioURL.path)")
            } else {
                audioURL = item.sourceURL!
                sourcePath = audioURL.path
            }

            // 2. Convert if needed
            let wavURL: URL
            if FFmpegService.needsConversion(audioURL) {
                await MainActor.run { item.status = .converting }
                wavURL = try await FFmpegService.convertToWAV(input: audioURL)
                AppLogger.info("Pipeline", "Converted audio for \(title) to \(wavURL.path)")
            } else {
                wavURL = audioURL
            }
            tempAudioURL = wavURL

            // 3. Create initial transcript record
            var transcript = Transcript(
                title: title,
                sourceType: item.sourceType,
                sourcePath: sourcePath,
                remoteSource: item.remoteSource,
                createdAt: Date(),
                speakerDetection: item.speakerDetection,
                speakerCount: item.speakerNames.count,
                fullText: "",
                status: .processing,
                collectionID: item.collectionID,
                collectionTitle: item.collectionTitle,
                collectionType: item.collectionType,
                collectionItemIndex: item.collectionItemIndex
            )
            try repository.save(&transcript, segments: [])
            guard let savedTranscriptId = transcript.id else {
                throw PipelineError.databaseError
            }

            transcriptId = savedTranscriptId
            await MainActor.run {
                item.resultTranscriptId = savedTranscriptId
            }
            AppLogger.info("Pipeline", "Created transcript record \(savedTranscriptId) for \(title)")

            // 4. Transcribe
            await MainActor.run { item.status = .transcribing }
            let asrResult = try await transcriptionService.transcribe(audioURL: wavURL)

            await MainActor.run { item.progress = 0.6 }

            // 5. Build segments
            var segments: [TranscriptSegment] = []
            var speakerCount = item.speakerNames.count

            if item.speakerDetection {
                do {
                    if !diarizationService.isModelLoaded {
                        try await diarizationService.loadModel()
                    }
                    await MainActor.run { item.status = .diarizing }
                    let diarResult = try await diarizationService.diarize(
                        audioURL: wavURL,
                        speakerCount: item.speakerNames.count
                    )
                    AppLogger.info("Pipeline", "Diarization succeeded for \(title)")

                    await MainActor.run { item.progress = 0.8 }

                    let speakerNames = speakerNames(for: diarResult, preferred: item.speakerNames)
                    speakerCount = speakerNames.count

                    segments = diarResult.segments.enumerated().compactMap { index, seg in
                        let matchingText = asrResult.segments
                            .filter { overlaps(start: seg.startTime, end: seg.endTime, with: $0.startTime, and: $0.endTime) }
                            .map(\.text)
                            .joined(separator: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !matchingText.isEmpty else { return nil }

                        return TranscriptSegment(
                            transcriptId: savedTranscriptId,
                            speakerId: seg.speakerIndex,
                            speakerName: seg.speakerIndex < speakerNames.count
                                ? speakerNames[seg.speakerIndex]
                                : "Speaker \(seg.speakerIndex + 1)",
                            text: matchingText,
                            startTime: seg.startTime,
                            endTime: seg.endTime,
                            sortOrder: index
                        )
                    }
                } catch {
                    AppLogger.error(
                        "Pipeline",
                        "Diarization failed for \(title). Falling back to ASR-only segments: \(error.localizedDescription)"
                    )
                    let fallbackNames = defaultSpeakerNames(preferred: item.speakerNames, minimumCount: 1)
                    speakerCount = fallbackNames.count
                    segments = asrResult.segments.enumerated().map { index, seg in
                        TranscriptSegment(
                            transcriptId: savedTranscriptId,
                            speakerId: 0,
                            speakerName: fallbackNames.first,
                            text: seg.text,
                            startTime: seg.startTime,
                            endTime: seg.endTime,
                            sortOrder: index
                        )
                    }
                }

                if segments.isEmpty {
                    let fallbackNames = defaultSpeakerNames(preferred: item.speakerNames, minimumCount: 1)
                    speakerCount = fallbackNames.count
                    segments = asrResult.segments.enumerated().map { index, seg in
                        TranscriptSegment(
                            transcriptId: savedTranscriptId,
                            speakerId: 0,
                            speakerName: fallbackNames.first,
                            text: seg.text,
                            startTime: seg.startTime,
                            endTime: seg.endTime,
                            sortOrder: index
                        )
                    }
                }
            } else {
                segments = asrResult.segments.enumerated().map { index, seg in
                    TranscriptSegment(
                        transcriptId: savedTranscriptId,
                        text: seg.text,
                        startTime: seg.startTime,
                        endTime: seg.endTime,
                        sortOrder: index
                    )
                }
            }

            let fullText = buildFullText(segments: segments)
            let resolvedDuration = resolvedDuration(
                preferredDuration: asrResult.durationSeconds,
                segments: segments
            )

            try repository.updateStatus(
                savedTranscriptId,
                status: .completed,
                fullText: fullText.isEmpty ? asrResult.fullText : fullText,
                durationSeconds: resolvedDuration,
                speakerCount: speakerCount
            )
            try repository.saveSegments(segments)

            transcript.durationSeconds = resolvedDuration
            transcript.fullText = fullText.isEmpty ? asrResult.fullText : fullText
            transcript.status = .completed
            transcript.speakerCount = speakerCount

            // Auto-export if enabled
            if settings.autoExportEnabled, let exportURL = settings.autoExportURL {
                do {
                    try ExportService.autoExport(
                        transcript: transcript,
                        segments: segments,
                        to: exportURL,
                        showTimestamps: settings.showTimestamps
                    )
                    AppLogger.info("Pipeline", "Auto-exported transcript to \(exportURL.path)")
                } catch {
                    AppLogger.error("Pipeline", "Auto-export failed: \(error.localizedDescription)")
                }
            }

            await MainActor.run { item.progress = 1.0 }
            cleanupTempFile(wavURL, originalURL: item.sourceURL)
            AppLogger.info("Pipeline", "Completed pipeline for \(title) transcriptId=\(savedTranscriptId)")

            return savedTranscriptId
        } catch {
            if let transcriptId {
                try? repository.updateStatus(
                    transcriptId,
                    status: .failed,
                    errorMessage: error.localizedDescription
                )
            }
            if let tempAudioURL {
                cleanupTempFile(tempAudioURL, originalURL: item.sourceURL)
            }
            AppLogger.error("Pipeline", "Pipeline failed for \(item.title): \(error.localizedDescription)")
            throw error
        }
    }

    private func buildFullText(segments: [TranscriptSegment]) -> String {
        segments.compactMap { seg in
            guard !seg.text.isEmpty else { return nil }
            var line = ""
            if let name = seg.speakerName {
                line += "\(name): "
            }
            line += seg.text
            return line
        }.joined(separator: "\n\n")
    }

    private func defaultSpeakerNames(preferred: [String], minimumCount: Int) -> [String] {
        let count = max(minimumCount, preferred.count)
        return (0..<count).map { index in
            if index < preferred.count, !preferred[index].isEmpty {
                return preferred[index]
            }
            return "Speaker \(index + 1)"
        }
    }

    private func speakerNames(
        for diarization: DiarizationService.DiarizationResult,
        preferred: [String]
    ) -> [String] {
        let count = (diarization.segments.map(\.speakerIndex).max() ?? -1) + 1
        guard count > 0 else { return preferred }

        return (0..<count).map { index in
            if index < preferred.count, !preferred[index].isEmpty {
                return preferred[index]
            }
            return "Speaker \(index + 1)"
        }
    }

    private func overlaps(start lhsStart: Double, end lhsEnd: Double, with rhsStart: Double, and rhsEnd: Double) -> Bool {
        min(lhsEnd, rhsEnd) > max(lhsStart, rhsStart)
    }

    private func resolvedDuration(
        preferredDuration: Double,
        segments: [TranscriptSegment]
    ) -> Double {
        if preferredDuration > 0 {
            return preferredDuration
        }

        return segments.map(\.endTime).max() ?? 0
    }

    private func cleanupTempFile(_ wavURL: URL, originalURL: URL?) {
        let fm = FileManager.default
        if wavURL.path.hasPrefix(StoragePaths.temp.path) {
            try? fm.removeItem(at: wavURL)
        }
    }
}

enum PipelineError: LocalizedError {
    case databaseError

    var errorDescription: String? {
        switch self {
        case .databaseError: "Failed to create transcript record"
        }
    }
}
