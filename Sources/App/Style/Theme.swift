// The Sound Recorder look in one place: semantic colours with light and dark values, corner radii,
// spacing, motion and the opaque card. Views use these tokens and never literal colours.
// Text colours meet WCAG AA on every surface they are used on (body text ≥ 4.5:1, controls ≥ 3:1).

import AppKit
import SwiftUI

enum Theme {
    // Surfaces, from back to front.
    static let background = Color(light: 0xF4F4F6, dark: 0x151517)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1F1F22)
    static let surfaceRaised = Color(light: 0xEEEEF2, dark: 0x2A2A2E)
    static let border = Color(light: 0xDEDEE4, dark: 0x34343A)
    static let shadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.06, darkAlpha: 0.30)

    // Text.
    static let textPrimary = Color(light: 0x1C1C1F, dark: 0xF2F2F5)
    static let textSecondary = Color(light: 0x5C5C66, dark: 0xA6A6B0)

    // Accent: `accent` for text and icons, `accentFill` behind white (`onAccent`) glyphs.
    static let accent = Color(light: 0xC42448, dark: 0xFF6B86)
    static let accentFill = Color(light: 0xC42448, dark: 0xCF2B50)
    static let accentSoft = Color(light: 0xFBE4E9, dark: 0x3A2228)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0xFFFFFF)

    // Status.
    static let warning = Color(light: 0x9A5800, dark: 0xFFB547)
    static let danger = Color(light: 0xC62828, dark: 0xFF6B6B)

    // Level meter: track, then low → mid → high.
    static let meterTrack = Color(light: 0xE6E6EB, dark: 0x34343A)
    static let meterLow = Color(light: 0x23863F, dark: 0x3FCF6E)
    static let meterMid = Color(light: 0xB07800, dark: 0xF0B429)
    static let meterHigh = Color(light: 0xC42448, dark: 0xFF6B86)
    static let meterGradient = LinearGradient(colors: [meterLow, meterMid, meterHigh], startPoint: .leading, endPoint: .trailing)

    enum Radius {
        static let card: CGFloat = 20
        static let notice: CGFloat = 14
        static let row: CGFloat = 10
        static let badge: CGFloat = 8
    }

    enum Spacing {
        static let windowInset: CGFloat = 20   // left and right of the main window content
        static let stack: CGFloat = 14         // between cards
        static let cardPadding: CGFloat = 12
        static let scrollerGutter: CGFloat = 10 // room for the overlay scroller beside list rows
    }

    /// Short, consistent curves; views apply them through `calmAnimation`, which honours Reduce Motion.
    enum Motion {
        static let standard = Animation.easeInOut(duration: 0.2)
        static let quick = Animation.easeOut(duration: 0.15)
    }
}

extension Color {
    /// A colour that follows the window's light or dark appearance, from 0xRRGGBB values.
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension View {
    /// An opaque card: surface fill, 1 px border and a very light shadow on the shape only
    /// (not on the content, so text and icons inside cast no shadows of their own).
    func card(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            shape.fill(Theme.surface)
                .shadow(color: Theme.shadow, radius: 4, y: 1)
                .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
        }
    }
}

/// Solid window background.
struct Backdrop: View {
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}
