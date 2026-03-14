import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var expandedCollections: Set<String> = []

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedTranscriptId) {
            if let queueManager = appState.queueManager,
               !queueManager.items.isEmpty {
                Section("Queue") {
                    ForEach(queueManager.items.filter { $0.status != .completed }) { item in
                        QueueItemRow(
                            item: item,
                            onRetry: { appState.retryQueueItem(item) },
                            onCancel: { appState.cancelQueueItem(item) }
                        )
                    }
                }
            }

            Section("History") {
                ForEach(historyEntries) { entry in
                    switch entry {
                    case .single(let transcript):
                        transcriptRow(transcript)
                    case .collection(let collection):
                        DisclosureGroup(
                            isExpanded: expandedBinding(for: collection.id)
                        ) {
                            ForEach(collection.transcripts) { transcript in
                                transcriptRow(transcript)
                                    .padding(.leading, Spacing.md)
                            }
                        } label: {
                            CollectionCard(collection: collection)
                        }
                        .contextMenu {
                            Button("Delete Collection", role: .destructive) {
                                appState.deleteCollection(id: collection.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search transcripts")
        .onAppear {
            expandedCollections.formUnion(historyEntries.compactMap {
                if case .collection(let collection) = $0 {
                    return collection.id
                }
                return nil
            })
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                appState.refreshTranscripts()
            } else {
                appState.searchTranscripts(query: newValue)
            }
        }
        .background(ColorTokens.backgroundRaised)
    }

    @ViewBuilder
    private func transcriptRow(_ transcript: Transcript) -> some View {
        TranscriptRow(transcript: transcript)
            .tag(transcript.id!)
            .contextMenu {
                Button("Delete", role: .destructive) {
                    if let id = transcript.id {
                        appState.deleteTranscript(id: id)
                    }
                }
            }
    }

    private var historyEntries: [HistoryEntry] {
        var entries: [HistoryEntry] = []
        var seenCollections: Set<String> = []

        for transcript in appState.transcripts {
            guard let collectionID = transcript.collectionID else {
                entries.append(.single(transcript))
                continue
            }

            guard seenCollections.insert(collectionID).inserted else { continue }

            let transcripts = appState.transcripts
                .filter { $0.collectionID == collectionID }
                .sorted { lhs, rhs in
                    switch (lhs.collectionItemIndex, rhs.collectionItemIndex) {
                    case let (lhsIndex?, rhsIndex?):
                        return lhsIndex < rhsIndex
                    case (.some, nil):
                        return true
                    case (nil, .some):
                        return false
                    case (nil, nil):
                        return lhs.createdAt > rhs.createdAt
                    }
                }

            entries.append(
                .collection(
                    HistoryCollection(
                        id: collectionID,
                        title: transcript.collectionTitle ?? transcript.title,
                        type: transcript.collectionType,
                        transcripts: transcripts
                    )
                )
            )
        }

        return entries
    }

    private func expandedBinding(for collectionID: String) -> Binding<Bool> {
        Binding(
            get: { expandedCollections.contains(collectionID) },
            set: { isExpanded in
                if isExpanded {
                    expandedCollections.insert(collectionID)
                } else {
                    expandedCollections.remove(collectionID)
                }
            }
        )
    }
}

private struct CollectionCard: View {
    let collection: HistoryCollection

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: collection.iconName)
                .foregroundStyle(ColorTokens.textSecondary)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(collection.title)
                    .font(Typography.headline)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .lineLimit(1)

                Text("\(collection.transcripts.count) transcripts")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.xxs)
    }
}

private struct HistoryCollection: Identifiable {
    let id: String
    let title: String
    let type: Transcript.CollectionType?
    let transcripts: [Transcript]

    var iconName: String {
        switch type {
        case .channel: "person.crop.rectangle.stack"
        case .playlist, .none: "list.bullet.rectangle"
        }
    }
}

private enum HistoryEntry: Identifiable {
    case single(Transcript)
    case collection(HistoryCollection)

    var id: String {
        switch self {
        case .single(let transcript):
            return "single-\(transcript.id ?? 0)"
        case .collection(let collection):
            return "collection-\(collection.id)"
        }
    }
}
