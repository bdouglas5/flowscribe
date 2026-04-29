import Foundation

final class AudioPipelineService {
    private let transcriptionService: TranscriptionService
    private let diarizationService: DiarizationService
    private let repository: TranscriptRepository
    private let settings: AppSettings
    private let spotifyPodcastService: SpotifyPodcastService?

    init(transcriptionService: TranscriptionService,
         diarizationService: DiarizationService,
         repository: TranscriptRepository,
         settings: AppSettings,
         spotifyPodcastService: SpotifyPodcastService? = nil) {
        self.transcriptionService = transcriptionService
        self.diarizationService = diarizationService
        self.repository = repository
        self.settings = settings
        self.spotifyPodcastService = spotifyPodcastService
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

                let downloadResult: (audioFile: URL, title: String)

                if item.remoteSource == .spotify, let metadata = item.spotifyMetadata,
                   let spotifyService = spotifyPodcastService {
                    downloadResult = try await spotifyService.downloadAudio(
                        episodeName: metadata.showName.isEmpty ? item.title : item.title,
                        showName: metadata.showName,
                        showID: metadata.showID,
                        publisherName: metadata.publisherName,
                        durationSeconds: Double(metadata.episodeDurationMs) / 1000.0
                    ) { fraction in
                        Task { @MainActor in
                            item.progress = max(item.progress, fraction * 0.5)
                        }
                    }
                } else if item.remoteSource == .spotify {
                    throw PipelineError.unsupportedSource
                } else {
                    downloadResult = try await YTDLPService.downloadAudio(for: item) { fraction, speed in
                        Task { @MainActor in
                            item.progress = max(item.progress, fraction * 0.5)
                            item.downloadSpeed = speed
                        }
                    }
                }

                await MainActor.run {
                    item.downloadSpeed = nil
                    item.progress = 0.5
                }
                audioURL = downloadResult.audioFile
                title = downloadResult.title
                await MainActor.run {
                    item.title = downloadResult.title
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
                thumbnailURL: item.thumbnailURL,
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

            let isRemote = item.sourceType == .url
            await MainActor.run { item.progress = isRemote ? 0.9 : 0.8 }

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

                    await MainActor.run { item.progress = isRemote ? 0.95 : 0.9 }

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

    func finalizeRecording(
        title: String,
        audioURL: URL,
        liveText: String,
        liveSegments: [RecordingDraftSegment],
        speakerDetection: Bool,
        speakerNames: [String],
        runFinalPass: Bool,
        progressHandler: @escaping @Sendable (String, Double) -> Void = { _, _ in }
    ) async throws -> Int64 {
        AppLogger.info("Recording", "Finalizing recording '\(title)'")

        if runFinalPass {
            try await transcriptionService.ensureModelLoaded()
        }

        progressHandler("Creating transcript record…", 0.05)

        var transcript = Transcript(
            title: title,
            sourceType: .recording,
            sourcePath: "",
            remoteSource: nil,
            createdAt: Date(),
            speakerDetection: speakerDetection && runFinalPass,
            speakerCount: speakerDetection ? max(1, speakerNames.count) : 0,
            fullText: "",
            status: .processing
        )
        try repository.save(&transcript, segments: [])
        guard let transcriptID = transcript.id else {
            throw PipelineError.databaseError
        }

        do {
            let segments: [TranscriptSegment]
            let fullText: String
            let duration: Double
            let resolvedSpeakerCount: Int

            if runFinalPass {
                progressHandler("Running final transcription…", 0.25)
                let asrResult = try await transcriptionService.transcribe(audioURL: audioURL)

                if speakerDetection {
                    progressHandler("Running speaker diarization…", 0.65)
                    let diarization = try await buildDiarizedSegments(
                        transcriptID: transcriptID,
                        audioURL: audioURL,
                        asrSegments: asrResult.segments,
                        preferredSpeakerNames: speakerNames
                    )
                    segments = diarization.segments
                    resolvedSpeakerCount = diarization.speakerCount
                } else {
                    segments = asrResult.segments.enumerated().map { index, segment in
                        TranscriptSegment(
                            transcriptId: transcriptID,
                            text: segment.text,
                            startTime: segment.startTime,
                            endTime: segment.endTime,
                            sortOrder: index
                        )
                    }
                    resolvedSpeakerCount = 0
                }

                fullText = buildFullText(segments: segments)
                duration = resolvedDuration(
                    preferredDuration: asrResult.durationSeconds,
                    segments: segments
                )
            } else {
                progressHandler("Saving live transcript…", 0.55)
                segments = buildLiveSegments(
                    transcriptID: transcriptID,
                    liveSegments: liveSegments,
                    speakerDetection: speakerDetection,
                    preferredSpeakerNames: speakerNames
                )
                fullText = buildFullText(segments: segments)
                duration = max(
                    liveSegments.map(\.endTime).max() ?? 0,
                    (try? await FFmpegService.audioDuration(of: audioURL)) ?? 0
                )
                resolvedSpeakerCount = speakerDetection ? max(1, speakerNames.count) : 0
            }

            try repository.saveSegments(segments)
            try repository.updateStatus(
                transcriptID,
                status: .completed,
                fullText: fullText.isEmpty ? liveText : fullText,
                durationSeconds: duration,
                speakerCount: resolvedSpeakerCount
            )

            transcript.fullText = fullText.isEmpty ? liveText : fullText
            transcript.durationSeconds = duration
            transcript.status = .completed
            transcript.speakerCount = resolvedSpeakerCount

            progressHandler("Managing recording file…", 0.9)
            let persistedAudioURL = try await persistRecordingAudio(audioURL, title: title)
            try repository.updateSourcePath(transcriptID, sourcePath: persistedAudioURL?.path ?? "")

            if settings.autoExportEnabled, let exportURL = settings.autoExportURL {
                do {
                    try ExportService.autoExport(
                        transcript: transcript,
                        segments: segments,
                        to: exportURL,
                        showTimestamps: settings.showTimestamps
                    )
                } catch {
                    AppLogger.error("Recording", "Auto-export failed: \(error.localizedDescription)")
                }
            }

            progressHandler("Recording saved", 1.0)
            return transcriptID
        } catch {
            try? repository.updateStatus(
                transcriptID,
                status: .failed,
                errorMessage: error.localizedDescription
            )
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

    private func buildLiveSegments(
        transcriptID: Int64,
        liveSegments: [RecordingDraftSegment],
        speakerDetection: Bool,
        preferredSpeakerNames: [String]
    ) -> [TranscriptSegment] {
        let defaultNames = defaultSpeakerNames(
            preferred: preferredSpeakerNames,
            minimumCount: speakerDetection ? 1 : 0
        )

        return liveSegments.enumerated().map { index, segment in
            TranscriptSegment(
                transcriptId: transcriptID,
                speakerId: speakerDetection ? 0 : nil,
                speakerName: speakerDetection ? defaultNames.first : nil,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                sortOrder: index
            )
        }
    }

    private func buildDiarizedSegments(
        transcriptID: Int64,
        audioURL: URL,
        asrSegments: [TranscriptionService.TranscriptionResult.Segment],
        preferredSpeakerNames: [String]
    ) async throws -> (segments: [TranscriptSegment], speakerCount: Int) {
        if !diarizationService.isModelLoaded {
            try await diarizationService.loadModel()
        }

        let diarization = try await diarizationService.diarize(
            audioURL: audioURL,
            speakerCount: preferredSpeakerNames.count
        )
        let names = speakerNames(for: diarization, preferred: preferredSpeakerNames)

        let segments: [TranscriptSegment] = diarization.segments.enumerated().compactMap { entry in
            let (index, segment) = entry
            let matchingText = asrSegments
                .filter { overlaps(start: segment.startTime, end: segment.endTime, with: $0.startTime, and: $0.endTime) }
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !matchingText.isEmpty else { return nil }

            return TranscriptSegment(
                transcriptId: transcriptID,
                speakerId: segment.speakerIndex,
                speakerName: segment.speakerIndex < names.count ? names[segment.speakerIndex] : "Speaker \(segment.speakerIndex + 1)",
                text: matchingText,
                startTime: segment.startTime,
                endTime: segment.endTime,
                sortOrder: index
            )
        }

        return (segments, names.count)
    }

    private func persistRecordingAudio(_ sourceURL: URL, title: String) async throws -> URL? {
        let fm = FileManager.default

        guard settings.recordingKeepOriginalAudio else {
            cleanupTempFile(sourceURL, originalURL: nil)
            return nil
        }

        let baseDirectory = settings.recordingAudioURL ?? StoragePaths.recordings
        if !fm.fileExists(atPath: baseDirectory.path) {
            try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }

        let sanitizedTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitizedTitle.isEmpty ? "Recording" : sanitizedTitle

        let destinationURL: URL
        if settings.recordingAudioQuality == .speechOptimized {
            let wavURL = try await FFmpegService.convertToWAV(input: sourceURL)
            destinationURL = uniqueDestinationURL(
                in: baseDirectory,
                baseName: baseName,
                extension: "wav"
            )
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: wavURL, to: destinationURL)
            cleanupTempFile(sourceURL, originalURL: nil)
        } else {
            let ext = sourceURL.pathExtension.isEmpty ? "caf" : sourceURL.pathExtension
            destinationURL = uniqueDestinationURL(
                in: baseDirectory,
                baseName: baseName,
                extension: ext
            )
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: sourceURL, to: destinationURL)
        }

        return destinationURL
    }

    private func uniqueDestinationURL(
        in directory: URL,
        baseName: String,
        extension ext: String
    ) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var suffix = 2

        while fm.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension(ext)
            suffix += 1
        }

        return candidate
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
    case unsupportedSource

    var errorDescription: String? {
        switch self {
        case .databaseError: "Failed to create transcript record"
        case .unsupportedSource: "Unsupported audio source"
        }
    }
}
