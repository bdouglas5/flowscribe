import AVFoundation
import CoreAudio
import Foundation
@preconcurrency import FluidAudio

enum LiveTranscriptionError: LocalizedError {
    case permissionDenied
    case alreadyRecording
    case notRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access is required to start a recording."
        case .alreadyRecording:
            return "A recording is already in progress."
        case .notRecording:
            return "There is no active recording."
        }
    }
}

struct LiveRecordingEvent: Sendable {
    enum Payload: Sendable {
        case devicesUpdated([RecordingInputDevice], selectedID: String?)
        case warmupStatusChanged(RecordingWarmupState, message: String?)
        case statusChanged(String)
        case levelChanged(Float)
        case elapsedChanged(Double)
        case recordingStarted(selectedDeviceID: String?)
    }

    let sessionID: UUID?
    let payload: Payload

    func applies(to activeSessionID: UUID?) -> Bool {
        guard let sessionID else { return true }
        return sessionID == activeSessionID
    }
}

actor LiveTranscriptionService {
    private let transcriptionService: TranscriptionService
    private let audioEngine = AVAudioEngine()
    private let audioConverter = AudioConverter()

    private var eventHandler: (@MainActor @Sendable (LiveRecordingEvent) -> Void)?
    private var masterAudioFile: AVAudioFile?
    private var masterAudioURL: URL?
    private var startDate: Date?
    private var isRecording = false
    private var currentMode: AppSettings.RecordingLiveMode = .automatic
    private var currentCaptureSource: RecordingCaptureSource = .microphone
    private var currentSessionID: UUID?

    private var vadManager: VadManager?
    private var vadState = VadStreamState.initial()
    private var vadSamples: [Float] = []
    private var currentSilenceDuration = 0.0

    private var streamingManager: StreamingEouAsrManager?
    private var chunkPlanner = RecordingChunkPlanner()
    private var chunkSamples: [Float] = []
    private var chunkStartTime: Double?

    private var committedText = ""
    private var partialText = ""
    private var draftSegments: [RecordingDraftSegment] = []

    private var warmupState: RecordingWarmupState = .idle
    private var warmupMessage: String?

    init(transcriptionService: TranscriptionService) {
        self.transcriptionService = transcriptionService
    }

    func setEventHandler(_ handler: @escaping @MainActor @Sendable (LiveRecordingEvent) -> Void) {
        eventHandler = handler
    }

    @discardableResult
    func armRecorder(
        preferredInputDeviceID: String?,
        mode: AppSettings.RecordingLiveMode,
        captureSource: RecordingCaptureSource = .microphone
    ) async -> String? {
        currentMode = mode.resolvedRecorderMode
        currentCaptureSource = captureSource

        let devices = AudioInputDeviceManager.inputDevices()
        let selectedID = resolvedSelectedInputDeviceID(
            preferredID: preferredInputDeviceID,
            devices: devices
        )
        await emit(.devicesUpdated(devices, selectedID: selectedID))

        if !isWarmEnough(for: currentMode, captureSource: captureSource) {
            Task {
                await self.prewarmRecordingModels(for: mode, captureSource: captureSource)
            }
        } else {
            await updateWarmupState(.ready, message: "Recorder ready")
        }

        return selectedID
    }

    func refreshInputDevices(preferredID: String?) async -> [RecordingInputDevice] {
        let devices = AudioInputDeviceManager.inputDevices()
        let selectedID = resolvedSelectedInputDeviceID(
            preferredID: preferredID,
            devices: devices
        )
        await emit(.devicesUpdated(devices, selectedID: selectedID))
        return devices
    }

    func prewarmRecordingModels(
        for mode: AppSettings.RecordingLiveMode,
        captureSource: RecordingCaptureSource = .microphone
    ) async {
        let resolvedMode = mode.resolvedRecorderMode
        currentCaptureSource = captureSource

        guard captureSource == .microphone else {
            await updateWarmupState(.idle, message: nil)
            return
        }

        if isWarmEnough(for: resolvedMode, captureSource: captureSource) {
            await updateWarmupState(.ready, message: "Recorder ready")
            return
        }

        await updateWarmupState(.warming, message: "Preparing recorder…")

        do {
            try await ensureVadLoaded()
            if resolvedMode.requiresStreamingWarmup {
                try await ensureStreamingLoaded()
            }
            await updateWarmupState(.ready, message: "Recorder ready")
        } catch {
            await updateWarmupState(.failed, message: error.localizedDescription)
        }
    }

    func startRecording(
        sessionID: UUID,
        preferredInputDeviceID: String?,
        mode: AppSettings.RecordingLiveMode,
        captureSource: RecordingCaptureSource = .microphone
    ) async throws -> String? {
        guard !isRecording else {
            throw LiveTranscriptionError.alreadyRecording
        }

        guard captureSource == .microphone else {
            throw LiveTranscriptionError.permissionDenied
        }

        guard await requestMicrophonePermissionIfNeeded() else {
            throw LiveTranscriptionError.permissionDenied
        }

        currentSessionID = sessionID
        currentMode = mode.resolvedRecorderMode
        currentCaptureSource = captureSource
        resetTransientState()

        await emit(.statusChanged("Preparing microphone…"), sessionID: sessionID)

        _ = await armRecorder(
            preferredInputDeviceID: preferredInputDeviceID,
            mode: mode,
            captureSource: captureSource
        )

        try await ensureVadLoaded(sessionID: sessionID)
        if currentMode.requiresStreamingWarmup {
            try await ensureStreamingLoaded(sessionID: sessionID)
        }

        let selectedDeviceID = try AudioInputDeviceManager.applyInputDevice(
            id: preferredInputDeviceID,
            to: audioEngine
        )

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let audioURL = StoragePaths.temp.appendingPathComponent("recording-\(UUID().uuidString).caf")
        masterAudioURL = audioURL
        masterAudioFile = try AVAudioFile(forWriting: audioURL, settings: inputFormat.settings)

        if let streamingManager, currentMode.requiresStreamingWarmup {
            let activeSessionID = sessionID
            await streamingManager.setPartialCallback { [weak self] transcript in
                guard let self else { return }
                Task {
                    await self.handleStreamingPartial(
                        fullTranscript: transcript,
                        sessionID: activeSessionID
                    )
                }
            }
            await streamingManager.setEouCallback { [weak self] transcript in
                guard let self else { return }
                Task {
                    await self.commitStreamingTranscript(
                        fullTranscript: transcript,
                        endTime: await self.elapsedSeconds(),
                        sessionID: activeSessionID
                    )
                }
            }
        }

        let activeSessionID = sessionID
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let copy = buffer.deepCopy() else { return }
            Task {
                await self.handleAudioBuffer(copy, sessionID: activeSessionID)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        startDate = Date()
        isRecording = true
        await emit(.statusChanged("Recording"), sessionID: sessionID)
        await emit(.recordingStarted(selectedDeviceID: selectedDeviceID), sessionID: sessionID)

        return selectedDeviceID
    }

    func stopRecording() async throws -> RecordingCaptureResult {
        guard isRecording, let sessionID = currentSessionID else {
            throw LiveTranscriptionError.notRecording
        }

        isRecording = false
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        let finalElapsed = elapsedSeconds()

        if currentMode.requiresStreamingWarmup, let streamingManager {
            let transcript = try await streamingManager.finish()
            await commitStreamingTranscript(
                fullTranscript: transcript,
                endTime: finalElapsed,
                sessionID: sessionID
            )
            await streamingManager.reset()
        } else {
            try await flushChunkIfNeeded(at: finalElapsed, force: true)
        }

        guard let audioURL = masterAudioURL else {
            clearAfterStop()
            throw LiveTranscriptionError.notRecording
        }

        let captureResult = RecordingCaptureResult(
            audioURL: audioURL,
            durationSeconds: finalElapsed,
            liveText: committedText,
            draftSegments: draftSegments
        )

        clearAfterStop()
        return captureResult
    }

    private func requestMicrophonePermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func ensureVadLoaded(sessionID: UUID? = nil) async throws {
        if vadManager != nil {
            return
        }

        if let sessionID {
            await emit(.statusChanged("Loading voice activity detection…"), sessionID: sessionID)
        }

        vadManager = try await VadManager()
    }

    private func ensureStreamingLoaded(sessionID: UUID? = nil) async throws {
        if streamingManager != nil {
            return
        }

        if let sessionID {
            await emit(.statusChanged("Loading streaming transcription…"), sessionID: sessionID)
        }

        let manager = StreamingEouAsrManager(chunkSize: .ms320, eouDebounceMs: 1280)
        try await manager.loadModelsFromHuggingFace(
            to: StoragePaths.models.appendingPathComponent("parakeet-eou-streaming", isDirectory: true)
        )
        streamingManager = manager
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, sessionID: UUID) async {
        guard isRecording, sessionID == currentSessionID else { return }

        do {
            try masterAudioFile?.write(from: buffer)

            let samples = try audioConverter.resampleBuffer(buffer)
            let durationSeconds = Double(samples.count) / Double(VadManager.sampleRate)

            await updateElapsedAndLevel(from: samples, sessionID: sessionID)
            try await updateVadState(with: samples, durationSeconds: durationSeconds)

            switch currentMode {
            case .automatic, .streamingEnglish:
                _ = try await streamingManager?.process(audioBuffer: buffer)
            case .chunkedMultilingual:
                try await appendChunkedSamples(samples)
            }
        } catch {
            await emit(.statusChanged(error.localizedDescription), sessionID: sessionID)
        }
    }

    private func updateElapsedAndLevel(from samples: [Float], sessionID: UUID) async {
        let elapsed = elapsedSeconds()
        let power = samples.isEmpty ? 0 : sqrt(samples.reduce(0) { $0 + ($1 * $1) } / Float(samples.count))

        await emit(.elapsedChanged(elapsed), sessionID: sessionID)
        await emit(.levelChanged(min(max(power * 3.2, 0), 1)), sessionID: sessionID)
    }

    private func updateVadState(with samples: [Float], durationSeconds: Double) async throws {
        guard let vadManager else { return }

        vadSamples.append(contentsOf: samples)

        while vadSamples.count >= VadManager.chunkSize {
            let chunk = Array(vadSamples.prefix(VadManager.chunkSize))
            vadSamples.removeFirst(VadManager.chunkSize)

            let result = try await vadManager.processStreamingChunk(
                chunk,
                state: vadState,
                returnSeconds: true,
                timeResolution: 2
            )
            vadState = result.state
        }

        if vadState.triggered {
            currentSilenceDuration = 0
        } else {
            currentSilenceDuration += durationSeconds
        }
    }

    private func appendChunkedSamples(_ samples: [Float]) async throws {
        let elapsed = elapsedSeconds()

        if chunkStartTime == nil {
            chunkStartTime = max(0, elapsed - (Double(samples.count) / Double(VadManager.sampleRate)))
        }

        if vadState.triggered {
            chunkPlanner.registerVoiceActivity(at: elapsed)
        }

        chunkSamples.append(contentsOf: samples)

        let currentChunkDuration = Double(chunkSamples.count) / Double(VadManager.sampleRate)
        let shouldFlush = chunkPlanner.shouldFlushChunk(
            at: elapsed,
            speechActive: vadState.triggered,
            currentChunkDuration: currentChunkDuration,
            currentSilenceDuration: currentSilenceDuration
        )

        if shouldFlush {
            try await flushChunkIfNeeded(at: elapsed, force: true)
        }
    }

    private func flushChunkIfNeeded(at endTime: Double, force: Bool) async throws {
        guard !chunkSamples.isEmpty else { return }

        let duration = Double(chunkSamples.count) / Double(VadManager.sampleRate)
        if !force, duration < 1.0 {
            return
        }

        let samples = chunkSamples
        let startTime = chunkStartTime ?? max(0, endTime - duration)
        chunkSamples = []
        chunkStartTime = nil
        currentSilenceDuration = 0

        let result = try await transcriptionService.transcribe(samples: samples, durationSeconds: duration)
        let segmentText = result.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segmentText.isEmpty else { return }

        let segment = RecordingDraftSegment(
            text: segmentText,
            startTime: startTime,
            endTime: max(startTime, endTime)
        )
        appendCommittedSegment(segment)
    }

    private func handleStreamingPartial(fullTranscript: String, sessionID: UUID) async {
        guard isRecording, sessionID == currentSessionID else { return }
        partialText = unresolvedStreamingSuffix(for: fullTranscript)
    }

    private func commitStreamingTranscript(
        fullTranscript: String,
        endTime: Double,
        sessionID: UUID
    ) async {
        guard sessionID == currentSessionID else { return }

        let delta = unresolvedStreamingSuffix(for: fullTranscript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !delta.isEmpty else {
            partialText = ""
            return
        }

        let startTime = draftSegments.last?.endTime ?? 0
        let segment = RecordingDraftSegment(
            text: delta,
            startTime: startTime,
            endTime: max(startTime, endTime)
        )
        appendCommittedSegment(segment)
        partialText = ""
    }

    private func unresolvedStreamingSuffix(for fullTranscript: String) -> String {
        guard !committedText.isEmpty else { return fullTranscript }
        if fullTranscript.hasPrefix(committedText) {
            return String(fullTranscript.dropFirst(committedText.count))
        }
        return fullTranscript
    }

    private func appendCommittedSegment(_ segment: RecordingDraftSegment) {
        draftSegments.append(segment)
        committedText = joinedText(existing: committedText, next: segment.text)
    }

    private func joinedText(existing: String, next: String) -> String {
        let trimmedNext = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNext.isEmpty else { return existing }
        guard !existing.isEmpty else { return trimmedNext }

        if let first = trimmedNext.first, [".", ",", "!", "?", ";", ":"].contains(first) {
            return existing + trimmedNext
        }

        if existing.hasSuffix("\n\n") {
            return existing + trimmedNext
        }

        return existing + "\n\n" + trimmedNext
    }

    private func resolvedSelectedInputDeviceID(
        preferredID: String?,
        devices: [RecordingInputDevice]
    ) -> String? {
        if devices.contains(where: { $0.id == preferredID }) {
            return preferredID
        }
        return AudioInputDeviceManager.defaultInputDeviceID()
    }

    private func isWarmEnough(
        for mode: AppSettings.RecordingLiveMode,
        captureSource: RecordingCaptureSource
    ) -> Bool {
        guard captureSource == .microphone, vadManager != nil else {
            return false
        }

        if mode.requiresStreamingWarmup {
            return streamingManager != nil
        }

        return true
    }

    private func resetTransientState() {
        committedText = ""
        partialText = ""
        draftSegments = []
        chunkSamples = []
        chunkStartTime = nil
        chunkPlanner.reset()
        vadSamples = []
        vadState = .initial()
        currentSilenceDuration = 0
    }

    private func clearAfterStop() {
        masterAudioFile = nil
        masterAudioURL = nil
        startDate = nil
        currentSessionID = nil
        resetTransientState()
    }

    private func elapsedSeconds() -> Double {
        guard let startDate else { return 0 }
        return Date().timeIntervalSince(startDate)
    }

    private func updateWarmupState(
        _ state: RecordingWarmupState,
        message: String?
    ) async {
        warmupState = state
        warmupMessage = message
        await emit(.warmupStatusChanged(state, message: message))
    }

    private func emit(
        _ payload: LiveRecordingEvent.Payload,
        sessionID: UUID? = nil
    ) async {
        guard let eventHandler else { return }
        await MainActor.run {
            eventHandler(
                LiveRecordingEvent(
                    sessionID: sessionID,
                    payload: payload
                )
            )
        }
    }
}

private extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        ) else {
            return nil
        }

        copy.frameLength = frameLength

        let sourcePointer = UnsafeMutablePointer(mutating: audioBufferList)
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(sourcePointer)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)

        for index in 0..<min(sourceBuffers.count, destinationBuffers.count) {
            let source = sourceBuffers[index]
            guard
                let sourceData = source.mData,
                let destinationData = destinationBuffers[index].mData
            else { continue }

            memcpy(destinationData, sourceData, Int(source.mDataByteSize))
            destinationBuffers[index].mDataByteSize = source.mDataByteSize
        }

        return copy
    }
}
