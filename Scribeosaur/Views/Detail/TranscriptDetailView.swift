import AppKit
import SwiftUI

struct TranscriptDetailView: View {
    @Environment(AppState.self) private var appState

    let transcript: Transcript

    @State private var segments: [TranscriptSegment] = []
    @State private var markdownFiles: [TranscriptMarkdownFile] = []
    @State private var preparedContext: PreparedTranscriptContext?
    @State private var documentSheetFile: TranscriptMarkdownFile?
    @State private var documentSheetContent = ""
    @State private var documentSheetMissing = false
    @State private var isDocumentSheetPresented = false
    @State private var chatMessages: [TranscriptChatMessage] = []
    @State private var chatDraft = ""
    @State private var streamingAssistantText = ""
    @State private var showTimestamps = false
    @State private var isChatCollapsed = false
    @State private var isAIRunning = false
    @State private var aiError: String?
    @State private var activeAITask: Task<Void, Never>?
    @State private var contextRefreshTask: Task<Void, Never>?

    private var isAnyAIRunning: Bool {
        isAIRunning || appState.aiService.isRunningTask
    }

    var body: some View {
        HStack(spacing: 0) {
            transcriptWorkspace

            if isChatCollapsed {
                collapsedChatRail
            } else {
                Divider()
                    .background(ColorTokens.border)

                TranscriptChatPanel(
                    messages: chatMessages,
                    promptTemplates: appState.aiService.availablePromptTemplates,
                    draft: $chatDraft,
                    streamingAssistantText: streamingAssistantText,
                    isRunning: isAnyAIRunning,
                    statusMessage: activeTaskStatusMessage,
                    errorMessage: aiError,
                    onRunPreset: runPreset,
                    onOpenPromptSettings: { appState.openSettings(section: .ai) },
                    onSend: sendChatMessage,
                    onCancel: cancelActiveAI,
                    onClear: clearChatMessages,
                    onCollapse: { isChatCollapsed = true },
                    onSaveMessageAsMarkdown: saveChatMessageAsMarkdown
                )
                .frame(width: 340)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(ColorTokens.backgroundRaised)
        .animation(.easeInOut(duration: 0.2), value: isChatCollapsed)
        .sheet(isPresented: $isDocumentSheetPresented) {
            if let file = documentSheetFile {
                MarkdownFileSheet(
                    file: file,
                    content: documentSheetContent,
                    isMissing: documentSheetMissing,
                    onCopy: copySheetMarkdown,
                    onReveal: revealSheetMarkdown,
                    onExport: exportSheetMarkdown,
                    onDelete: deleteSheetMarkdown
                )
            }
        }
        .onAppear {
            showTimestamps = appState.settings.showTimestamps
            loadTranscriptData()
            updateMatchCount()
        }
        .onDisappear {
            activeAITask?.cancel()
            contextRefreshTask?.cancel()
        }
        .onChange(of: transcript.id) { _, _ in
            activeAITask?.cancel()
            activeAITask = nil
            contextRefreshTask?.cancel()
            contextRefreshTask = nil
            aiError = nil
            streamingAssistantText = ""
            chatDraft = ""
            preparedContext = nil
            loadTranscriptData()
            updateMatchCount()
        }
    }

    private var transcriptWorkspace: some View {
        VStack(spacing: 0) {
            transcriptHeader

            Divider()
                .background(ColorTokens.border)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.md) {
                        filesSection

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
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.lg)
                    .padding(.bottom, 60)
                }
                .onChange(of: appState.currentMatchIndex) { _, _ in
                    scrollToCurrentMatch(proxy: proxy)
                }
                .onChange(of: appState.activeSearchQuery) { _, _ in
                    updateMatchCount()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                TranscriptToolbar(
                    transcript: transcript,
                    segments: segments,
                    showTimestamps: $showTimestamps
                )
                .padding(.bottom, Spacing.md)
            }
        }
    }

