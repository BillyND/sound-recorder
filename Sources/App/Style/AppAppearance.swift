// The app's light / dark choice. Applied to NSApp, so every window (main, Settings and Sparkle's
// update windows) switches at once; "System" follows the Mac's setting.

import AppKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    private var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    @MainActor func apply() { NSApp?.appearance = nsAppearance }
}
