import AppKit
import CheppuCore

/// What the Pill looks like.
///
/// Three states, drawn so that they cannot be confused at a glance from the far
/// side of a screen (`docs/product-experience.md` §3).
///
/// Listening is a row of bars that move with the voice. The question the user
/// is actually asking is "can it hear me right now?", and only something that
/// moves with what they are saying answers it — a static icon says the app is
/// switched on, which they already knew.
///
/// Transcribing is a single mark sweeping from one end of the Pill to the
/// other. It has to differ in shape rather than in colour or in speed, because
/// the state it is most likely to be mistaken for is a Dictation listening to
/// silence — and at silence the bars are at rest. Upright marks that move with
/// a voice, against one lying flat that travels on its own, is a difference the
/// eye reads without being looked at. That it moves at all is the other half:
/// what this state exists to prevent is a pause being read as a hang.
///
/// The Clipboard Fallback is the one state that is written rather than drawn,
/// and the one that stands still. The other two are answers to "is it working?",
/// which a shape answers faster than a word; this one asks the user to do
/// something, and there is no shape that says "your words are on the clipboard".
///
/// It is drawn by hand for the same reason the menu bar icon is: the bundle is
/// assembled by `Scripts/make-app.sh` and has nowhere to keep an asset.
final class PillView: NSView {
    /// The dark capsule everything is drawn on. Cheppu picks the colour rather
    /// than following the system's, because the Pill floats over other apps'
    /// windows rather than sitting in one: it has to read the same over a white
    /// document and a black terminal.
    private static let capsule = NSColor(white: 0, alpha: 0.82)
    private static let rim = NSColor(white: 1, alpha: 0.12)
    private static let ink = NSColor.white

    /// The level meter: five bars, tallest in the middle, so that a voice reads
    /// as a shape rather than as five things moving together.
    private static let bars = [0.45, 0.75, 1.0, 0.75, 0.45]
    private static let barWidth: CGFloat = 4
    private static let barGap: CGFloat = 5
    private static let shortestBar: CGFloat = 5

    /// The notice, and the size it is set in.
    ///
    /// Where the words are, in the words the rest of Cheppu uses for it. It
    /// says nothing about why they are there: the user is reading this because
    /// what they said did not appear, and "focus moved" or "Accessibility was
    /// taken away" is an explanation they cannot do anything with. Where the
    /// words are is the one thing they can.
    ///
    /// It fits the Pill at this size, which is what keeps the Pill the size it
    /// is in every other state — one that grew for a message would be a shape
    /// that moved while being read.
    private static let notice = "On the clipboard"
    private static let noticeSize: CGFloat = 13

    /// The mark that sweeps while the Engine works, and the track it runs in.
    private static let sweepLength: CGFloat = 38
    private static let sweepThickness: CGFloat = 5
    private static let sweepInset: CGFloat = 16

    /// How often the Transcribing sweep moves, and how far it moves each time.
    ///
    /// Thirty times a second is smooth to the eye and costs nothing next to
    /// what the Engine is doing while it runs. It runs only while Transcribing,
    /// which is under a second of a Dictation and nothing at all of the rest of
    /// the day.
    private static let everyFrame: TimeInterval = 1 / 30
    private static let travelledPerFrame = 0.22

    private var state: PillState = .listening(.silent)

    /// The wave the sweep rides on while Transcribing, and the timer moving it.
    private var travelled = 0.0
    private var travelling: Timer?

