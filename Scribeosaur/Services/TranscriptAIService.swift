import Foundation

@MainActor
protocol TranscriptAIService: AnyObject {
    var promptTemplates: [AIPromptTemplate] { get }
    var availablePromptTemplates: [AIPromptTemplate] { get }
    var activeTaskPromptTitle: String? { get }
    var activeTaskStatus: String? { get }
    var activeTaskTranscriptId: Int64? { get }
    var isRunningTask: Bool { get }
    var lastError: String? { get }
    var statusTitle: String { get }
    var statusDetail: String { get }

    func refreshStatus() async
    func cancelActiveTask()
    func runTranscriptTask(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        segments: [TranscriptSegment],
        preparedContext: PreparedTranscriptContext?
    ) async throws -> String
    func streamTranscriptTask(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        segments: [TranscriptSegment],
        preparedContext: PreparedTranscriptContext?
    ) -> AsyncStream<String>
    func streamTranscriptChat(
        message: String,
        transcript: Transcript,
        segments: [TranscriptSegment],
        history: [TranscriptChatMessage],
        preparedContext: PreparedTranscriptContext?
    ) -> AsyncStream<String>
    func runTranscriptMarkdownFileTask(
        userPrompt: String,
        transcript: Transcript,
        segments: [TranscriptSegment],
        preparedContext: PreparedTranscriptContext?
    ) async throws -> String
    func createCustomPrompt() -> AIPromptTemplate
    func savePrompt(_ prompt: AIPromptTemplate)
    func deletePrompt(id: String)
}
