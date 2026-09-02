import AppKit

/// Cheppu's menu bar icon: a speech bubble with a level meter cut out of it.
///
/// The icon is a solid silhouette on purpose. A menu bar is mostly thin outline
/// glyphs, so a filled shape is the one that can be found at a glance — which is
/// what matters for an app whose whole interface is this icon and the Pill.
///
/// It is drawn rather than shipped as an asset because `Scripts/make-app.sh`
/// assembles the bundle by hand and ADR-0003 rules out asset catalogues. Drawing
/// also means the shape is re-rendered at whatever scale the status bar asks for,
/// so it stays crisp on every display.
enum MenuBarIcon {
    /// The side of the square the icon is drawn in, in points. 18 is the size
    /// AppKit lays a status item image out at.
    private static let side: CGFloat = 18

    /// A template image, so AppKit tints it for the menu bar's appearance and
    /// for the highlight drawn while the menu is open. Cheppu never picks the
    /// colour itself.
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let (bubble, tail) = paths()
            NSColor.black.setFill()
            bubble.fill()
            tail.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cheppu"
        return image
    }

    /// The bubble carries the bars as a second subpath and is filled even-odd,
    /// which knocks them out of it. The tail is a separate fill laid over the
    /// bubble; it stays clear of the bars so that filling it cannot fill one
    /// back in.
    private static func paths() -> (bubble: NSBezierPath, tail: NSBezierPath) {
        let bubble = NSBezierPath(
            roundedRect: NSRect(x: 0.5, y: 5.5, width: 17, height: 12),
            xRadius: 4,
            yRadius: 4
        )
        for (x, height) in [(4.0, 5.0), (8.0, 7.5), (12.0, 5.0)] {
            let bar = NSRect(x: x, y: 11.5 - height / 2, width: 2, height: height)
            bubble.append(NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1))
        }
        bubble.windingRule = .evenOdd

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 2, y: 7))
        tail.line(to: NSPoint(x: 7, y: 7))
        tail.line(to: NSPoint(x: 2, y: 1))
        tail.close()

        return (bubble, tail)
    }
}
