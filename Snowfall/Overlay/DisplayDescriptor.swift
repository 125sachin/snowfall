import AppKit

/// Value snapshot of a display. All rects are canonical global AppKit points (origin bottom-left
/// of the primary display, +y up). `scale` is the backing scale factor (pixels per point).
struct DisplayDescriptor: Identifiable, Equatable, Sendable {
    let id: UInt32
    let uuid: String
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let scale: CGFloat

    /// Ground block under the visible area (e.g. the Dock): its top edge is where snow settles.
    var bottomSurface: CollisionSurface {
        CollisionSurface(id: "display-\(uuid)",
                         frame: CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                                       height: max(0, visibleFrame.minY - frame.minY)),
                         velocity: .zero, kind: .displayBottom)
    }
}

extension DisplayDescriptor {
    @MainActor
    static func current() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(num.uint32Value)
            var uuid = "display-\(id)"
            if let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
               let s = CFUUIDCreateString(nil, u) as String? { uuid = s }
            return DisplayDescriptor(id: id, uuid: uuid, name: screen.localizedName, frame: screen.frame,
                                     visibleFrame: screen.visibleFrame, scale: screen.backingScaleFactor)
        }
    }
}

/// Unit-explicit coordinate helpers. AX and CoreGraphics use a top-left origin with y down,
/// anchored to the primary display; AppKit global space uses a bottom-left origin with y up.
enum CoordinateSpace {
    static func appKitRect(fromAXRect r: CGRect, primaryHeightPoints h: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }
    static func axRect(fromAppKitRect r: CGRect, primaryHeightPoints h: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }
    /// Rect relative to a display's own bottom-left origin (render-time conversion).
    static func displayLocalRect(fromGlobalPoints r: CGRect, display: CGRect) -> CGRect {
        r.offsetBy(dx: -display.minX, dy: -display.minY)
    }
    static func pixels(fromPoints points: CGFloat, scale: CGFloat) -> CGFloat { points * scale }
    static func points(fromPixels pixels: CGFloat, scale: CGFloat) -> CGFloat { pixels / scale }
}
