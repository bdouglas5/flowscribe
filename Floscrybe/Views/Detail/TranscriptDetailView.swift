import SwiftUI

struct TranscriptDetailView: View {
    enum DetailTab: String, CaseIterable, Identifiable {
        case transcript
        case ai

        var id: String { rawValue }

        var title: String {
            switch self {
            case .transcript: "Transcript"
            case .ai: "AI"
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
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(transcript.title)
                        .font(Typography.largeTitle)
                        .foregroundStyle(ColorTokens.textPrimary)

                    HStack(spacing: Spacing.sm) {
                        if let collectionTitle = transcript.collectionTitle {
                            Text(collectionTitle)
                                .font(Typography.caption)
                                .foregroundStyle(ColorTokens.textMuted)
                        }

                        Text(TimeFormatting.formattedDate(transcript.createdAt))
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)

                        if let duration = transcript.durationSeconds, duration > 0 {
                            Text(TimeFormatting.duration(seconds: duration))
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
                Spacer()
            }
            .padding(Spacing.md)

            Divider()
                .background(ColorTokens.border)

            Picker("View", selection: $selectedTab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider()
                .background(ColorTokens.border)

            Group {
                switch selectedTab {
                case .transcript:
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                            ForEach(segments) { segment in
                                TranscriptSegmentView(
                                    segment: segment,
                                    showTimestamps: showTimestamps
                                )
                            }
                        }
                        .padding(Spacing.md)
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

            Divider()
                .background(ColorTokens.border)

            TranscriptToolbar(
                transcript: transcript,
                segments: segments,
                showTimestamps: $showTimestamps,
                isGeneratingAI: isGeneratingAI,
                onRunPrompt: runPrompt,
                onShowAITab: { selectedTab = .ai }
            )
        }
        .background(ColorTokens.backgroundBase)
        .onAppear {
            showTimestamps = appState.settings.showTimestamps
            loadTranscriptData()
        }
        .onChange(of: transcript.id) { _, _ in
            selectedTab = .transcript
            aiError = nil
            loadTranscriptData()
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

    private var activeTaskStatusMessage: String? {
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
