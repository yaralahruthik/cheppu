import CheppuCore
import Foundation

/// The Clock port, over the machine's own.
///
/// The one place in Cheppu that reads the time, and the one place it waits.
/// Everything that cares what time it is — a History entry's stamp, the length
/// of a press, the Cap — goes through the core and reaches this, so that the
/// suite can move time without waiting for it.
///
/// An actor because of the wait: there is one at a time, and it has to be
/// possible to call off the one that is under way from wherever the Dictation it
/// belongs to ended.
///
/// This is glue over `Date` and `Task.sleep`. The two rules it looks like it
/// holds — one wait at a time, and a wait called off never reaching its end —
/// are the port's rather than this file's, and they are asserted against the
/// fake Clock at the core seam, where what they change about a Dictation can be
/// read back. What is left here is the smallest way of keeping them, which is
/// why it is not tested.
actor SystemClock: ClockPort {
    /// The wait under way, if there is one. Nothing outlives it: a Task that is
    /// still sleeping is one that is still going to do something.
    private var waiting: Task<Void, Never>?

    func now() async -> Date {
        Date()
    }

    func waitOut(_ span: Duration, then whatFollows: @escaping @Sendable () async -> Void) async {
        waiting?.cancel()
        waiting = Task {
            // Cancelled sleep throws, and a wait that was called off is a wait
            // whose end must not happen.
            guard (try? await Task.sleep(for: span)) != nil else { return }
            await whatFollows()
        }
    }

    func stopWaiting() async {
        waiting?.cancel()
        waiting = nil
    }
}
