import AppKit
import ApplicationServices
import CoreGraphics

/// The field being dictated into, as the Accessibility API answers it.
///
/// Cheppu is already trusted for Accessibility — it is what lets the Hotkey be
/// seen from inside another app — so this asks nothing of the user that a
/// Dictation had not already asked for. Where the grant is missing the question
/// simply goes unanswered, and the Pill rests where it always does.
///
/// It answers with both the field and the text cursor inside it, widest first,
/// and leaves `PillPlacement` to decide how much of that it can honour. Which
/// one matters depends on how big the field turns out to be — a search box is
/// worth stepping clear of whole, and an editor filling the window can only be
/// stepped clear of a line at a time — and that is a decision, so it does not
/// live here.
///
/// There is no seam in front of this and nothing here is tested. Every part of
/// it is another app answering a question about a screen, and what is decided
/// with the answer — `PillPlacement` — was taken out and tested on its own.
struct FocusedField: Sendable {
    /// How long another app is given to answer.
    ///
    /// The question is asked once, on the way into a Dictation, and the Pill is
    /// not shown until it is answered — so a hung app must not be able to hold
    /// the Pill back for longer than a blink. A responsive app answers in
    /// single-digit milliseconds.
    private static let whileTheAppAnswers: Float = 0.1

    /// What the Pill should keep clear of, in screen coordinates, widest
    /// first: the field being dictated into and the text cursor inside it.
    ///
    /// Empty is an ordinary answer rather than a failure. Plenty of apps do not
    /// describe their text to the Accessibility API at all, and the Pill's
    /// resting place is the right answer for every one of them.
    func whatToKeepClearOf() async -> [CGRect] {
        // Off the main thread on purpose: an Accessibility call blocks until
        // the other app replies or the timeout runs out, and the main thread is
        // where every app on the machine's menu bar is drawn.
        let asking = Task.detached(priority: .userInitiated, operation: Self.ask)
        let asTheApiMeasuresThem = await asking.value
        guard !asTheApiMeasuresThem.isEmpty else { return [] }

        // The Accessibility API measures from the top of the primary screen
        // downwards and AppKit measures from the bottom of it upwards. The same
        // rectangle in the wrong one of those is the Pill placed as far from
        // where the user is typing as it is possible to be.
        let primaryScreen = await MainActor.run { NSScreen.screens.first?.frame ?? .zero }
        return asTheApiMeasuresThem.map { measured in
            CGRect(
                x: measured.minX,
                y: primaryScreen.maxY - measured.maxY,
                width: measured.width,
                height: measured.height
            )
        }
    }

    /// The field and the cursor in it, as the API measures them: from the top
    /// of the primary screen down.
    @Sendable private static func ask() -> [CGRect] {
        let wholeMachine = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(wholeMachine, whileTheAppAnswers)

        guard let field = element(kAXFocusedUIElementAttribute, of: wholeMachine) else { return [] }
        return [frame(of: field), textCursor(in: field)].compactMap { $0 }
    }

    /// Where the text cursor is, for an app that can say.
    private static func textCursor(in field: AXUIElement) -> CGRect? {
        guard let selection = attribute(kAXSelectedTextRangeAttribute, of: field) else { return nil }

        var bounds: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                field,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                selection,
                &bounds
            ) == .success,
            let cursor: CGRect = measurement(bounds, .cgRect),
            // A cursor with no height is an app answering the question without
            // knowing the answer, which is worth less than the field it is in.
            cursor.height > 0
        else {
            return nil
        }
        return cursor
    }

    /// Where the whole field is, for an app that cannot place the cursor in it.
    private static func frame(of field: AXUIElement) -> CGRect? {
        guard
            let corner: CGPoint = measurement(attribute(kAXPositionAttribute, of: field), .cgPoint),
            let size: CGSize = measurement(attribute(kAXSizeAttribute, of: field), .cgSize)
        else {
            return nil
        }
        return CGRect(origin: corner, size: size)
    }

    private static func attribute(_ named: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, named as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func element(_ named: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(named, of: element),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    /// One geometric answer, unwrapped from the box the API returns it in.
    ///
    /// The type is checked rather than assumed: an app is free to answer with
    /// anything at all, and reading a point out of something that is not one
    /// would not be a wrong Pill position but a crash in Cheppu.
    private static func measurement<Measurement>(
        _ value: CFTypeRef?,
        _ kind: AXValueType
    ) -> Measurement? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        let measurement = UnsafeMutablePointer<Measurement>.allocate(capacity: 1)
        defer { measurement.deallocate() }
        guard AXValueGetValue((value as! AXValue), kind, measurement) else { return nil }
        return measurement.pointee
    }
}
