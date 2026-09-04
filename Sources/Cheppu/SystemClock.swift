import CheppuCore
import Foundation

/// The Clock port, over the machine's own.
///
/// The one place in Cheppu that reads the time. Everything that cares what time
/// it is — a History entry's stamp today, the Cap and the hold threshold later
/// — goes through the core and reaches this, so that the suite can move time
/// without waiting for it.
///
/// This is glue: it holds no decisions of its own, which is why it is not tested.
struct SystemClock: ClockPort {
    func now() async -> Date {
        Date()
    }
}
