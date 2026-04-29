import SwiftUI

struct CategoryFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedCategory: TranscriptCategory
    @Binding var selectedDateFilter: DateFilter
    var matchCount: Int = 0
    var currentMatchIndex: Int = 0
    var onPreviousMatch: (() -> Void)?
    var onNextMatch: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Search field
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
                TextField("Search transcripts...", text: $searchText)
                    .font(Typography.body)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty && matchCount > 0 {
                    Text("\(currentMatchIndex + 1)/\(matchCount)")
                        .font(Typography.mono)
                        .foregroundStyle(ColorTokens.textMuted)
                        .fixedSize()

                    Button { onPreviousMatch?() } label: {
                        Image(systemName: "chevron.up")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button { onNextMatch?() } label: {
                        Image(systemName: "chevron.down")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ColorTokens.backgroundFloat)
            )

            // Source category chips (wrapping flow layout)
            FlowLayout(spacing: Spacing.xs) {
                ForEach(TranscriptCategory.allCases) { category in
                    FilterChip(
                        label: category.displayName,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                    .fixedSize()
                }
            }

            // Date filters (plain text, no background)
            FlowLayout(spacing: Spacing.md) {
                ForEach(DateFilter.allCases) { filter in
                    Button { selectedDateFilter = filter } label: {
                        Text(filter.displayName)
                            .font(Typography.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(
                                selectedDateFilter == filter
                                    ? ColorTokens.textPrimary
                                    : ColorTokens.textMuted
                            )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.md)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
            subviews: subviews
        )
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = currentY + rowHeight
        }

        return ArrangementResult(
            positions: positions,
            size: CGSize(width: maxWidth, height: totalHeight)
        )
    }

    private struct ArrangementResult {
        let positions: [CGPoint]
        let size: CGSize
    }
}
