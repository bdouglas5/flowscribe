import Foundation
import GRDB

struct TranscriptSegment: Codable, Identifiable, Equatable {
    var id: Int64?
    var transcriptId: Int64
    var speakerId: Int?
    var speakerName: String?
    var text: String
    var startTime: Double
    var endTime: Double
    var sortOrder: Int
}

extension TranscriptSegment: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcriptSegment"

    static let transcript = belongsTo(Transcript.self)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