    private var transcriptHeader: some View {
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

                    if !markdownFiles.isEmpty {
                        Text("\(markdownFiles.count) file\(markdownFiles.count == 1 ? "" : "s")")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.md)
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text("Files")
                    .font(Typography.headline)
                    .foregroundStyle(ColorTokens.textPrimary)

                Spacer()

                if let status = activeTaskStatusMessage, isAnyAIRunning {
                    Text(status)
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                        .lineLimit(1)
                }
            }

            if markdownFiles.isEmpty {
                Text("No markdown files yet.")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
                    .padding(.vertical, Spacing.xs)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 156, maximum: 220), spacing: Spacing.sm)],
                    alignment: .leading,
                    spacing: Spacing.sm
                ) {
                    ForEach(markdownFiles) { file in
                        MarkdownFileCard(file: file) {
                            openMarkdownFileSheet(file)
                        }
                    }
                }
            }

            if let aiError, !aiError.isEmpty {
                Text(aiError)
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.statusError)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ColorTokens.backgroundFloat)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ColorTokens.border.opacity(0.65), lineWidth: 1)
        )
    }

    private var collapsedChatRail: some View {
        VStack {
            Button {
                isChatCollapsed = false
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ColorTokens.textSecondary)
            .help("Show Transcript Chat")

            Spacer()
        }
        .frame(width: 52)
        .padding(.top, Spacing.md)
        .background(ColorTokens.backgroundBase)
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
        materializeLegacyAIResultsIfNeeded()
        loadMarkdownFiles()
        loadChatMessages()
        loadPreparedContext()
        prepareContextInBackground()
    }

    private func loadSegments() {
        guard let id = transcript.id, let repo = appState.repository else { return }
        segments = (try? repo.fetchSegments(transcriptId: id)) ?? []
    }

    private func loadPreparedContext() {
        preparedContext = appState.preparedTranscriptContext(
            for: transcript,
            segments: segments
        )
    }

    private func prepareContextInBackground() {
        guard let transcriptID = transcript.id else { return }
        appState.scheduleTranscriptContextPreparation(transcriptId: transcriptID)
        contextRefreshTask?.cancel()
        contextRefreshTask = Task {
            await appState.prepareTranscriptContextIfNeeded(
                transcript: transcript,
                segments: segments,
                waitForUserAI: true
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard transcript.id == transcriptID else { return }
                loadPreparedContext()
            }
        }
    }

    private func loadChatMessages() {
        guard let id = transcript.id, let repo = appState.repository else { return }
        chatMessages = (try? repo.fetchChatMessages(transcriptId: id)) ?? []
    }

    private func loadMarkdownFiles(selecting selectedID: Int64? = nil) {
        guard let id = transcript.id, let repo = appState.repository else { return }
        markdownFiles = (try? repo.fetchMarkdownFiles(transcriptId: id)) ?? []
        if let selectedID,
           let selectedFile = markdownFiles.first(where: { $0.id == selectedID }) {
            openMarkdownFileSheet(selectedFile)
        } else if let sheetFileID = documentSheetFile?.id,
                  let updatedFile = markdownFiles.first(where: { $0.id == sheetFileID }) {
            documentSheetFile = updatedFile
            loadDocumentSheetContent(for: updatedFile)
        } else if documentSheetFile != nil {
            documentSheetFile = nil
            documentSheetContent = ""
            documentSheetMissing = false
            isDocumentSheetPresented = false
        }
    }

    private func materializeLegacyAIResultsIfNeeded() {
        guard let transcriptID = transcript.id, let repo = appState.repository else { return }
        do {
            _ = try TranscriptMarkdownFileMaterializer.materializeLegacyAIResults(
                transcript: transcript,
                repository: repo
            )
        } catch {
            AppLogger.error(
                "TranscriptFiles",
                "Failed to materialize legacy AI results for transcript \(transcriptID): \(error.localizedDescription)"
            )
        }
    }

    private func runPreset(_ promptTemplate: AIPromptTemplate) {
        guard !isAnyAIRunning else { return }
        let context = preparedContext

        activeAITask = Task {
            await generateMarkdownFiles(
                fallbackTitle: promptTemplate.title,
                sourcePrompt: promptTemplate.body
            ) {
                try await appState.aiService.runTranscriptTask(
                    promptTemplate,
                    transcript: transcript,
                    segments: segments,
                    preparedContext: context
                )
            } onCreated: { files in
                guard let transcriptID = transcript.id else { return }
                _ = saveChatMessage(
                    role: .assistant,
                    content: createdFilesReply(files, emptyFallback: "I could not create a markdown file from \(promptTemplate.title)."),
                    transcriptID: transcriptID
                )
            }
        }
    }

    private func sendChatMessage() {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAnyAIRunning, let transcriptID = transcript.id else { return }

        let priorHistory = chatMessages
        chatDraft = ""
        aiError = nil

        guard saveChatMessage(role: .user, content: text, transcriptID: transcriptID) != nil else {
            return
        }

        if let localReply = TranscriptChatIntentDetector.localAssistantReply(for: text) {
            _ = saveChatMessage(role: .assistant, content: localReply, transcriptID: transcriptID)
            return
        }

        if TranscriptChatIntentDetector.shouldCreateMarkdownFile(for: text) {
            activeAITask = Task {
                await generateMarkdownFilesFromChat(message: text)
            }
        } else {
            activeAITask = Task {
                await streamChatResponse(message: text, history: priorHistory)
            }
        }
    }

    private func streamChatResponse(message: String, history: [TranscriptChatMessage]) async {
        let context = preparedContext

        await MainActor.run {
            isAIRunning = true
            aiError = nil
            streamingAssistantText = ""
        }

        var response = ""
        for await chunk in appState.aiService.streamTranscriptChat(
            message: message,
            transcript: transcript,
            segments: segments,
            history: history,
            preparedContext: context
        ) {
            if Task.isCancelled { break }
            response += chunk
            await MainActor.run {
                streamingAssistantText = response
            }
        }

        let sanitized = TranscriptAIUtilities.sanitizeModelResponse(response)
        await MainActor.run {
            if !Task.isCancelled, !sanitized.isEmpty, let transcriptID = transcript.id {
                _ = saveChatMessage(role: .assistant, content: sanitized, transcriptID: transcriptID)
            } else if sanitized.isEmpty, let lastError = appState.aiService.lastError {
                aiError = lastError
            }
            streamingAssistantText = ""
            isAIRunning = false
            activeAITask = nil
        }
    }

    private func generateMarkdownFilesFromChat(message: String) async {
        let context = preparedContext

        await generateMarkdownFiles(
            fallbackTitle: "Chat Document",
            sourcePrompt: message
        ) {
            try await appState.aiService.runTranscriptMarkdownFileTask(
                userPrompt: message,
                transcript: transcript,
                segments: segments,
                preparedContext: context
            )
        } onCreated: { files in
            guard let transcriptID = transcript.id else { return }
            let reply = createdFilesReply(
                files,
                emptyFallback: "I could not create a markdown file from that request."
            )
            _ = saveChatMessage(role: .assistant, content: reply, transcriptID: transcriptID)
        }
    }

    private func generateMarkdownFiles(
        fallbackTitle: String,
        sourcePrompt: String?,
        generate: @escaping () async throws -> String,
        onCreated: (([TranscriptMarkdownFile]) -> Void)? = nil
    ) async {
        guard let transcriptID = transcript.id else { return }

        await MainActor.run {
            isAIRunning = true
            aiError = nil
        }

        do {
            let content = try await generate()
            if Task.isCancelled { throw CancellationError() }
            let files = try saveMarkdownDocuments(
                from: content,
                fallbackTitle: fallbackTitle,
                sourcePrompt: sourcePrompt,
                transcriptID: transcriptID
            )

            await MainActor.run {
                onCreated?(files)
                isAIRunning = false
                activeAITask = nil
                loadMarkdownFiles(selecting: files.first?.id)
            }
        } catch is CancellationError {
            await MainActor.run {
                isAIRunning = false
                activeAITask = nil
                aiError = nil
            }
        } catch {
            await MainActor.run {
                isAIRunning = false
                activeAITask = nil
                aiError = error.localizedDescription
            }
        }
    }

    private func saveMarkdownDocuments(
        from content: String,
        fallbackTitle: String,
        sourcePrompt: String?,
        transcriptID: Int64
    ) throws -> [TranscriptMarkdownFile] {
        guard let repo = appState.repository else { return [] }
        let documents = TranscriptAIDocumentParser.documents(from: content, fallbackTitle: fallbackTitle)
        let createdAt = Date()
        var files: [TranscriptMarkdownFile] = []

        for document in documents {
            let writtenFile = try TranscriptMarkdownFileStorage.writeMarkdown(
                title: "\(transcript.title) - \(document.title)",
                content: document.content,
                transcriptID: transcriptID
            )
            var markdownFile = TranscriptMarkdownFile(
                id: nil,
                transcriptId: transcriptID,
                title: document.title,
                fileName: writtenFile.fileName,
                sourcePrompt: sourcePrompt,
                legacyAIResultId: nil,
                createdAt: createdAt,
                updatedAt: createdAt
            )
            try repo.insertMarkdownFile(&markdownFile)
            files.append(markdownFile)
        }

        return files
    }

    private func createdFilesReply(
        _ files: [TranscriptMarkdownFile],
        emptyFallback: String
    ) -> String {
        guard !files.isEmpty else { return emptyFallback }

        let names = files.map { "- \($0.title)" }.joined(separator: "\n")
        return "Created \(files.count) markdown file\(files.count == 1 ? "" : "s"):\n\(names)"
    }

    private func saveChatMessageAsMarkdown(_ message: TranscriptChatMessage) {
        guard let transcriptID = transcript.id else { return }

        do {
            let files = try saveMarkdownDocuments(
                from: message.content,
                fallbackTitle: "Chat Response",
                sourcePrompt: "Saved from transcript chat",
                transcriptID: transcriptID
            )
            loadMarkdownFiles(selecting: files.first?.id)
        } catch {
            aiError = error.localizedDescription
        }
    }

    private func saveChatMessage(
        role: TranscriptChatMessage.Role,
        content: String,
        transcriptID: Int64
    ) -> TranscriptChatMessage? {
        guard let repo = appState.repository else { return nil }
        var message = TranscriptChatMessage(
            id: nil,
            transcriptId: transcriptID,
            role: role,
            content: content,
            createdAt: Date()
        )

        do {
            try repo.saveChatMessage(&message)
            chatMessages.append(message)
            return message
        } catch {
            aiError = error.localizedDescription
            return nil
        }
    }

    private func clearChatMessages() {
        guard let transcriptID = transcript.id, let repo = appState.repository, !isAnyAIRunning else { return }
        try? repo.deleteChatMessages(transcriptId: transcriptID)
        chatMessages = []
        streamingAssistantText = ""
    }

    private func cancelActiveAI() {
        appState.aiService.cancelActiveTask()
        activeAITask?.cancel()
        activeAITask = nil
        isAIRunning = false
        streamingAssistantText = ""
    }

    private func openMarkdownFileSheet(_ file: TranscriptMarkdownFile) {
        documentSheetFile = file
        loadDocumentSheetContent(for: file)
        isDocumentSheetPresented = true
    }

    private func loadDocumentSheetContent(for file: TranscriptMarkdownFile) {
        do {
            documentSheetContent = try TranscriptMarkdownFileStorage.read(file)
            documentSheetMissing = false
        } catch {
            documentSheetContent = ""
            documentSheetMissing = true
        }
    }

    private func copySheetMarkdown() {
        guard !documentSheetMissing else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(documentSheetContent, forType: .string)
    }

    private func revealSheetMarkdown() {
        guard let file = documentSheetFile, !documentSheetMissing else { return }
        NSWorkspace.shared.activateFileViewerSelecting([TranscriptMarkdownFileStorage.url(for: file)])
    }

    private func exportSheetMarkdown() {
        guard let file = documentSheetFile, !documentSheetMissing else { return }
        let panel = NSSavePanel()
        panel.title = "Export Markdown File"
        panel.nameFieldStringValue = file.fileName
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            try? documentSheetContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func deleteSheetMarkdown() {
        guard let file = documentSheetFile, let id = file.id, let repo = appState.repository else { return }
        try? TranscriptMarkdownFileStorage.delete(file)
        try? repo.deleteMarkdownFile(id: id)
        isDocumentSheetPresented = false
        documentSheetFile = nil
        documentSheetContent = ""
        documentSheetMissing = false
        loadMarkdownFiles()
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
        guard appState.aiService.activeTaskTranscriptId == transcript.id || isAIRunning else {
            return nil
        }

        var components: [String] = []

        if let promptTitle = appState.aiService.activeTaskPromptTitle, !promptTitle.isEmpty {
            components.append(promptTitle)
        }

        if let status = appState.aiService.activeTaskStatus, !status.isEmpty {
            components.append(status)
        }

        guard !components.isEmpty else { return nil }
        return components.joined(separator: " · ")
    }
}

