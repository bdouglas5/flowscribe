import SwiftUI

struct SpeakerLabelingDialog: View {
    @Binding var isPresented: Bool
    @State private var speakerCount = 2
    @State private var speakerNames: [String] = ["", ""]
    var onConfirm: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Speaker Setup")
                .font(Typography.title)
                .foregroundStyle(ColorTokens.textPrimary)

            Text("Label the speakers before transcription begins.")
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textSecondary)

            HStack {
                Text("Number of speakers:")
                    .font(Typography.body)
                    .foregroundStyle(ColorTokens.textSecondary)

                Picker("", selection: $speakerCount) {
                    ForEach(1...10, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .frame(width: 60)
                .onChange(of: speakerCount) { _, newCount in
                    adjustSpeakerNames(to: newCount)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(0..<speakerCount, id: \.self) { index in
                    HStack {
                        Text("Speaker \(index + 1):")
                            .font(Typography.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .frame(width: 80, alignment: .trailing)

                        TextField("Name", text: binding(for: index))
                            .textFieldStyle(.plain)
                            .padding(Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(ColorTokens.backgroundBase)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ColorTokens.border, lineWidth: 1)
                            )
                    }
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.secondary)

                Button("Transcribe") {
                    let names = speakerNames.prefix(speakerCount).enumerated().map { index, name in
                        name.isEmpty ? "Speaker \(index + 1)" : name
                    }
                    onConfirm(names)
                    isPresented = false
                }
                .buttonStyle(.primary)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 400)
        .background(ColorTokens.backgroundFloat)
    }

    private func adjustSpeakerNames(to count: Int) {
        while speakerNames.count < count {
            speakerNames.append("")
        }
        if speakerNames.count > count {
            speakerNames = Array(speakerNames.prefix(count))
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < speakerNames.count ? speakerNames[index] : "" },
            set: { if index < speakerNames.count { speakerNames[index] = $0 } }
        )
    }
}
