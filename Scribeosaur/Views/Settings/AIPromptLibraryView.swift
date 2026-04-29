import SwiftUI

struct AIPromptLibraryView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedPromptID: String?
    @State private var titleDraft = ""
    @State private var bodyDraft = ""
    @State private var autosaveTask: Task<Void, Never>?
    @State private var saveState: PromptSaveState = .saved

    var body: some View {
        HSplitView {
            promptListPane
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

            editorPane
                .frame(minWidth: 420, idealWidth: 520, maxWidth: .infinity)
        }
        .frame(minHeight: 400)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(ColorTokens.backgroundRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ColorTokens.border.opacity(0.65), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task {
            ensureSelection()
        }
        .onDisappear {
            autosaveTask?.cancel()
        }
        .onChange(of: selectedPromptID) { _, _ in
            autosaveTask?.cancel()
            loadSelectedPrompt()
        }
        .onChange(of: titleDraft) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: bodyDraft) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: appState.aiService.promptTemplates.map(\.id)) { _, _ in
            ensureSelection()
        }
    }

    private var promptListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textPrimary)

                    Text("Built-in and custom prompts")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }

                Spacer()

                Button("New Prompt") {
                    createPrompt()
                }
                .buttonStyle(.secondary)
                .controlSize(.small)
            }
            .padding(Spacing.md)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if !builtInPrompts.isEmpty {
                        promptGroup(title: "Built In", prompts: builtInPrompts)
                    }

                    if !customPrompts.isEmpty {
                        promptGroup(title: "Custom", prompts: customPrompts)
                    }
                }
                .padding(Spacing.md)
            }
            .background(ColorTokens.backgroundRaised)
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let selectedPrompt {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(selectedPrompt.kind == .builtIn ? "Built-In Prompt" : "Custom Prompt")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)

                        if selectedPrompt.allowsTitleEditing {
                            TextField("Prompt Name", text: $titleDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(Typography.title)
                        } else {
                            Text(selectedPrompt.title)
                                .font(Typography.title)
                                .foregroundStyle(ColorTokens.textPrimary)
                        }
                    }

                    Spacer(minLength: Spacing.md)

                    VStack(alignment: .trailing, spacing: Spacing.sm) {
                        saveStateBadge

                        if selectedPrompt.isDeletable {
                            Button("Delete Prompt") {
                                deleteSelectedPrompt()
                            }
                            .buttonStyle(.secondary)
                            .controlSize(.small)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Instructions")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)

                    TextEditor(text: $bodyDraft)
                        .font(Typography.body)
                        .scrollContentBackground(.hidden)
                        .padding(Spacing.sm)
                        .frame(minHeight: 280)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(ColorTokens.backgroundFloat)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(ColorTokens.border.opacity(0.65), lineWidth: 1)
                        )
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("No prompt selected")
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textPrimary)

                    Text("Choose a built-in prompt or create a custom one to shape how AI responds to your transcripts.")
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ColorTokens.backgroundBase)
    }

    @ViewBuilder
    private func promptGroup(title: String, prompts: [AIPromptTemplate]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(ColorTokens.textMuted)

            ForEach(prompts) { prompt in
                promptRow(prompt)
            }
        }
    }

    private func promptRow(_ prompt: AIPromptTemplate) -> some View {
        Button {
            selectedPromptID = prompt.id
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.title)
                        .font(Typography.body.weight(.medium))
                        .foregroundStyle(ColorTokens.textPrimary)

                    Text(prompt.kind == .builtIn ? "Built-in" : "Custom")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }

                Spacer()

                if prompt.kind == .builtIn {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedPromptID == prompt.id ? ColorTokens.backgroundFloat : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selectedPromptID == prompt.id
                            ? ColorTokens.border.opacity(0.75)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var builtInPrompts: [AIPromptTemplate] {
        appState.aiService.availablePromptTemplates.filter { $0.kind == .builtIn }
    }

    private var customPrompts: [AIPromptTemplate] {
        appState.aiService.availablePromptTemplates.filter { $0.kind == .custom }
    }

    private var selectedPrompt: AIPromptTemplate? {
        guard let selectedPromptID else { return nil }
        return appState.aiService.promptTemplates.first { $0.id == selectedPromptID }
    }

    private var saveStateBadge: some View {
        Text(saveState.label)
            .font(Typography.caption)
            .foregroundStyle(ColorTokens.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(saveState.color)
            .clipShape(Capsule())
    }

    private func ensureSelection() {
        if let selectedPromptID,
           appState.aiService.promptTemplates.contains(where: { $0.id == selectedPromptID }) {
            loadSelectedPrompt()
            return
        }

        selectedPromptID = appState.aiService.availablePromptTemplates.first?.id
        loadSelectedPrompt()
    }

    private func loadSelectedPrompt() {
        guard let selectedPrompt else {
            titleDraft = ""
            bodyDraft = ""
            saveState = .saved
            return
        }

        titleDraft = selectedPrompt.title
        bodyDraft = selectedPrompt.body
        saveState = .saved
    }

    private func createPrompt() {
        let prompt = appState.aiService.createCustomPrompt()
        selectedPromptID = prompt.id
        titleDraft = prompt.title
        bodyDraft = prompt.body
        saveState = .saved
    }

    private func scheduleAutosave() {
        guard let selectedPrompt else { return }

        let normalizedTitle = normalizedTitle(for: selectedPrompt)
        let normalizedBody = normalizedBody()

        if normalizedBody.isEmpty {
            saveState = .needsContent
            autosaveTask?.cancel()
            return
        }

        guard normalizedTitle != selectedPrompt.title || normalizedBody != selectedPrompt.body else {
            saveState = .saved
            autosaveTask?.cancel()
            return
        }

        saveState = .saving
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            persistSelection()
        }
    }

    private func persistSelection() {
        guard let selectedPrompt else { return }

        let nextBody = normalizedBody()
        guard !nextBody.isEmpty else {
            saveState = .needsContent
            return
        }

        let nextTitle = normalizedTitle(for: selectedPrompt)

        appState.aiService.savePrompt(AIPromptTemplate(
            id: selectedPrompt.id,
            title: nextTitle,
            body: nextBody,
            kind: selectedPrompt.kind
        ))

        titleDraft = nextTitle
        bodyDraft = nextBody
        saveState = .saved
    }

    private func deleteSelectedPrompt() {
        guard let selectedPrompt, selectedPrompt.isDeletable else { return }
        autosaveTask?.cancel()
        appState.aiService.deletePrompt(id: selectedPrompt.id)
        selectedPromptID = appState.aiService.availablePromptTemplates.first?.id
        loadSelectedPrompt()
    }

    private func normalizedTitle(for prompt: AIPromptTemplate) -> String {
        if prompt.allowsTitleEditing {
            let trimmedTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedTitle.isEmpty ? prompt.title : trimmedTitle
        }
        return prompt.title
    }

    private func normalizedBody() -> String {
        bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum PromptSaveState {
    case saving
    case saved
    case needsContent

    var label: String {
        switch self {
        case .saving: "Saving…"
        case .saved: "Saved"
        case .needsContent: "Body required"
        }
    }

    var color: Color {
        switch self {
        case .saving:
            ColorTokens.backgroundHover
        case .saved:
            ColorTokens.progressFill
        case .needsContent:
            ColorTokens.statusError
        }
    }
}
