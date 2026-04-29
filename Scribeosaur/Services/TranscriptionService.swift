import Foundation
@preconcurrency import FluidAudio

@Observable
final class TranscriptionService {
    var isModelLoaded = false
    var modelLoadProgress: Double = 0.0

    private var asrManager: AsrManager?
    private var modelLoadingTask: Task<Void, Error>?

    func loadModel() async throws {
        guard !isModelLoaded, asrManager == nil else { return }
        if let modelLoadingTask {
            try await modelLoadingTask.value
            return
        }

        let task = Task { @MainActor in
            modelLoadProgress = 0.1

            let models = try await AsrModels.downloadAndLoad(version: .v3)

            modelLoadProgress = 0.5

            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)

            self.asrManager = manager
            self.isModelLoaded = true
            self.modelLoadProgress = 1.0
        }
        modelLoadingTask = task

        do {
            try await task.value
        } catch {
            await MainActor.run {
                self.modelLoadProgress = 0
            }
            modelLoadingTask = nil
            throw error
        }

        modelLoadingTask = nil
    }

    func ensureModelLoaded() async throws {
        if isModelLoaded, asrManager != nil {
            return
        }
        try await loadModel()
    }

    struct TranscriptionResult {
        let segments: [Segment]
        let fullText: String
        let durationSeconds: Double
        let tokenTimings: [TokenTiming]

        struct Segment {
            let text: String
            let startTime: Double
            let endTime: Double
        }
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        try await ensureModelLoaded()
        guard let asrManager else { throw TranscriptionError.modelNotLoaded }

        try await asrManager.resetDecoderState(for: .system)
        let result = try await asrManager.transcribe(audioURL, source: .system)
        let duration = (try? await FFmpegService.audioDuration(of: audioURL)) ?? 0
        let tokenTimings = result.tokenTimings ?? []
        let transcriptSegments = buildSegments(from: tokenTimings, fallbackText: result.text, duration: duration)

        return TranscriptionResult(
            segments: transcriptSegments,
            fullText: result.text,
            durationSeconds: duration,
            tokenTimings: tokenTimings
        )
    }

    func transcribe(samples: [Float], durationSeconds: Double) async throws -> TranscriptionResult {
        try await ensureModelLoaded()
        guard let asrManager else { throw TranscriptionError.modelNotLoaded }

        try await asrManager.resetDecoderState(for: .system)
        let result = try await asrManager.transcribe(samples, source: .system)
        let tokenTimings = result.tokenTimings ?? []
        let transcriptSegments = buildSegments(
            from: tokenTimings,
            fallbackText: result.text,
            duration: durationSeconds
        )

        return TranscriptionResult(
            segments: transcriptSegments,
            fullText: result.text,
            durationSeconds: durationSeconds,
            tokenTimings: tokenTimings
        )
    }

    private func buildSegments(
        from tokenTimings: [TokenTiming],
        fallbackText: String,
        duration: Double
    ) -> [TranscriptionResult.Segment] {
        let words = buildWordTimings(from: tokenTimings)
        guard !words.isEmpty else {
            return [
                TranscriptionResult.Segment(
                    text: fallbackText,
                    startTime: 0,
                    endTime: duration
                )
            ]
        }

        var segments: [TranscriptionResult.Segment] = []
        var currentWords: [WordTiming] = []

        func flushCurrentWords() {
            guard
                let first = currentWords.first,
                let last = currentWords.last
            else { return }

            let text = render(words: currentWords)
            guard !text.isEmpty else {
                currentWords.removeAll()
                return
            }

            segments.append(
                TranscriptionResult.Segment(
                    text: text,
                    startTime: first.startTime,
                    endTime: last.endTime
                )
            )
            currentWords.removeAll()
        }

        for word in words {
            if let previous = currentWords.last {
                let gap = word.startTime - previous.endTime
                let currentText = render(words: currentWords)
                let shouldBreak = gap > 1.0
                    || (currentText.last.map(isSentenceBoundary) == true && currentWords.count >= 8)
                    || currentWords.count >= 20

                if shouldBreak {
                    flushCurrentWords()
                }
            }

            currentWords.append(word)
        }

        flushCurrentWords()
        return segments
    }

    private func buildWordTimings(from tokenTimings: [TokenTiming]) -> [WordTiming] {
        guard !tokenTimings.isEmpty else { return [] }

        var words: [WordTiming] = []
        var currentText = ""
        var currentStart: Double?
        var currentEnd = 0.0

        func flushCurrentWord() {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let startTime = currentStart else {
                currentText = ""
                currentStart = nil
                return
            }

            words.append(
                WordTiming(
                    text: trimmed,
                    startTime: startTime,
                    endTime: currentEnd
                )
            )

            currentText = ""
            currentStart = nil
        }

        for token in tokenTimings {
            let tokenText = token.token
            let startsNewWord = tokenText.hasPrefix(" ")
            let trimmedToken = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)

            if startsNewWord && !currentText.isEmpty {
                flushCurrentWord()
            }

            if currentStart == nil {
                currentStart = token.startTime
            }

            currentEnd = token.endTime
            currentText += tokenText

            if !trimmedToken.isEmpty, isTerminalPunctuation(in: trimmedToken) {
                flushCurrentWord()
            }
        }

        flushCurrentWord()
        return words
    }

    private func render(words: [WordTiming]) -> String {
        words.reduce(into: "") { partialResult, word in
            if partialResult.isEmpty {
                partialResult = word.text
            } else if isStandalonePunctuation(word.text) {
                partialResult += word.text
            } else {
                partialResult += " " + word.text
            }
        }
    }

    private func isTerminalPunctuation(in text: String) -> Bool {
        guard let last = text.last else { return false }
        return isSentenceBoundary(last) || [",", ";", ":"].contains(last)
    }

    private func isStandalonePunctuation(_ text: String) -> Bool {
        let punctuation = CharacterSet.punctuationCharacters
        return !text.isEmpty && text.unicodeScalars.allSatisfy { punctuation.contains($0) }
    }

    private func isSentenceBoundary(_ character: Character) -> Bool {
        [".", "!", "?"].contains(character)
    }
}

private extension TranscriptionService {
    struct WordTiming {
        let text: String
        let startTime: Double
        let endTime: Double
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "Transcription model is not loaded"
        }
    }
}
