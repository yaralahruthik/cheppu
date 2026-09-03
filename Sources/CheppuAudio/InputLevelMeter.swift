import CheppuCore
import Foundation

/// Turns what the microphone just heard into the height the Pill draws.
///
/// The Pill exists to answer one question — "can it hear me right now?" — and
/// two things stand between a buffer of samples and an honest answer to it.
///
/// The first is that hearing is logarithmic and samples are not. Speech at a
/// comfortable distance from a laptop microphone arrives at an amplitude of
/// about 0.05, so a Pill drawn from raw loudness would be 5% full while someone
/// was talking straight into it, and indistinguishable from a Pill hearing
/// nothing at all. The meter therefore reads in decibels and shows the range a
/// person actually speaks across.
///
/// The second is that speech has holes in it. There is near-silence between
/// most syllables, and a meter that followed it exactly would strobe rather
/// than move. So the reading rises the instant the speaker does and falls only
/// as fast as `halfLife`, which is long enough to bridge a syllable and short
/// enough that stopping mid-sentence is visible.
struct InputLevelMeter {
    /// The quietest sound the Pill shows anything for. Below this is room tone,
    /// fan noise and the microphone's own floor — nothing the user said, and
    /// nothing they could act on.
    static let floor: Double = -60

    /// How long the reading takes to fall by half once the sound stops.
    ///
    /// Measured in time rather than in buffers, because the buffer size belongs
    /// to the device: the same voice must not decay differently on different
    /// hardware.
    static let halfLife = Duration.milliseconds(150)

    private var reading: Double = 0

    /// The level after hearing one buffer.
    ///
    /// An empty buffer is no sound and no time passing, so it leaves the
    /// reading exactly where it was rather than counting as silence.
    mutating func hearing(_ samples: [Float], at sampleRate: Double) -> InputLevel {
        guard !samples.isEmpty, sampleRate > 0 else { return InputLevel(reading) }

        let elapsed = Double(samples.count) / sampleRate
        let decayed = reading * pow(0.5, elapsed / Self.halfLife.asSeconds)

        reading = max(Self.loudness(of: samples), decayed)
        return InputLevel(reading)
    }

    /// How loud a buffer is, as a fraction of the range the Pill draws.
    ///
    /// Root mean square rather than the largest sample: one click should not
    /// fill the Pill, and what the user is asking about is the sound of their
    /// voice rather than its peaks.
    private static func loudness(of samples: [Float]) -> Double {
        let sumOfSquares = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rootMeanSquare = (sumOfSquares / Double(samples.count)).squareRoot()
        guard rootMeanSquare > 0 else { return 0 }

        let decibels = 20 * log10(rootMeanSquare)
        return (decibels - floor) / -floor
    }
}

extension Duration {
    /// This Duration in seconds.
    var asSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
