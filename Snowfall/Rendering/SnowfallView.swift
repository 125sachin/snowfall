import AppKit
import MetalKit

/// Transparent Metal view that never takes hit-testing.
final class SnowfallView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { false }

    func configureTransparency() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        (layer as? CAMetalLayer)?.isOpaque = false
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        autoResizeDrawable = false           // sized by `updateDrawableSize` (capped scale)
        enableSetNeedsDisplay = false
        (layer as? CAMetalLayer)?.maximumDrawableCount = 2   // default 3 = a full extra screen buffer
        updateDrawableSize()
    }

    /// Renders at the display's native scale so flakes stay crisp. (An earlier 1.5x cap saved
    /// memory but made the snow look blurry.)
    var renderScaleCap: CGFloat = 3 { didSet { updateDrawableSize() } }

    /// While the overlay is hidden (covered by a full-screen app, or snow is off) the drawables are
    /// shrunk to 1x1 so the buffers are returned to the system, then restored when it reappears.
    var releaseDrawables = false { didSet { if oldValue != releaseDrawables { updateDrawableSize() } } }

    func updateDrawableSize() {
        if releaseDrawables {
            if drawableSize != CGSize(width: 1, height: 1) { drawableSize = CGSize(width: 1, height: 1) }
            return
        }
        let native = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let s = max(1, min(native, renderScaleCap))
        let size = CGSize(width: max(1, (bounds.width * s).rounded()), height: max(1, (bounds.height * s).rounded()))
        if drawableSize != size { drawableSize = size }
    }

    override func layout() { super.layout(); updateDrawableSize() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateDrawableSize() }
}
