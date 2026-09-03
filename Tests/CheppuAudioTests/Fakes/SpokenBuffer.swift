import Foundation

/// A buffer of a constant amplitude, which is the loudness the meter reads.
///
/// Not a recording of anyone: what both suites need is a known loudness, and a
/// square wave's root mean square is exactly its amplitude, so every assertion
/// about a level can be worked out on paper.
func buffer(at amplitude: Float, frames: Int = 4_096) -> [Float] {
    (0..<frames).map { $0.isMultiple(of: 2) ? amplitude : -amplitude }
}
