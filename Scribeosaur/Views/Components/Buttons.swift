import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.headline)
            .foregroundStyle(isEnabled ? ColorTokens.buttonPrimaryText : ColorTokens.textMuted)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? ColorTokens.buttonPrimary : ColorTokens.buttonSecondary)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.headline)
            .foregroundStyle(ColorTokens.buttonSecondaryText)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(ColorTokens.buttonSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ColorTokens.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

struct CompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body.weight(.semibold))
            .foregroundStyle(isEnabled ? ColorTokens.buttonPrimaryText : ColorTokens.textMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEnabled ? ColorTokens.buttonPrimary : ColorTokens.buttonSecondary)
            )
            .opacity(configuration.isPressed ? 0.86 : 1.0)
    }
}

struct UtilityButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body.weight(.medium))
            .foregroundStyle(isEnabled ? ColorTokens.textSecondary : ColorTokens.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? ColorTokens.backgroundHover : Color.clear)
            )
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == CompactPrimaryButtonStyle {
    static var compactPrimary: CompactPrimaryButtonStyle { CompactPrimaryButtonStyle() }
}

extension ButtonStyle where Self == UtilityButtonStyle {
    static var utility: UtilityButtonStyle { UtilityButtonStyle() }
}
