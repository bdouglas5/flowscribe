import Foundation
import GRDB

struct TranscriptChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable, DatabaseValueConvertible, Sendable {
        case user
        case assistant
    }

    var id: Int64?
    var transcriptId: Int64
    var role: Role
    var content: String
    var createdAt: Date
}

extension TranscriptChatMessage: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcriptChatMessage"

    static let transcript = belongsTo(Transcript.self)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
