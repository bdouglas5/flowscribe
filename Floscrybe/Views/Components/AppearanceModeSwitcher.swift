import SwiftUI

struct AppearanceModeSwitcher: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        HStack(spacing: Spacing.xs) {
            ForEach(AppSettings.AppearanceMode.allCases, id: \.self) { mode in
                Button {
                    settings.appearanceMode = mode
                } label: {
                    Image(systemName: icon(for: mode))
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    settings.appearanceMode == mode
                        ? ColorTokens.buttonPrimaryText
                        : ColorTokens.textMuted
                )
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            settings.appearanceMode == mode
                                ? ColorTokens.buttonPrimary
                                : Color.clear
                        )
                )
                .help(mode.displayName)
            }
        }
    }

    private func icon(for mode: AppSettings.AppearanceMode) -> String {
        switch mode {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}
