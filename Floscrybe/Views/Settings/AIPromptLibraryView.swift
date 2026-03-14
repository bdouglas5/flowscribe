import SwiftUI

struct AIPromptLibraryView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedPromptID: String?
    @State private var titleDraft = ""
    @State private var bodyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Picker("Prompt", selection: $selectedPromptID) {
                ForEach(appState.codexService.availablePromptTemplates) { prompt in
                    Text(prompt.title).tag(Optional(prompt.id))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedPromptID) { _, _ in
                loadSelectedPrompt()
            }

            if let selectedPrompt {
                if selectedPrompt.allowsTitleEditing {
                    TextField("Prompt Name", text: $titleDraft)
                        .textFieldStyle(.roundedBorder)
                } else {
                    LabeledContent("Prompt Name") {
                        Text(selectedPrompt.title)
                            .foregroundStyle(ColorTokens.textSecondary)
                    }
                }

                Text("Prompt Body")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)

                TextEditor(text: $bodyDraft)
                    .font(Typography.body)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.sm)
                    .frame(minHeight: 190)
                    .background(ColorTokens.backgroundRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: Spacing.sm) {
                    Button("Save Prompt") {
                        saveSelectedPrompt()
                    }
                    .buttonStyle(.primary)
                    .disabled(bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("New Custom Prompt") {
                        createPrompt()
                    }
                    .buttonStyle(.secondary)

                    Button("Delete Prompt") {
                        deleteSelectedPrompt()
                    }
                    .buttonStyle(.secondary)
                    .disabled(!selectedPrompt.isDeletable)

                    Spacer()
                }

                Text(helperText(for: selectedPrompt))
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
            } else {
                Text("No prompts available.")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
            }
        }
        .task {
            ensureSelection()
        }
        .onChange(of: appState.codexService.promptTemplates.map(\.id)) { _, _ in
            ensureSelection()
        }
    }

    private var selectedPrompt: AIPromptTemplate? {
        guard let selectedPromptID else { return nil }
        return appState.codexService.promptTemplates.first { $0.id == selectedPromptID }
    }

    private func helperText(for prompt: AIPromptTemplate) -> String {
        if prompt.kind == .builtIn {
            return "Built-in prompts can be edited, but not deleted."
        }
        return "Custom prompts appear in the AI menu for every transcript."
    }

    private func ensureSelection() {
        if let selectedPromptID,
           appState.codexService.promptTemplates.contains(where: { $0.id == selectedPromptID }) {
            loadSelectedPrompt()
            return
        }

        selectedPromptID = appState.codexService.availablePromptTemplates.first?.id
        loadSelectedPrompt()
    }

    private func loadSelectedPrompt() {
        guard let selectedPrompt else {
            titleDraft = ""
            bodyDraft = ""
            return
        }

        titleDraft = selectedPrompt.title
        bodyDraft = selectedPrompt.body
    }

    private func createPrompt() {
        let prompt = appState.codexService.createCustomPrompt()
        selectedPromptID = prompt.id
        titleDraft = prompt.title
        bodyDraft = prompt.body
    }

    private func saveSelectedPrompt() {
        guard let selectedPrompt else { return }

        let nextTitle: String
        if selectedPrompt.allowsTitleEditing {
            let trimmedTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            nextTitle = trimmedTitle.isEmpty ? selectedPrompt.title : trimmedTitle
        } else {
            nextTitle = selectedPrompt.title
        }

        let nextBody = bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextBody.isEmpty else { return }

        appState.codexService.savePrompt(AIPromptTemplate(
            id: selectedPrompt.id,
            title: nextTitle,
            body: nextBody,
            kind: selectedPrompt.kind
        ))
        titleDraft = nextTitle
        bodyDraft = nextBody
    }

    private func deleteSelectedPrompt() {
        guard let selectedPrompt else { return }
        appState.codexService.deletePrompt(id: selectedPrompt.id)
        selectedPromptID = appState.codexService.availablePromptTemplates.first?.id
        loadSelectedPrompt()
    }
}
