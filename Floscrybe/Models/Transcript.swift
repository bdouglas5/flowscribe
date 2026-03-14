import Foundation
import GRDB

struct Transcript: Codable, Identifiable, Equatable {
    var id: Int64?
    var title: String
    var sourceType: SourceType
    var sourcePath: String
    var remoteSource: RemoteSource?
    var createdAt: Date
    var durationSeconds: Double?
    var speakerDetection: Bool
    var speakerCount: Int
    var fullText: String
    var status: TranscriptStatus
    var errorMessage: String?
    var collectionID: String?
    var collectionTitle: String?
    var collectionType: CollectionType?
    var collectionItemIndex: Int?

    enum SourceType: String, Codable, DatabaseValueConvertible {
        case file
        case url
    }

    enum RemoteSource: String, Codable, DatabaseValueConvertible {
        case youtube
        case spotify
    }

    enum CollectionType: String, Codable, DatabaseValueConvertible {
        case playlist
        case channel
    }

    enum TranscriptStatus: String, Codable, DatabaseValueConvertible {
        case processing
        case completed
        case failed
    }
}

extension Transcript: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcript"

    static let segments = hasMany(TranscriptSegment.self)

    var segments: QueryInterfaceRequest<TranscriptSegment> {
        request(for: Transcript.segments).order(Column("sortOrder"))
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
