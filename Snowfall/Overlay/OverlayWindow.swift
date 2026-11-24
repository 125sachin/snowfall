import AppKit

/// Borderless, transparent, click-through panel covering one display.
///
/// Level choice: `.floating` (3). It sits above normal app windows (0) but below the Dock (20),
/// menu bar (24), status items / our popover (25), modal alerts and the screen saver, so system UI
/// and security prompts are never covered. `.screenSaver` (1000) was rejected: it would draw over
/// the menu bar, Dock and alerts. Trade-off: other apps' floating panels share this level, so
/// snow may fall behind them. Validate on real displays; see docs/PERMISSIONS.md and TESTING.md.
///
/// Collection behaviour: `.canJoinAllSpaces` (appear on every Space), `.fullScreenAuxiliary`
/// (allowed alongside full-screen apps), `.stationary` (stays put during Mission Control /
/// Space transitions), `.ignoresCycle` (excluded from Cmd-`).
final class OverlayWindow: NSPanel {
    static let overlayLevel = NSWindow.Level.floating

    let displayID: UInt32

    init(display: DisplayDescriptor) {
        displayID = display.id
        super.init(contentRect: display.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        title = "Snowfall Overlay"
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Borderless windows are otherwise pushed below the menu bar; we want the exact display frame.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
