/// What the user is told about their Spellings, said the same way in both
/// places it is said: the row on the Settings screen, and the short section
/// above the Dictations in the History window.
///
/// The copy is here rather than in either window because it is the same
/// sentence in both, and two windows keeping one sentence in step by hand is
/// two windows that come to disagree about what fetching costs.
public enum SpellingsRow: Equatable, Sendable {
    /// The part of the Engine that can hear where a Spelling was said is on the
    /// machine: whether Spellings are read, and how many there are.
    ///
    /// Off keeps them and stops reading them, so a Spelling suspected of
    /// misfiring can be ruled out in one flick.
    case theEngineCanReadThem(areOn: Bool, howMany: Int)

    /// It is not on the machine, and this is the offer to fetch it — with what
    /// it weighs said at the moment it is offered and never before (ADR-0014).
    case thePartIsMissing

    /// It is on its way. Nothing was started on Cheppu's own account: somebody
    /// pressed the button.
    case thePartIsArriving(EngineDownloadProgress)

    /// The line the user reads.
    public var title: String { "Spellings" }

    /// Whether this row is worth a section of its own in the History window
    /// even with nothing taught.
    ///
    /// A fetch under way is: the user pressed the button, and a download that
    /// vanished from under them because they forgot their last Spelling while
    /// it ran would be Cheppu spending their connection where they cannot see
    /// it. A part that is merely missing is not, because the offer is made at
    /// the first Correction and never before (ADR-0014) — and before that there
    /// is nothing for the part to read.
    public var isWorthShowingOnItsOwn: Bool {
        switch self {
        case .thePartIsArriving: true
        case .theEngineCanReadThem, .thePartIsMissing: false
        }
    }

    /// The second line, which is where what this costs is said.
    public var explanation: String {
        switch self {
        case .theEngineCanReadThem(_, 0):
            "Words you correct in History are put back the next time Cheppu hears them said."
        case .theEngineCanReadThem(_, 1):
            "One word or phrase you corrected, put back where Cheppu hears it said."
        case .theEngineCanReadThem(_, let howMany):
            "\(howMany) words and phrases you corrected, put back where Cheppu hears them said."
        case .thePartIsMissing:
            "Reading them needs \(SpellingsPartOfTheEngine.howBigItIs) more of the engine, "
                + "fetched once. Nothing is downloaded until you ask for it."
        case .thePartIsArriving(let progress):
            "Fetching the rest of the engine — \(progress.howFarAlong)."
        }
    }

    /// Which way the switch is set, or nothing where there is no switch to set:
    /// a part that is missing or arriving is a thing to read and a button to
    /// press, and a switch over it would be one that changed nothing.
    public var isOn: Bool? {
        switch self {
        case .theEngineCanReadThem(let areOn, _): areOn
        case .thePartIsMissing, .thePartIsArriving: nil
        }
    }

    /// What the row's button says, where it has one.
    ///
    /// Nothing to forget is no button: a row offering to empty something that
    /// is already empty is a screen that can be read and not acted on.
    public var action: String? {
        switch self {
        // No ellipsis, and nothing asked first, for the reason Clear History
        // asks nothing (`docs/product-experience.md` §10).
        case .theEngineCanReadThem(_, let howMany): howMany > 0 ? "Forget All" : nil
        case .thePartIsMissing: "Download"
        case .thePartIsArriving: nil
        }
    }
}

/// The second part of the Engine: what only Spellings need, and what it weighs.
///
/// Not fetched at Onboarding. 97 MiB for every user, most of whom will never
/// make a Correction, to spare the few who do a button is the wrong side of the
/// trade — so it is offered at the first Correction, with its size said at that
/// moment, and again from Settings for as long as it is missing (ADR-0014).
public enum SpellingsPartOfTheEngine {
    /// What the two CoreML bundles, the token table and the tokenizer that
    /// reads it weigh together, measured against the repository on
    /// 10 September 2026.
    ///
    /// Committed rather than asked for. The size is said before anything is
    /// fetched, and asking the repository what it weighs in order to offer the
    /// download would be Cheppu reaching the network at a moment the user has
    /// not agreed to it yet.
    public static let bytes: Int64 = 102_802_455

    /// What it weighs, in the words the user reads.
    ///
    /// Megabytes of a million bytes, as `EngineDownloadProgress` counts them
    /// and as the Finder and the App Store do, so that the number in the offer
    /// and the number under the bar that follows it are the same number.
    public static var howBigItIs: String {
        "\((bytes + 500_000) / 1_000_000) MB"
    }
}
