import Foundation
import GRDB

struct TranscriptMarkdownFile: Codable, Identifiable, Equatable {
    var id: Int64?
    var transcriptId: Int64
    var title: String
    var fileName: String
    var sourcePrompt: String?
    var legacyAIResultId: Int64?
    var createdAt: Date
    var updatedAt: Date
}

extension TranscriptMarkdownFile: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcriptMarkdownFile"

    static let transcript = belongsTo(Transcript.self)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
