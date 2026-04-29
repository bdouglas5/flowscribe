import AppKit
import SwiftUI

enum ColorTokens {
    // MARK: - Backgrounds (warm beige in light mode)
    static let backgroundBase = adaptiveRGB(lightR: 0.95, lightG: 0.94, lightB: 0.92, dark: 0.07)
    static let backgroundRaised = adaptiveRGB(lightR: 1.00, lightG: 0.99, lightB: 0.98, dark: 0.11)
    static let backgroundFloat = adaptiveRGB(lightR: 0.97, lightG: 0.96, lightB: 0.95, dark: 0.15)
    static let backgroundHover = adaptiveRGB(lightR: 0.93, lightG: 0.92, lightB: 0.90, dark: 0.18)

    // MARK: - Text
    static let textPrimary = adaptive(light: 0.10, dark: 0.93)
    static let textSecondary = adaptive(light: 0.35, dark: 0.70)
    static let textMuted = adaptive(light: 0.55, dark: 0.45)

    // MARK: - Border
    static let border = adaptive(light: 0.82, dark: 0.20)

    // MARK: - Buttons
    static let buttonPrimary = adaptive(light: 0.12, dark: 0.90)
    static let buttonPrimaryText = adaptive(light: 0.95, dark: 0.07)
    static let buttonSecondary = adaptive(light: 0.88, dark: 0.18)
    static let buttonSecondaryText = adaptive(light: 0.12, dark: 0.90)

    // MARK: - Semantic
    static let statusError = Color(red: 0.75, green: 0.25, blue: 0.25)

    // MARK: - Selection
    static let selectionBackground = adaptive(light: 0.85, dark: 0.22)

    // MARK: - Progress
    static let progressTrack = adaptive(light: 0.88, dark: 0.15)
    static let progressFill = adaptive(light: 0.45, dark: 0.60)

    // MARK: - Accent
    static let accentBlue = adaptiveRGB(
        lightR: 0.25, lightG: 0.47, lightB: 0.85,
        darkR: 0.40, darkG: 0.60, darkB: 0.95
    )
    static let accentBlueSubtle = adaptiveRGB(
        lightR: 0.90, lightG: 0.93, lightB: 1.0,
        darkR: 0.12, darkG: 0.14, darkB: 0.20
    )
    static let startupGlowPrimary = adaptiveRGB(
        lightR: 0.96, lightG: 0.72, lightB: 0.48,
        darkR: 0.72, darkG: 0.46, darkB: 0.22
    )
    static let startupGlowSecondary = adaptiveRGB(
        lightR: 0.89, lightG: 0.56, lightB: 0.40,
        darkR: 0.58, darkG: 0.34, darkB: 0.27
    )
    static let startupGlowTertiary = adaptiveRGB(
        lightR: 0.86, lightG: 0.80, lightB: 0.64,
        darkR: 0.42, darkG: 0.40, darkB: 0.28
    )
    static let startupTrack = adaptiveRGB(
        lightR: 0.90, lightG: 0.86, lightB: 0.80,
        darkR: 0.17, darkG: 0.16, darkB: 0.14
    )
    static let startupTrackBorder = adaptiveRGB(
        lightR: 0.80, lightG: 0.75, lightB: 0.70,
        darkR: 0.24, darkG: 0.23, darkB: 0.20
    )
    static let startupCard = adaptiveRGB(
        lightR: 1.00, lightG: 0.98, lightB: 0.96,
        darkR: 0.12, darkG: 0.11, darkB: 0.10
    )
    static let startupCardBorder = adaptiveRGB(
        lightR: 0.84, lightG: 0.80, lightB: 0.76,
        darkR: 0.24, darkG: 0.22, darkB: 0.20
    )

    private static func adaptive(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(white: value, alpha: 1)
        })
    }

    private static func adaptiveRGB(lightR: CGFloat, lightG: CGFloat, lightB: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if isDark {
                return NSColor(white: dark, alpha: 1)
            } else {
                return NSColor(red: lightR, green: lightG, blue: lightB, alpha: 1)
            }
        })
    }

    private static func adaptiveRGB(lightR: CGFloat, lightG: CGFloat, lightB: CGFloat, darkR: CGFloat, darkG: CGFloat, darkB: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if isDark {
                return NSColor(red: darkR, green: darkG, blue: darkB, alpha: 1)
            } else {
                return NSColor(red: lightR, green: lightG, blue: lightB, alpha: 1)
            }
        })
    }
}