private struct MarkdownFileCard: View {
    let file: TranscriptMarkdownFile
    let onOpen: () -> Void

    private var exists: Bool {
        TranscriptMarkdownFileStorage.exists(file)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: exists ? "doc.text" : "exclamationmark.triangle")
                        .foregroundStyle(exists ? ColorTokens.textSecondary : ColorTokens.statusError)

                    Spacer()
                }

                Text(file.title)
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(ColorTokens.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(exists ? TimeFormatting.formattedDate(file.createdAt) : "Missing on disk")
                    .font(Typography.caption)
                    .foregroundStyle(exists ? ColorTokens.textMuted : ColorTokens.statusError)
                    .lineLimit(1)
            }
            .frame(height: 78)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ColorTokens.backgroundRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ColorTokens.border.opacity(0.65), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MarkdownFileSheet: View {
    let file: TranscriptMarkdownFile
    let content: String
    let isMissing: Bool
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(file.title)
                        .font(Typography.title)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .lineLimit(2)

                    Text(isMissing ? "Missing on disk" : file.fileName)
                        .font(Typography.caption)
                        .foregroundStyle(isMissing ? ColorTokens.statusError : ColorTokens.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                Button("Copy", action: onCopy)
                    .buttonStyle(.secondary)
                    .controlSize(.small)
                    .disabled(isMissing)

                Button("Reveal", action: onReveal)
                    .buttonStyle(.secondary)
                    .controlSize(.small)
                    .disabled(isMissing)

                Button("Export", action: onExport)
                    .buttonStyle(.secondary)
                    .controlSize(.small)
                    .disabled(isMissing)

                Button(isMissing ? "Remove Reference" : "Delete", action: onDelete)
                    .buttonStyle(.secondary)
                    .controlSize(.small)
            }
            .padding(Spacing.lg)

            Divider()
                .background(ColorTokens.border)

            ScrollView {
                Text(isMissing ? "This file is missing on disk." : content)
                    .font(Typography.body)
                    .foregroundStyle(isMissing ? ColorTokens.textMuted : ColorTokens.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.lg)
            }
            .background(ColorTokens.backgroundRaised)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 480, idealHeight: 560)
        .background(ColorTokens.backgroundBase)
    }
}

