import Foundation
import GRDB

struct TranscriptAIResult: Codable, Identifiable, Equatable {
    var id: Int64?
    var transcriptId: Int64
    var promptID: String
    var promptTitle: String
    var promptBody: String
    var content: String
    var createdAt: Date
}

extension TranscriptAIResult: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcriptAIResult"

    static let transcript = belongsTo(Transcript.self)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
