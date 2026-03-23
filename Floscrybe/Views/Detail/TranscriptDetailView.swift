import AppKit
import SwiftUI

struct TranscriptDetailView: View {
    enum DetailTab: String, CaseIterable, Identifiable {
        case transcript
        case ai

        var id: String { rawValue }

        var title: String {
            switch self {
            case .transcript: "Transcript"
            case .ai: "AI Summary"
            }
        }
    }

    @Environment(AppState.self) private var appState

    let transcript: Transcript

    @State private var segments: [TranscriptSegment] = []
    @State private var aiResults: [TranscriptAIResult] = []
    @State private var selectedTab: DetailTab = .transcript
    @State private var selectedAIResultID: Int64?
    @State private var showTimestamps: Bool = false
    @State private var isGeneratingAI = false
    @State private var aiError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Centered thumbnail + metadata
            VStack(spacing: Spacing.md) {
                if let urlString = transcript.thumbnailURL,
                   let url = URL(string: urlString) {
                    thumbnailView(imageURL: url)
                }

                VStack(spacing: Spacing.xs) {
                    Text(transcript.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ColorTokens.textPrimary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: Spacing.sm) {
                        Label {
                            Text(TimeFormatting.formattedDate(transcript.createdAt))
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)

                        if let duration = transcript.durationSeconds, duration > 0 {
                            Label {
                                Text(TimeFormatting.duration(seconds: duration))
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                        }

                        HStack(spacing: Spacing.xxs) {
                            SourceIconView(
                                category: TranscriptCategory.category(for: transcript),
                                size: 10
                            )
                            Text(TranscriptCategory.category(for: transcript).displayName)
                                .font(Typography.caption)
                                .foregroundStyle(ColorTokens.textMuted)
                        }

                        if let collectionTitle = transcript.collectionTitle {
                            Text(collectionTitle)
                                .font(Typography.caption)
                                .foregroundStyle(ColorTokens.textMuted)
                        }

                        if transcript.speakerCount > 0 {
                            Text("\(transcript.speakerCount) speakers")
                                .font(Typography.caption)
                                .foregroundStyle(ColorTokens.textMuted)
                        }

                        if !aiResults.isEmpty {
                            Text("\(aiResults.count) AI save\(aiResults.count == 1 ? "" : "s")")
                                .font(Typography.caption)
                                .foregroundStyle(ColorTokens.textMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)

            // Centered underline tab bar
            HStack(spacing: Spacing.lg) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.title)
                        .font(Typography.headline)
                        .foregroundStyle(
                            selectedTab == tab
                                ? ColorTokens.textPrimary
                                : ColorTokens.textMuted
                        )
                        .padding(.vertical, Spacing.sm)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(ColorTokens.textPrimary)
                                    .frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTab = tab }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.md)

            Divider()
                .background(ColorTokens.border)

            Group {
                switch selectedTab {
                case .transcript:
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                    TranscriptSegmentView(
                                        segment: segment,
                                        showTimestamps: showTimestamps,
                                        searchQuery: appState.activeSearchQuery,
                                        currentGlobalMatchIndex: appState.currentMatchIndex,
                                        globalMatchOffset: matchOffset(upTo: index)
                                    )
                                    .id(segment.id)
                                }
                            }
                            .frame(maxWidth: 720)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, Spacing.xl)
                            .padding(.vertical, Spacing.lg)
                            .padding(.bottom, 60) // Space for floating toolbar
                        }
                        .onChange(of: appState.currentMatchIndex) { _, _ in
                            scrollToCurrentMatch(proxy: proxy)
                        }
                        .onChange(of: appState.activeSearchQuery) { _, _ in
                            updateMatchCount()
                        }
                    }

                case .ai:
                    TranscriptAIResultPane(
                        results: aiResults,
                        selectedResultID: $selectedAIResultID,
                        isGenerating: isGeneratingAI,
                        statusMessage: activeTaskStatusMessage,
                        errorMessage: aiError,
                        onDelete: deleteAIResult
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                TranscriptToolbar(
                    transcript: transcript,
                    segments: segments,
                    showTimestamps: $showTimestamps,
                    selectedTab: selectedTab,
                    selectedAIResult: aiResults.first(where: { $0.id == selectedAIResultID }),
                    isGeneratingAI: isGeneratingAI,
                    onRunPrompt: runPrompt,
                    onShowAITab: { selectedTab = .ai }
                )
                .padding(.bottom, Spacing.md)
            }
        }
        .background(ColorTokens.backgroundRaised)
        .onAppear {
            showTimestamps = appState.settings.showTimestamps
            loadTranscriptData()
            updateMatchCount()
        }
        .onChange(of: transcript.id) { _, _ in
            selectedTab = .transcript
            aiError = nil
            loadTranscriptData()
            updateMatchCount()
        }
    }

    @ViewBuilder
    private func thumbnailView(imageURL: URL) -> some View {
        let image = CachedAsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .empty, .failure:
                RoundedRectangle(cornerRadius: 12)
                    .fill(ColorTokens.backgroundFloat)
                    .overlay {
                        SourceIconView(
                            category: TranscriptCategory.category(for: transcript),
                            size: 28
                        )
                    }
            }
        }
        .frame(width: 288, height: 162)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ColorTokens.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 2, y: 1)

        if transcript.sourceType == .url, let sourceURL = URL(string: transcript.sourcePath) {
            Button {
                NSWorkspace.shared.open(sourceURL)
            } label: {
                image
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        } else {
            image
        }
    }

    private func loadTranscriptData() {
        loadSegments()
        loadAIResults()
    }

    private func loadSegments() {
        guard let id = transcript.id, let repo = appState.repository else { return }
        segments = (try? repo.fetchSegments(transcriptId: id)) ?? []
    }

    private func loadAIResults(selecting selectedID: Int64? = nil) {
        guard let id = transcript.id, let repo = appState.repository else { return }
        aiResults = (try? repo.fetchAIResults(transcriptId: id)) ?? []

        if let selectedID, aiResults.contains(where: { $0.id == selectedID }) {
            selectedAIResultID = selectedID
        } else if let existingSelection = selectedAIResultID,
                  aiResults.contains(where: { $0.id == existingSelection }) {
            selectedAIResultID = existingSelection
        } else {
            selectedAIResultID = aiResults.first?.id
        }
    }

    private func runPrompt(_ promptTemplate: AIPromptTemplate) {
        guard !isGeneratingAI, !appState.codexService.isRunningTask else { return }
        Task {
            await generateAIResult(using: promptTemplate)
        }
    }

    private func deleteAIResult(_ id: Int64) {
        guard let repo = appState.repository else { return }
        try? repo.deleteAIResult(id: id)
        loadAIResults()
    }

    private func generateAIResult(using promptTemplate: AIPromptTemplate) async {
        guard let transcriptID = transcript.id, let repo = appState.repository else { return }

        await MainActor.run {
            selectedTab = .ai
            isGeneratingAI = true
            aiError = nil
        }

        do {
            let content = try await appState.codexService.runTranscriptTask(
                promptTemplate,
                transcript: transcript,
                segments: segments
            )

            var result = TranscriptAIResult(
                id: nil,
                transcriptId: transcriptID,
                promptID: promptTemplate.id,
                promptTitle: promptTemplate.title,
                promptBody: promptTemplate.body,
                content: content,
                createdAt: Date()
            )
            try repo.saveAIResult(&result)

            await MainActor.run {
                isGeneratingAI = false
                loadAIResults(selecting: result.id)
            }
        } catch {
            await MainActor.run {
                isGeneratingAI = false
                aiError = error.localizedDescription
            }
        }
    }

    private func matchOffset(upTo segmentIndex: Int) -> Int {
        var offset = 0
        for i in 0..<segmentIndex {
            offset += HighlightedText.matchCount(in: segments[i].text, query: appState.activeSearchQuery)
        }
        return offset
    }

    private func updateMatchCount() {
        let query = appState.activeSearchQuery
        guard !query.isEmpty else {
            appState.totalMatchCount = 0
            return
        }
        var total = 0
        for segment in segments {
            total += HighlightedText.matchCount(in: segment.text, query: query)
        }
        appState.totalMatchCount = total
    }

    private func scrollToCurrentMatch(proxy: ScrollViewProxy) {
        let targetIndex = appState.currentMatchIndex
        guard appState.totalMatchCount > 0 else { return }

        var cumulative = 0
        for segment in segments {
            let count = HighlightedText.matchCount(in: segment.text, query: appState.activeSearchQuery)
            if cumulative + count > targetIndex {
                withAnimation {
                    proxy.scrollTo(segment.id, anchor: .center)
                }
                return
            }
            cumulative += count
        }
    }

    private var activeTaskStatusMessage: String? {
        guard appState.codexService.activeTaskTranscriptId == transcript.id || isGeneratingAI else {
            return nil
        }

        var components: [String] = []

        if let promptTitle = appState.codexService.activeTaskPromptTitle, !promptTitle.isEmpty {
            components.append(promptTitle)
        }

        if let status = appState.codexService.activeTaskStatus, !status.isEmpty {
            components.append(status)
        }

        guard !components.isEmpty else { return nil }
        return components.joined(separator: " · ")
    }
}
