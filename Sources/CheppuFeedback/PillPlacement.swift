import CoreGraphics

/// Where the Pill sits while a Dictation runs.
///
/// It has one place: the bottom of the screen, in the middle, a little above
/// whatever the Dock is doing. The Pill is read out of the corner of an eye
/// that is on the work (`docs/product-experience.md` §3), and something that
/// appeared somewhere different every time would have to be looked for
/// instead — which is the one thing it cannot cost the user.
///
/// The only thing that ever moves it is the thing it would otherwise cover. A
/// chat box, a terminal prompt and a search field all sit exactly where the
/// Pill rests, and a Pill over one of them would answer "can it hear me?" by
/// hiding the answer to "what did it write?". So when the field being dictated
/// into is in the way the Pill steps clear of it, straight up, and stays
/// horizontally where it always is: one axis of movement is something the eye
/// follows, and two is something it has to search.
enum PillPlacement {
    /// How big the Pill is. Wide enough for a level that can be read at a
    /// glance and small enough to be nothing but a glance.
    static let size = CGSize(width: 132, height: 40)

    /// How far above the bottom of the screen the Pill rests.
    ///
    /// Measured against the visible frame, which already has the Dock taken
    /// off it, so this is clearance from the Dock rather than clearance over
    /// it.
    static let restingAboveTheBottom: CGFloat = 24

    /// How much of a gap is kept between the Pill and the field it is stepping
    /// clear of. Touching the field is still covering the line under it.
    static let clearOfTheField: CGFloat = 12

    /// Where to put the Pill on `screen`, given where the user is typing.
    ///
    /// - Parameters:
    ///   - screen: the visible frame of the screen the Pill belongs on, in
    ///     screen coordinates — the y axis points up, and a display left of or
    ///     below the built-in one has negative ones.
    ///   - keepClearOf: what the Pill would rather not cover, widest first: the
    ///     field being dictated into, and then the text cursor inside it. Empty
    ///     where the app could not say, which is the ordinary answer for an app
    ///     that does not describe its text — and the Pill rests where it always
    ///     does.
    ///
    ///     Widest first, and the first one it can honour wins. Keeping clear of
    ///     the whole field is what the user wants: it is the thing they are
    ///     reading as well as writing. But a field can be the whole screen —
    ///     an editor filling a window — and there is no clearing that. Rather
    ///     than give up and sit in the middle of their document, the Pill steps
    ///     clear of the line they are actually typing on, which is the part of
    ///     it that must never be covered.
    static func place(on screen: CGRect, keepingClearOf keepClearOf: [CGRect]) -> CGRect {
        let home = CGRect(
            x: screen.midX - size.width / 2,
            y: screen.minY + restingAboveTheBottom,
            width: size.width,
            height: size.height
        )

        for toKeepClearOf in keepClearOf {
            // Grown by the gap before anything is asked of it, which does two
            // things at once: it is what keeps the Pill off the line under the
            // field, and it gives a text cursor — a caret one point wide, which
            // is what many apps answer with — enough body to be in the way at
            // all. An empty rectangle intersects nothing.
            let keptClear = toKeepClearOf.insetBy(dx: -clearOfTheField, dy: -clearOfTheField)

            // Already clear of the widest thing on the list, so it is clear of
            // everything inside it too. This is the ordinary case: the user is
            // typing somewhere up in a document, and the Pill stays home.
            guard home.intersects(keptClear) else { return home }

            let above = home.offsetBy(dx: 0, dy: keptClear.maxY - home.minY)
            if above.maxY <= screen.maxY { return above }

            let below = home.offsetBy(dx: 0, dy: keptClear.minY - home.maxY)
            if below.minY >= screen.minY { return below }

            // No room either side of this one. Whatever is next on the list is
            // smaller and inside it, so it may yet be steppable clear of.
        }

        // Nothing on the list could be cleared without leaving the screen, or
        // there was nothing on it. The Pill goes home rather than off the edge:
        // a user who cannot see it has no way of knowing Cheppu is listening,
        // which is worse than a corner of their text being covered for as long
        // as they speak.
        return home
    }
}
