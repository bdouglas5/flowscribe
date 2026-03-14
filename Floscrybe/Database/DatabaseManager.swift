import Foundation
import GRDB

final class DatabaseManager {
    let dbQueue: DatabaseQueue

    init() throws {
        try StoragePaths.ensureDirectoriesExist()
        dbQueue = try DatabaseQueue(path: StoragePaths.databaseFile.path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_tables") { db in
            try db.create(table: "transcript") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("sourceType", .text).notNull()
                t.column("sourcePath", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("durationSeconds", .double)
                t.column("speakerDetection", .boolean).notNull().defaults(to: false)
                t.column("speakerCount", .integer).notNull().defaults(to: 0)
                t.column("fullText", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull().defaults(to: "processing")
                t.column("errorMessage", .text)
            }

            try db.create(table: "transcriptSegment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("transcriptId", .integer)
                    .notNull()
                    .indexed()
                    .references("transcript", onDelete: .cascade)
                t.column("speakerId", .integer)
                t.column("speakerName", .text)
                t.column("text", .text).notNull()
                t.column("startTime", .double).notNull()
                t.column("endTime", .double).notNull()
                t.column("sortOrder", .integer).notNull()
            }

            try db.create(virtualTable: "transcriptFTS", using: FTS5()) { t in
                t.tokenizer = .unicode61()
                t.synchronize(withTable: "transcript")
                t.column("title")
                t.column("fullText")
            }
        }

        migrator.registerMigration("v2_add_remote_source_metadata") { db in
            try db.alter(table: "transcript") { t in
                t.add(column: "remoteSource", .text)
            }
        }

        migrator.registerMigration("v3_add_collection_metadata") { db in
            try db.alter(table: "transcript") { t in
                t.add(column: "collectionID", .text)
                t.add(column: "collectionTitle", .text)
                t.add(column: "collectionType", .text)
                t.add(column: "collectionItemIndex", .integer)
            }
        }

        migrator.registerMigration("v4_add_transcript_ai_results") { db in
            try db.create(table: "transcriptAIResult") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("transcriptId", .integer)
                    .notNull()
                    .indexed()
                    .references("transcript", onDelete: .cascade)
                t.column("promptID", .text).notNull()
                t.column("promptTitle", .text).notNull()
                t.column("promptBody", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        try migrator.migrate(dbQueue)
    }
}
