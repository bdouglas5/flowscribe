import Foundation
import GRDB

struct TranscriptContextChunk: Codable, Identifiable, Equatable {
    var id: Int64?
    var cacheId: Int64
    var transcriptId: Int64
    var sortOrder: Int
    var content: String
    var summary: String
    var createdAt: Date
}

extension TranscriptContextChunk: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcriptContextChunk"

    static let cache = belongsTo(TranscriptContextCache.self)
    static let transcript = belongsTo(Transcript.self)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
