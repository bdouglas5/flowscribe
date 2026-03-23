import SwiftUI

struct FilterChip<Icon: View>: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    let icon: Icon?

    init(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                if let icon {
                    icon
                }
                Text(label)
                    .font(Typography.caption)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(isSelected ? ColorTokens.buttonPrimaryText : ColorTokens.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? ColorTokens.buttonPrimary : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

extension FilterChip where Icon == EmptyView {
    init(label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
        self.icon = nil
    }
}
