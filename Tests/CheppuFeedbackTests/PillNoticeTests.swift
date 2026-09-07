import AppKit
import Testing

@testable import CheppuCore
@testable import CheppuFeedback

// The Pill is one size in every state (`docs/product-experience.md` §3): one
// that grew for a message would be a shape that moved while it was being read.
// So the words it says have to fit the Pill it already is, and that is measured
// here rather than asserted in a comment — a notice that overflowed would be a
// Dictation whose one explanation was cut in half.
//
// Nothing here draws: text is measured, and no window is put on screen.
@Suite("What the Pill says fits the Pill")
struct PillNoticeTests {
    /// Every state the Pill writes rather than draws, which is every state that
    /// has words at all.
    private static let written: [PillState] =
        [.onTheClipboard] + Permission.allCases.map { .permissionMissing($0) }

    @Test("Every notice fits inside the Pill", arguments: written)
    func everyNoticeFitsInsideThePill(_ state: PillState) throws {
        let words = try #require(state.words)
        let room = PillPlacement.size.width - 2 * PillView.noticeInset

        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        centred.lineBreakMode = .byWordWrapping

        let notice = NSAttributedString(
            string: words,
            attributes: [
                .font: NSFont.systemFont(ofSize: PillView.noticeSize, weight: .medium),
                .paragraphStyle: centred,
            ]
        )
        let wrapped = notice.boundingRect(
            with: NSSize(width: room, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin
        )

        // Wrapping is allowed — "Cheppu needs Input Monitoring" is two lines —
        // but nothing may run off either edge of the capsule it is drawn on.
        #expect(wrapped.width <= room)
        #expect(wrapped.height <= PillPlacement.size.height)
    }
}
