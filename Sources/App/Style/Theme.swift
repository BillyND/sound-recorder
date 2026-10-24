// The Sound Recorder look in one place: accent colors, corner radii, spacing, motion,
// the glass card and the window backdrop. Views use these tokens instead of literals.

import SwiftUI

enum Theme {
    static let brand = Color(red: 0.98, green: 0.30, blue: 0.42)
    static let brandDeep = Color(red: 0.86, green: 0.16, blue: 0.36)
    static let brandGradient = LinearGradient(colors: [brand, brandDeep], startPoint: .top, endPoint: .bottom)
    static let meterGradient = LinearGradient(colors: [.green, .yellow, .orange, brand], startPoint: .leading, endPoint: .trailing)
    static let warning = Color.orange

    enum Radius {
        static let card: CGFloat = 22
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

    enum Motion {
        static let hover = Animation.easeOut(duration: 0.12)
        static let notice = Animation.easeOut(duration: 0.2)
        static let select = Animation.spring(duration: 0.3)
        static let press = Animation.spring(duration: 0.2)
    }
}

extension Color {
    static let brand = Theme.brand
    static let brandDeep = Theme.brandDeep
}

extension View {
    /// Liquid Glass on macOS 26, a material card before that.
    @ViewBuilder func card(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Soft accent glow behind the glass, adapting to light and dark mode.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Theme.brand.opacity(0.20), .clear], center: .topLeading, startRadius: 0, endRadius: 460)
            RadialGradient(colors: [Theme.brandDeep.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}
