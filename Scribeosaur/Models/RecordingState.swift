import Foundation

struct RecordingInputDevice: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: String
    let name: String
}

enum RecordingCaptureSource: String, Equatable, Sendable {
    case microphone

    var displayName: String {
        switch self {
        case .microphone:
            return "Microphone"
        }
    }
}

enum RecordingWarmupState: String, Equatable, Sendable {
    case idle
    case warming
    case ready
    case failed

    var isPreparing: Bool {
        self == .warming
    }
}

struct RecordingDraftSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var startTime: Double
    var endTime: Double

    init(
        id: UUID = UUID(),
        text: String,
        startTime: Double,
        endTime: Double
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct RecordingCaptureResult: Sendable {
    let audioURL: URL
    let durationSeconds: Double
    let liveText: String
    let draftSegments: [RecordingDraftSegment]
}

struct RecordingSessionState: Equatable {
    enum Phase: String, Equatable {
        case idle
        case armed
        case preflighting
        case recording
        case finalizing
        case failed
    }

    var phase: Phase = .idle
    var captureSource: RecordingCaptureSource = .microphone
    var elapsedSeconds: Double = 0
    var audioLevel: Float = 0
    var selectedInputDeviceID: String?
    var availableInputDevices: [RecordingInputDevice] = []
    var statusMessage: String?
    var warmupState: RecordingWarmupState = .idle
    var warmupMessage: String?
    var finalizationProgress: Double = 0
    var finalizationStep: String?
    var errorMessage: String?

    var showsRecorderPopover: Bool {
        phase == .armed
    }

    var canStartRecording: Bool {
        phase == .armed && !warmupState.isPreparing
    }

    mutating func resetPresentationState(preservingConfigurationFrom previous: RecordingSessionState) {
        self = RecordingSessionState()
        selectedInputDeviceID = previous.selectedInputDeviceID
        availableInputDevices = previous.availableInputDevices
        warmupState = previous.warmupState
        warmupMessage = previous.warmupMessage
        captureSource = previous.captureSource
    }
}