    init() {
        super.init(frame: NSRect(origin: .zero, size: PillPlacement.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("The Pill is built in code, never from a nib.")
    }

    /// Shows a state, and starts or stops the dots travelling with it.
    func show(_ state: PillState) {
        self.state = state

        switch state {
        case .listening, .onTheClipboard:
            stopTravelling()
        case .transcribing where travelling == nil:
            startTravelling()
        case .transcribing:
            break
        }

        needsDisplay = true
    }

    /// Puts the Pill back to how it opens, for the next Dictation.
    ///
    /// Called as it goes off screen rather than as it comes back, so that a
    /// Pill which is shown again never shows a frame of the Dictation before
    /// it, and so that nothing is left running behind a window nobody can see.
    func rest() {
        stopTravelling()
        state = .listening(.silent)
        needsDisplay = true
    }

    private func startTravelling() {
        travelled = 0
        let travelling = Timer(timeInterval: Self.everyFrame, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.travelled += Self.travelledPerFrame
                self.needsDisplay = true
            }
        }
        // In the common run loop modes, so that the dots go on moving while a
        // menu is open rather than freezing into the hang they exist to rule
        // out.
        RunLoop.main.add(travelling, forMode: .common)
        self.travelling = travelling
    }

    private func stopTravelling() {
        travelling?.invalidate()
        travelling = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: bounds.height / 2,
            yRadius: bounds.height / 2
        )
        Self.capsule.setFill()
        capsule.fill()
        Self.rim.setStroke()
        capsule.stroke()

        switch state {
        case .listening(let level): drawTheLevel(level)
        case .transcribing: drawTheSweep()
        case .onTheClipboard: drawTheNotice()
        }
    }

    /// The Clipboard Fallback, in words.
    ///
    /// Centred on both axes, in the same white the bars and the sweep are drawn
    /// in, so that the Pill reads as the same object saying something rather
    /// than as a different thing that has appeared.
    private func drawTheNotice() {
        let notice = NSAttributedString(
            string: Self.notice,
            attributes: [
                .font: NSFont.systemFont(ofSize: Self.noticeSize, weight: .medium),
                .foregroundColor: Self.ink,
            ]
        )

        let size = notice.size()
        notice.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    /// The voice, as five bars rising from the height they rest at.
    ///
    /// They rest at a row of dots rather than at nothing, so that a Dictation
    /// hearing silence still looks like a Dictation that is listening.
    private func drawTheLevel(_ level: InputLevel) {
        let tallest = bounds.height - 16
        let width = CGFloat(Self.bars.count) * Self.barWidth
            + CGFloat(Self.bars.count - 1) * Self.barGap

        Self.ink.setFill()
        for (bar, share) in Self.bars.enumerated() {
            let height = Self.shortestBar + (tallest - Self.shortestBar) * level.value * share
            let rect = NSRect(
                x: bounds.midX - width / 2 + CGFloat(bar) * (Self.barWidth + Self.barGap),
                y: bounds.midY - height / 2,
                width: Self.barWidth,
                height: height
            )
            NSBezierPath(
                roundedRect: rect,
                xRadius: Self.barWidth / 2,
                yRadius: Self.barWidth / 2
            ).fill()
        }
    }

    /// The Engine at work, as a mark sweeping the length of the Pill.
    ///
    /// It runs on a track it never leaves, and it eases at both ends rather
    /// than turning round at speed: the Engine is working, not straining, and
    /// a mark that snapped back and forth would read as something going wrong.
    private func drawTheSweep() {
        let track = NSRect(
            x: bounds.minX + Self.sweepInset,
            y: bounds.midY - Self.sweepThickness / 2,
            width: bounds.width - 2 * Self.sweepInset,
            height: Self.sweepThickness
        )
        Self.ink.withAlphaComponent(0.18).setFill()
        NSBezierPath(
            roundedRect: track,
            xRadius: Self.sweepThickness / 2,
            yRadius: Self.sweepThickness / 2
        ).fill()

        // A cosine rather than a sawtooth: it is slowest at each end, which is
        // what makes one mark going back and forth read as one mark rather than
        // as something restarting.
        let howFarAlong = (1 - cos(travelled)) / 2
        let sweep = NSRect(
            x: track.minX + (track.width - Self.sweepLength) * howFarAlong,
            y: track.minY,
            width: Self.sweepLength,
            height: Self.sweepThickness
        )
        Self.ink.setFill()
        NSBezierPath(
            roundedRect: sweep,
            xRadius: Self.sweepThickness / 2,
            yRadius: Self.sweepThickness / 2
        ).fill()
    }
}
