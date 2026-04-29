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

    func insertAIResult(_ result: inout TranscriptAIResult) throws {
        try dbQueue.write { db in
            try result.insert(db)
        }
    }

    func saveChatMessage(_ message: inout TranscriptChatMessage) throws {
        try dbQueue.write { db in
            if message.id == nil {
                try message.insert(db)
            } else {
                try message.update(db)
            }
        }
    }

    func insertMarkdownFile(_ file: inout TranscriptMarkdownFile) throws {
        try dbQueue.write { db in
            try file.insert(db)
        }
    }

    func replaceContextCache(
        _ cache: inout TranscriptContextCache,
        chunks: [TranscriptContextChunk]
    ) throws {
        try dbQueue.write { db in
            _ = try TranscriptContextCache
                .filter(Column("transcriptId") == cache.transcriptId)
                .deleteAll(db)

            try cache.insert(db)
            guard let cacheId = cache.id else { return }

            for var chunk in chunks {
                chunk.cacheId = cacheId
                try chunk.insert(db)
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

    func fetchChatMessages(transcriptId: Int64) throws -> [TranscriptChatMessage] {
        try dbQueue.read { db in
            try TranscriptChatMessage
                .filter(Column("transcriptId") == transcriptId)
                .order(Column("createdAt").asc)
                .order(Column("id").asc)
                .fetchAll(db)
        }
    }

    func fetchMarkdownFiles(transcriptId: Int64) throws -> [TranscriptMarkdownFile] {
        try dbQueue.read { db in
            try TranscriptMarkdownFile
                .filter(Column("transcriptId") == transcriptId)
                .order(Column("createdAt").desc)
                .order(Column("id").desc)
                .fetchAll(db)
        }
    }

    func fetchMarkdownFile(id: Int64) throws -> TranscriptMarkdownFile? {
        try dbQueue.read { db in
            try TranscriptMarkdownFile.fetchOne(db, id: id)
        }
    }

    func markdownFileForLegacyAIResult(
        transcriptId: Int64,
        legacyAIResultId: Int64
    ) throws -> TranscriptMarkdownFile? {
        try dbQueue.read { db in
            try TranscriptMarkdownFile
                .filter(Column("transcriptId") == transcriptId)
                .filter(Column("legacyAIResultId") == legacyAIResultId)
                .fetchOne(db)
        }
    }

    func fetchContextCache(transcriptId: Int64) throws -> TranscriptContextCache? {
        try dbQueue.read { db in
            try TranscriptContextCache
                .filter(Column("transcriptId") == transcriptId)
                .fetchOne(db)
        }
    }

    func fetchContextChunks(cacheId: Int64) throws -> [TranscriptContextChunk] {
        try dbQueue.read { db in
            try TranscriptContextChunk
                .filter(Column("cacheId") == cacheId)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
        }
    }

    func fetchContextCacheWithChunks(
        transcriptId: Int64
    ) throws -> (cache: TranscriptContextCache, chunks: [TranscriptContextChunk])? {
        try dbQueue.read { db in
            guard let cache = try TranscriptContextCache
                .filter(Column("transcriptId") == transcriptId)
                .fetchOne(db),
                  let cacheId = cache.id
            else {
                return nil
            }

            let chunks = try TranscriptContextChunk
                .filter(Column("cacheId") == cacheId)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
            return (cache, chunks)
        }
    }

    func staleContextCacheTranscriptIDs(limit: Int) throws -> [Int64] {
        try dbQueue.read { db in
            let sql = """
                SELECT transcript.id
                FROM transcript
                LEFT JOIN transcriptContextCache
                    ON transcriptContextCache.transcriptId = transcript.id
                WHERE transcript.status = ?
                  AND (
                    transcriptContextCache.id IS NULL
                    OR transcriptContextCache.status = ?
                  )
                ORDER BY transcript.createdAt DESC
                LIMIT ?
                """
            return try Int64.fetchAll(
                db,
                sql: sql,
                arguments: [
                    Transcript.TranscriptStatus.completed.rawValue,
                    TranscriptContextCache.Status.failed.rawValue,
                    limit,
                ]
            )
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

    func updateSourcePath(_ id: Int64, sourcePath: String) throws {
        try dbQueue.write { db in
            if var transcript = try Transcript.fetchOne(db, id: id) {
                transcript.sourcePath = sourcePath
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

    func deleteChatMessages(transcriptId: Int64) throws {
        try dbQueue.write { db in
            _ = try TranscriptChatMessage
                .filter(Column("transcriptId") == transcriptId)
                .deleteAll(db)
        }
    }

    func deleteMarkdownFile(id: Int64) throws {
        try dbQueue.write { db in
            _ = try TranscriptMarkdownFile.deleteOne(db, id: id)
        }
    }

    func deleteContextCache(transcriptId: Int64) throws {
        try dbQueue.write { db in
            _ = try TranscriptContextCache
                .filter(Column("transcriptId") == transcriptId)
                .deleteAll(db)
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

    // MARK: - Search & Filter

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

    func fetchFiltered(
        category: TranscriptCategory = .all,
        dateFilter: DateFilter = .allTime,
        searchQuery: String? = nil,
        titleFilter: String? = nil
    ) throws -> [Transcript] {
        let trimmedQuery = searchQuery?.trimmingCharacters(in: .whitespaces)
        let hasSearch = trimmedQuery != nil && !trimmedQuery!.isEmpty

        return try dbQueue.read { db in
            var conditions = ["transcript.status = ?"]
            var arguments: [any DatabaseValueConvertible] = [
                Transcript.TranscriptStatus.completed.rawValue
            ]

            // Category filter
            switch category {
            case .all:
                break
            case .youtube:
                conditions.append("transcript.remoteSource = ?")
                arguments.append(Transcript.RemoteSource.youtube.rawValue)
            case .spotify:
                conditions.append("transcript.remoteSource = ?")
                arguments.append(Transcript.RemoteSource.spotify.rawValue)
            case .localAudio:
                conditions.append("(transcript.sourceType = ? OR transcript.sourceType = ?)")
                arguments.append(Transcript.SourceType.file.rawValue)
                arguments.append(Transcript.SourceType.recording.rawValue)
            }

            // Date filter
            if let startDate = dateFilter.startDate {
                conditions.append("transcript.createdAt >= ?")
                arguments.append(startDate)
            }

            // Title filter (case-insensitive LIKE)
            if let titleTerm = titleFilter?.trimmingCharacters(in: .whitespaces), !titleTerm.isEmpty {
                conditions.append("transcript.title LIKE ?")
                arguments.append("%\(titleTerm)%")
            }

            let whereClause = conditions.joined(separator: " AND ")

            let sql: String
            if hasSearch {
                let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmedQuery!)
                sql = """
                    SELECT transcript.*
                    FROM transcript
                    JOIN transcriptFTS ON transcriptFTS.rowid = transcript.rowid
                    WHERE transcriptFTS MATCH ?
                      AND \(whereClause)
                    ORDER BY transcript.createdAt DESC
                    """
                var allArgs: [any DatabaseValueConvertible] = [pattern]
                allArgs.append(contentsOf: arguments)
                return try Transcript.fetchAll(
                    db,
                    sql: sql,
                    arguments: StatementArguments(allArgs)
                )
            } else {
                sql = """
                    SELECT *
                    FROM transcript
                    WHERE \(whereClause)
                    ORDER BY createdAt DESC
                    """
                return try Transcript.fetchAll(
                    db,
                    sql: sql,
                    arguments: StatementArguments(arguments)
                )
            }
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
