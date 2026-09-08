import AppKit

/// Cheppu's menu bar icon: a text caret whose stem is a level meter.
///
/// Two rails hold the place where the words will land, and three bars between
/// them say that something is being heard. It is Cheppu's mark, and the numbers
/// below are the ones the README states in units of its 24-grid — rails 14 by
/// 2.4 at y 2 and y 19.6, bars 2.4 wide of heights 8, 13 and 8, every corner
/// radius half the short side. `docs/brand/cheppu-mark-template.svg` is the
/// same shape said in SVG; if one of them changes, both do.
///
/// Every part of it is a filled capsule rather than a stroked outline. A menu
/// bar is mostly thin outline glyphs, so a solid mark is the one that can be
/// found at a glance — which is what matters for an app whose whole interface
/// is this icon and the Pill.
///
/// It is drawn rather than shipped as an asset because `Scripts/make-app.sh`
/// assembles the bundle by hand and ADR-0003 rules out asset catalogues. Drawing
/// also means the shape is re-rendered at whatever scale the status bar asks for,
/// so it stays crisp on every display.
enum MenuBarIcon {
    /// The side of the square the icon is drawn in, in points. 18 is the size
    /// AppKit lays a status item image out at.
    private static let side: CGFloat = 18

    /// The mark's ink, in its own grid units: it spans x 5 to 19 and y 2 to 22,
    /// so 14 wide by 20 tall inside a 24-square. The rest of the square is the
    /// mark's clear space, which is not the icon's to keep — a status item is
    /// already given room by the menu bar around it.
    private static let ink = (x: CGFloat(5), y: CGFloat(2), width: CGFloat(14), height: CGFloat(20))

    /// Half a point of air above and below, so the rails do not sit on the
    /// icon's edge, and the mark is scaled to whatever is left. Its height is
    /// what fills the square; the width follows, and is centred.
    private static let air: CGFloat = 0.5
    private static let scale = (side - air * 2) / ink.height

    /// A template image, so AppKit tints it for the menu bar's appearance and
    /// for the highlight drawn while the menu is open. Cheppu never picks the
    /// colour itself. The mark is allowed one — terracotta, on the middle bar —
    /// and the menu bar is the one place it is not.
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            NSColor.black.setFill()
            mark().fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cheppu"
        return image
    }

    /// The mark as one path of five capsules: the two rails, then the meter.
    ///
    /// The bars are 8, 13 and 8 units tall and all three are centred on the same
    /// line, so the meter reads as one shape rather than as three things of
    /// different lengths — the rhythm the Pill draws while it listens, tallest
    /// in the middle. Nothing overlaps, so the path fills with the default
    /// winding rule and there is no knockout to keep clear of.
    private static func mark() -> NSBezierPath {
        let path = NSBezierPath()

        for y in [CGFloat(2), CGFloat(19.6)] {
            path.append(capsule(x: 5, y: y, width: 14, height: 2.4))
        }

        let bars: [(x: CGFloat, height: CGFloat)] = [(7.3, 8), (10.8, 13), (14.3, 8)]
        for bar in bars {
            path.append(capsule(x: bar.x, y: 12 - bar.height / 2, width: 2.4, height: bar.height))
        }

        return path
    }

    /// One capsule, given where the mark is drawn — in grid units, counting down
    /// from the top of the 24-square — and returned where AppKit draws, in
    /// points counting up from the bottom of the icon.
    private static func capsule(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSBezierPath {
        let left = (side - ink.width * scale) / 2
        let rect = NSRect(
            x: left + (x - ink.x) * scale,
            y: air + (ink.y + ink.height - y - height) * scale,
            width: width * scale,
            height: height * scale
        )
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}
