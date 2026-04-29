import Foundation
import GRDB

struct TranscriptContextCache: Codable, Identifiable, Equatable {
    enum Status: String, Codable, DatabaseValueConvertible, Sendable {
        case preparing
        case ready
        case failed
    }

    var id: Int64?
    var transcriptId: Int64
    var contentHash: String
    var status: Status
    var normalizedText: String
    var memorySummary: String
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date
}

extension TranscriptContextCache: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcriptContextCache"

    static let transcript = belongsTo(Transcript.self)
    static let chunks = hasMany(TranscriptContextChunk.self)

    var chunks: QueryInterfaceRequest<TranscriptContextChunk> {
        request(for: TranscriptContextCache.chunks).order(Column("sortOrder"))
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
