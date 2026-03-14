import SwiftUI

enum Typography {
    static let largeTitle = Font.system(size: 24, weight: .bold, design: .default)
    static let title = Font.system(size: 18, weight: .semibold, design: .default)
    static let headline = Font.system(size: 14, weight: .semibold, design: .default)
    static let body = Font.system(size: 13, weight: .regular, design: .default)
    static let caption = Font.system(size: 11, weight: .regular, design: .default)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
}
