import Foundation

enum TranscriptMarkdownFileMaterializer {
    @discardableResult
    static func materializeLegacyAIResults(
        transcript: Transcript,
        repository: TranscriptRepository
    ) throws -> [TranscriptMarkdownFile] {
        guard let transcriptID = transcript.id else { return [] }

        let legacyResults = try repository.fetchAIResults(transcriptId: transcriptID)
        var createdFiles: [TranscriptMarkdownFile] = []

        for result in legacyResults {
            guard let resultID = result.id,
                  try repository.markdownFileForLegacyAIResult(
                    transcriptId: transcriptID,
                    legacyAIResultId: resultID
                  ) == nil
            else { continue }

            let content = ExportService.aiMarkdownContent(transcript: transcript, aiResult: result)
            let writtenFile = try TranscriptMarkdownFileStorage.writeMarkdown(
                title: "\(transcript.title) - \(result.promptTitle)",
                content: content,
                transcriptID: transcriptID
            )
            var markdownFile = TranscriptMarkdownFile(
                id: nil,
                transcriptId: transcriptID,
                title: result.promptTitle,
                fileName: writtenFile.fileName,
                sourcePrompt: result.promptBody,
                legacyAIResultId: resultID,
                createdAt: result.createdAt,
                updatedAt: result.createdAt
            )
            try repository.insertMarkdownFile(&markdownFile)
            createdFiles.append(markdownFile)
        }

        return createdFiles
    }
}
