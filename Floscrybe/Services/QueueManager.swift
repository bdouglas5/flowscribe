import Foundation

@Observable
final class QueueManager {
    var items: [QueueItem] = []
    var isProcessing = false
    var onItemCompleted: ((Int64, QueueItem) -> Void)?

    private let pipeline: AudioPipelineService
    private var processingTask: Task<Void, Never>?

    init(pipeline: AudioPipelineService) {
        self.pipeline = pipeline
    }

    func enqueue(_ item: QueueItem) {
        items.append(item)
        AppLogger.info("Queue", "Queued item \(item.title)")
        startProcessingIfNeeded()
    }

    func enqueue(_ newItems: [QueueItem]) {
        items.append(contentsOf: newItems)
        AppLogger.info("Queue", "Queued \(newItems.count) item(s)")
        startProcessingIfNeeded()
    }

    func replace(_ item: QueueItem, with newItems: [QueueItem]) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            items.insert(contentsOf: newItems, at: index)
        } else {
            items.append(contentsOf: newItems)
        }
        startProcessingIfNeeded()
    }

    func removeCompleted() {
        items.removeAll { $0.status == .completed }
    }

    func retry(_ item: QueueItem) {
        item.status = .waiting
        item.progress = 0
        item.errorMessage = nil
        AppLogger.info("Queue", "Item reset for retry \(item.title)")
        startProcessingIfNeeded()
    }

    func cancel(_ item: QueueItem) {
        AppLogger.info("Queue", "Cancelling item \(item.title)")
        items.removeAll { $0.id == item.id }
    }

    var pendingItems: [QueueItem] {
        items.filter { $0.status == .waiting }
    }

    var activeItem: QueueItem? {
        items.first { $0.isProcessing }
    }

    var completedItems: [QueueItem] {
        items.filter { $0.status == .completed }
    }

    private func startProcessingIfNeeded() {
        guard !isProcessing else { return }
        guard items.contains(where: { $0.status == .waiting }) else { return }

        isProcessing = true
        processingTask = Task {
            await processQueue()
        }
    }

    private func processQueue() async {
        while let next = await nextWaitingItem() {
            do {
                AppLogger.info("Queue", "Processing item \(next.title)")
                let transcriptId = try await pipeline.process(item: next)
                await MainActor.run {
                    next.status = .completed
                    next.resultTranscriptId = transcriptId
                }
                AppLogger.info("Queue", "Completed item \(next.title) transcriptId=\(transcriptId)")
                onItemCompleted?(transcriptId, next)
            } catch {
                await MainActor.run {
                    next.status = .failed
                    next.errorMessage = error.localizedDescription
                }
                AppLogger.error("Queue", "Failed item \(next.title): \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            isProcessing = false
        }
        AppLogger.info("Queue", "Queue processing idle")
    }

    @MainActor
    private func nextWaitingItem() -> QueueItem? {
        items.first { $0.status == .waiting }
    }
}
