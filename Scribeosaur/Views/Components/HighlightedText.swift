import SwiftUI

struct HighlightedText: View {
    let text: String
    let query: String
    let currentGlobalMatchIndex: Int
    let globalMatchOffset: Int

    var body: some View {
        if query.isEmpty {
            Text(text)
        } else {
            Text(attributedString)
        }
    }

    private var attributedString: AttributedString {
        var attributed = AttributedString(text)
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        guard !lowercasedQuery.isEmpty else { return attributed }

        var searchStart = lowercasedText.startIndex
        var localMatchIndex = 0

        while let range = lowercasedText.range(of: lowercasedQuery, range: searchStart..<lowercasedText.endIndex) {
            let attrStart = AttributedString.Index(range.lowerBound, within: attributed)
            let attrEnd = AttributedString.Index(range.upperBound, within: attributed)

            if let attrStart, let attrEnd {
                let globalIndex = globalMatchOffset + localMatchIndex
                if globalIndex == currentGlobalMatchIndex {
                    attributed[attrStart..<attrEnd].backgroundColor = Color.orange
                    attributed[attrStart..<attrEnd].foregroundColor = Color.black
                } else {
                    attributed[attrStart..<attrEnd].backgroundColor = Color.orange.opacity(0.3)
                }
            }

            localMatchIndex += 1
            searchStart = range.upperBound
        }

        return attributed
    }

    static func matchCount(in text: String, query: String) -> Int {
        guard !query.isEmpty else { return 0 }
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()
        var count = 0
        var searchStart = lowercasedText.startIndex

        while let range = lowercasedText.range(of: lowercasedQuery, range: searchStart..<lowercasedText.endIndex) {
            count += 1
            searchStart = range.upperBound
        }

        return count
    }
}