private struct TranscriptChatPanel: View {
    let messages: [TranscriptChatMessage]
    let promptTemplates: [AIPromptTemplate]
    @Binding var draft: String
    let streamingAssistantText: String
    let isRunning: Bool
    let statusMessage: String?
    let errorMessage: String?
    let onRunPreset: (AIPromptTemplate) -> Void
    let onOpenPromptSettings: () -> Void
    let onSend: () -> Void
    let onCancel: () -> Void
    let onClear: () -> Void
    let onCollapse: () -> Void
    let onSaveMessageAsMarkdown: (TranscriptChatMessage) -> Void

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .background(ColorTokens.border)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        if messages.isEmpty && streamingAssistantText.isEmpty {
                            Text("Ask a question about this transcript, or ask me to create Markdown notes.")
                                .font(Typography.body)
                                .foregroundStyle(ColorTokens.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Spacing.md)
                        }

                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            chatBubble(message)
                                .id(message.id)
                        }

                        if !streamingAssistantText.isEmpty {
                            assistantBubble(content: streamingAssistantText, isStreaming: true)
                                .id("streaming")
                        }
                    }
                    .padding(Spacing.md)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: streamingAssistantText) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()
                .background(ColorTokens.border)

            inputArea
        }
        .background(ColorTokens.backgroundBase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Transcript Chat")
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textPrimary)

                    Text("Local Gemma")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }

                Spacer()

                Button {
                    onClear()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.utility)
                .disabled(isRunning || messages.isEmpty)
                .help("Clear Chat")

                Button {
                    onCollapse()
                } label: {
                    Image(systemName: "sidebar.right")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.utility)
                .help("Collapse Chat")
            }

            presetChips

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
                    .lineLimit(2)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.statusError)
                    .lineLimit(3)
            }
        }
        .padding(Spacing.md)
    }

    private var presetChips: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text("Presets")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(ColorTokens.textMuted)

                Spacer()

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }

                Button {
                    onOpenPromptSettings()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.utility)
                .help("Manage AI Prompts")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(promptTemplates) { prompt in
                        Button {
                            onRunPreset(prompt)
                        } label: {
                            Label(prompt.title, systemImage: prompt.kind == .builtIn ? "sparkles" : "text.badge.plus")
                                .lineLimit(1)
                        }
                        .buttonStyle(.secondary)
                        .controlSize(.small)
                        .disabled(isRunning)
                    }
                }
            }
        }
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TextEditor(text: $draft)
                .font(Typography.body)
                .scrollContentBackground(.hidden)
                .padding(Spacing.sm)
                .frame(minHeight: 86, maxHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ColorTokens.backgroundRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ColorTokens.border.opacity(0.65), lineWidth: 1)
                )
                .disabled(isRunning)

            HStack(spacing: Spacing.sm) {
                if isRunning {
                    Button {
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.secondary)
                    .controlSize(.small)
                }

                Spacer()

                Button {
                    onSend()
                } label: {
                    Label(isRunning ? "Working..." : "Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.compactPrimary)
                .disabled(isRunning || trimmedDraft.isEmpty)
            }
        }
        .padding(Spacing.md)
    }

    private func chatBubble(_ message: TranscriptChatMessage) -> some View {
        Group {
            switch message.role {
            case .user:
                userBubble(content: message.content)
            case .assistant:
                assistantBubble(content: message.content, isStreaming: false, message: message)
            }
        }
    }

    private func userBubble(content: String) -> some View {
        HStack {
            Spacer(minLength: Spacing.lg)

            Text(content)
                .font(Typography.body)
                .foregroundStyle(ColorTokens.buttonPrimaryText)
                .textSelection(.enabled)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ColorTokens.buttonPrimary)
                )
        }
    }

    private func assistantBubble(
        content: String,
        isStreaming: Bool,
        message: TranscriptChatMessage? = nil
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(content)
                    .font(Typography.body)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .textSelection(.enabled)

                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else if let message {
                    Button {
                        onSaveMessageAsMarkdown(message)
                    } label: {
                        Label("Save as Markdown", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.secondary)
                    .controlSize(.small)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ColorTokens.backgroundRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ColorTokens.border.opacity(0.45), lineWidth: 1)
            )
            .padding(.trailing, Spacing.lg)

            Spacer(minLength: Spacing.lg)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if !streamingAssistantText.isEmpty {
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            } else if let id = messages.last?.id {
                withAnimation {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }
}
