import Foundation

struct ResolvedRemoteQueueItem: Equatable, Sendable {
    let title: String
    let sourceURL: URL
    let sourceType: Transcript.SourceType
    let remoteSource: Transcript.RemoteSource?
    let collectionID: String?
    let collectionTitle: String?
    let collectionType: Transcript.CollectionType?
    let collectionItemIndex: Int?
    let thumbnailURL: String?
    let speakerDetection: Bool
    let speakerNames: [String]
}

actor URLResolutionCoordinator {
    private var inFlightTasks: [String: Task<[ResolvedRemoteQueueItem], Error>] = [:]
    private var serialTail: Task<Void, Never>?

    func resolve(
        normalizedURL: String,
        operation: @escaping @Sendable () async throws -> [ResolvedRemoteQueueItem]
    ) async throws -> [ResolvedRemoteQueueItem] {
        if let existingTask = inFlightTasks[normalizedURL] {
            AppLogger.info("Queue", "Joining in-flight URL resolution for \(normalizedURL)")
            return try await existingTask.value
        }

        let previousTask = serialTail
        let task = Task<[ResolvedRemoteQueueItem], Error> {
            _ = await previousTask?.result
            return try await operation()
        }
        inFlightTasks[normalizedURL] = task
        serialTail = Task { _ = await task.result }

        do {
            let result = try await task.value
            inFlightTasks.removeValue(forKey: normalizedURL)
            return result
        } catch {
            inFlightTasks.removeValue(forKey: normalizedURL)
            throw error
        }
    }

    static func normalizedURLString(from rawValue: String) -> String? {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil

        if let queryItems = components.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems.sorted {
                if $0.name == $1.name {
                    return ($0.value ?? "") < ($1.value ?? "")
                }
                return $0.name < $1.name
            }
        }

        return components.string ?? url.absoluteString
    }
}
