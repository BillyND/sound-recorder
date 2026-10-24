// Slim overlay scrollers that show only while scrolling, even when "Show scroll bars" is set to
// Automatically and a mouse is attached (which would otherwise give thick, always-visible bars).
// SwiftUI's ScrollView is an NSScrollView underneath; a zero-size probe inside the scrolled content
// finds it and switches its scroller style, again whenever the system preference changes.

import AppKit
import SwiftUI

private struct ScrollerStyleProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ view: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyOverlayStyle()
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                // AppKit resets the style on this notification; apply ours after it has done so.
                DispatchQueue.main.async { self?.applyOverlayStyle() }
            }
        }

        private func applyOverlayStyle() {
            guard let scrollView = enclosingScrollView, scrollView.scrollerStyle != .overlay else { return }
            scrollView.scrollerStyle = .overlay
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

extension View {
    /// Use on the content inside a ScrollView.
    func overlayScrollers() -> some View {
        background(ScrollerStyleProbe().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
