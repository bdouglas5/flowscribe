import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var expandedCollections: Set<String> = []

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedTranscriptId) {
            if let queueManager = appState.queueManager,
               !filteredQueueItems(queueManager.items).isEmpty {
                Section("Queue") {
                    ForEach(filteredQueueItems(queueManager.items)) { item in
                        QueueItemRow(
                            item: item,
                            onRetry: { appState.retryQueueItem(item) },
                            onCancel: { appState.cancelQueueItem(item) }
                        )
                    }
                }
            }

            Section(header: Text("HISTORY").font(Typography.sectionHeader).foregroundStyle(ColorTokens.textMuted)) {
                if historyEntries.isEmpty {
                    emptyFilterState
                } else {
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
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            CategoryFilterBar(
                searchText: $searchText,
                selectedCategory: $state.selectedCategory,
                selectedDateFilter: $state.selectedDateFilter,
                matchCount: appState.totalMatchCount,
                currentMatchIndex: appState.currentMatchIndex,
                onPreviousMatch: { appState.navigateToPreviousMatch() },
                onNextMatch: { appState.navigateToNextMatch() }
            )
            .background(ColorTokens.backgroundBase)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ColorTokens.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(ColorTokens.backgroundFloat, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorTokens.backgroundBase)
        }
        .onAppear {
            expandedCollections.formUnion(historyEntries.compactMap {
                if case .collection(let collection) = $0 {
                    return collection.id
                }
                return nil
            })
        }
        .onChange(of: searchText) { _, newValue in
            applyFilters(searchQuery: newValue)
        }
        .onChange(of: appState.selectedCategory) { _, _ in
            applyFilters(searchQuery: searchText)
        }
        .onChange(of: appState.selectedDateFilter) { _, _ in
            applyFilters(searchQuery: searchText)
        }
        .background(ColorTokens.backgroundBase)
    }

    private func applyFilters(searchQuery: String) {
        if searchQuery.isEmpty {
            appState.refreshTranscripts()
        } else {
            appState.searchTranscripts(query: searchQuery)
        }
    }

    private func filteredQueueItems(_ items: [QueueItem]) -> [QueueItem] {
        items.filter { item in
            item.status != .completed &&
            (appState.selectedCategory == .all ||
             TranscriptCategory.category(for: item) == appState.selectedCategory)
        }
    }

    @ViewBuilder
    private var emptyFilterState: some View {
        let hasActiveFilters = appState.selectedCategory != .all ||
            appState.selectedDateFilter != .allTime ||
            !searchText.isEmpty

        if hasActiveFilters {
            VStack(spacing: Spacing.sm) {
                Text("No transcripts match your filters")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)

                Button("Clear Filters") {
                    appState.selectedCategory = .all
                    appState.selectedDateFilter = .allTime
                    searchText = ""
                    appState.refreshTranscripts()
                }
                .font(Typography.caption)
                .foregroundStyle(ColorTokens.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
        }
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
        let groupChannels = appState.settings.youtubeAutoGroupByChannel
        var entries: [HistoryEntry] = []
        var seenCollections: Set<String> = []

        for transcript in appState.transcripts {
            guard let collectionID = transcript.collectionID else {
                entries.append(.single(transcript))
                continue
            }

            // When channel grouping is off, show channel-type items individually
            if transcript.collectionType == .channel && !groupChannels {
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
            collectionIcon
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

    private var collectionIcon: some View {
        let collectionCategory: TranscriptCategory = {
            switch collection.type {
            case .show: return .spotify
            case .channel, .playlist: return .youtube
            case .none: return .all
            }
        }()

        return ThumbnailView(
            thumbnailURL: collection.transcripts.first?.thumbnailURL,
            category: collectionCategory,
            size: 40
        )
    }
}

private struct HistoryCollection: Identifiable {
    let id: String
    let title: String
    let type: Transcript.CollectionType?
    let transcripts: [Transcript]
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
