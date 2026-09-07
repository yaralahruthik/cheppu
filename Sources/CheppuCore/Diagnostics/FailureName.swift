/// What a failure is, written into the Diagnostics Log in place of what it says
/// about itself.
///
/// An error is the one thing on a Dictation's path that arrives from outside
/// Cheppu's vocabulary, and `localizedDescription` is where a log stops being a
/// record of what happened and becomes whatever a framework felt like putting
/// in a string. A `URLError` names the URL it failed on; a `CocoaError` names
/// the file. Neither of those is what the user said, and neither of them is
/// something Cheppu can promise about a type it has never seen.
///
/// So the failure is named rather than described. A type name is written into
/// the binary when Cheppu is built and cannot be something somebody dictated,
/// which makes it the most a log can say about a stranger's error and still
/// keep the promise it is written under (`docs/product-experience.md` §10).
///
/// Cheppu's own failures say more, because Cheppu knows what is in them: see
/// `FailureSafeToName`.
public struct FailureName: Equatable, Sendable, CustomStringConvertible {
    public let description: String

    /// - Parameter failure: what went wrong. It is asked what type it is, and
    ///   is otherwise never looked at — unless it is one of Cheppu's own, which
    ///   have said so.
    public init(of failure: any Error) {
        if let named = failure as? any FailureSafeToName {
            // A closed set of cases carrying nothing, so printing the value
            // prints the case and there is nothing else in it to print.
            description = String(describing: named)
        } else {
            // Qualified, so that a nested `Failure` in one target is told apart
            // from a nested `Failure` in another. A log full of "Failure" would
            // be a log that named nothing.
            description = String(reflecting: type(of: failure))
        }
    }
}

/// A failure whose own name is safe to write down.
///
/// Cheppu's failures are enumerations of cases that carry nothing: there is no
/// value in one of them, so there is nothing in one of them that could be
/// something the user said. Saying so here is what lets the log record which
/// refusal it met — a microphone that was refused reads very differently from
/// one that is not plugged in — rather than flattening every one of them to the
/// name of the type they share.
///
/// Conformance is a promise about the cases, and it is the only thing standing
/// between the Diagnostics Log and a failure that carries a string. Anything
/// with an associated value that came from outside Cheppu does not get to make
/// it.
public protocol FailureSafeToName: Error {}

extension AudioCaptureFailure: FailureSafeToName {}
extension InsertionFailure: FailureSafeToName {}
extension HotkeyFailure: FailureSafeToName {}
