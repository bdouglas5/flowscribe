import Foundation
import GRDB

final class TranscriptRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Create

    func save(_ transcript: inout Transcript, segments: [TranscriptSegment]) throws {
        try dbQueue.write { db in
            try transcript.insert(db)
            guard let transcriptId = transcript.id else { return }

            for var segment in segments {
                segment.transcriptId = transcriptId
                try segment.insert(db)
            }
        }
    }

    func saveSegments(_ segments: [TranscriptSegment]) throws {
        try dbQueue.write { db in
            for var segment in segments {
                try segment.insert(db)
            }
        }
    }

    func saveAIResult(_ result: inout TranscriptAIResult) throws {
        try dbQueue.write { db in
            if var existing = try TranscriptAIResult
                .filter(Column("transcriptId") == result.transcriptId)
                .filter(Column("promptID") == result.promptID)
                .fetchOne(db) {
                existing.promptTitle = result.promptTitle
                existing.promptBody = result.promptBody
                existing.content = result.content
                existing.createdAt = result.createdAt
                try existing.update(db)
                result = existing
            } else {
                try result.insert(db)
            }
        }
    }

    // MARK: - Read

    func fetchAll() throws -> [Transcript] {
        try dbQueue.read { db in
            try Transcript
                .filter(Column("status") == Transcript.TranscriptStatus.completed.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetch(id: Int64) throws -> Transcript? {
        try dbQueue.read { db in
            try Transcript.fetchOne(db, id: id)
        }
    }

    func fetchSegments(transcriptId: Int64) throws -> [TranscriptSegment] {
        try dbQueue.read { db in
            try TranscriptSegment
                .filter(Column("transcriptId") == transcriptId)
                .order(Column("sortOrder"))
                .fetchAll(db)
        }
    }

    func fetchAIResults(transcriptId: Int64) throws -> [TranscriptAIResult] {
        try dbQueue.read { db in
            try TranscriptAIResult
                .filter(Column("transcriptId") == transcriptId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Update

    func updateStatus(_ id: Int64, status: Transcript.TranscriptStatus,
                      fullText: String? = nil, durationSeconds: Double? = nil,
                      errorMessage: String? = nil,
                      speakerCount: Int? = nil) throws {
        try dbQueue.write { db in
            if var transcript = try Transcript.fetchOne(db, id: id) {
                transcript.status = status
                if let fullText { transcript.fullText = fullText }
                if let durationSeconds { transcript.durationSeconds = durationSeconds }
                if let errorMessage { transcript.errorMessage = errorMessage }
                if let speakerCount { transcript.speakerCount = speakerCount }
                try transcript.update(db)
            }
        }
    }

    // MARK: - Delete

    func delete(id: Int64) throws {
        try dbQueue.write { db in
            _ = try Transcript.deleteOne(db, id: id)
        }
    }

    func deleteAIResult(id: Int64) throws {
        try dbQueue.write { db in
            _ = try TranscriptAIResult.deleteOne(db, id: id)
        }
    }

    func deleteCollection(id: String) throws {
        try dbQueue.write { db in
            _ = try Transcript
                .filter(Column("collectionID") == id)
                .deleteAll(db)
        }
    }

    func deleteAll() throws {
        try dbQueue.write { db in
            _ = try Transcript.deleteAll(db)
        }
    }

    // MARK: - Search

    func search(query: String) throws -> [Transcript] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return try fetchAll()
        }
        return try dbQueue.read { db in
            let pattern = FTS5Pattern(matchingAllPrefixesIn: query)
            let sql = """
                SELECT transcript.*
                FROM transcript
                JOIN transcriptFTS ON transcriptFTS.rowid = transcript.rowid
                WHERE transcriptFTS MATCH ?
                  AND transcript.status = ?
                ORDER BY transcript.createdAt DESC
                """
            return try Transcript.fetchAll(
                db,
                sql: sql,
                arguments: [pattern, Transcript.TranscriptStatus.completed.rawValue]
            )
        }
    }

    // MARK: - Stats

    func totalCount() throws -> Int {
        try dbQueue.read { db in
            try Transcript.fetchCount(db)
        }
    }

    func databaseSize() -> Int64 {
        let path = StoragePaths.databaseFile.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }
}
