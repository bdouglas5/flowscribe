import Foundation

@Observable
final class QueueItem: Identifiable {
    let id = UUID()
    var title: String
    let sourceURL: URL?
    let sourceType: Transcript.SourceType
    let remoteSource: Transcript.RemoteSource?
    let collectionID: String?
    let collectionTitle: String?
    let collectionType: Transcript.CollectionType?
    let collectionItemIndex: Int?
    var status: Status = .waiting
    var progress: Double = 0.0
    var downloadSpeed: String?
    var errorMessage: String?
    var speakerNames: [String] = []
    var speakerDetection: Bool = false
    var resultTranscriptId: Int64?
    var thumbnailURL: String?
    var spotifyMetadata: SpotifyQueueMetadata?

    enum Status: String {
        case waiting
        case resolving
        case downloading
        case converting
        case transcribing
        case diarizing
        case completed
        case failed
    }

    var statusLabel: String {
        switch status {
        case .waiting: "Waiting"
        case .resolving: "Resolving"
        case .downloading: "Downloading"
        case .converting: "Converting"
        case .transcribing: "Transcribing"
        case .diarizing: "Diarizing"
        case .completed: "Done"
        case .failed: "Error"
        }
    }

    var isProcessing: Bool {
        switch status {
        case .resolving, .downloading, .converting, .transcribing, .diarizing: true
        default: false
        }
    }

    var isCancellable: Bool {
        status == .waiting || status == .resolving
    }

    init(title: String, sourceURL: URL?, sourceType: Transcript.SourceType,
         remoteSource: Transcript.RemoteSource? = nil,
         collectionID: String? = nil,
         collectionTitle: String? = nil,
         collectionType: Transcript.CollectionType? = nil,
         collectionItemIndex: Int? = nil,
         thumbnailURL: String? = nil,
         speakerDetection: Bool = false, speakerNames: [String] = []) {
        self.title = title
        self.sourceURL = sourceURL
        self.sourceType = sourceType
        self.remoteSource = remoteSource
        self.collectionID = collectionID
        self.collectionTitle = collectionTitle
        self.collectionType = collectionType
        self.collectionItemIndex = collectionItemIndex
        self.thumbnailURL = thumbnailURL
        self.speakerDetection = speakerDetection
        self.speakerNames = speakerNames
    }
}
