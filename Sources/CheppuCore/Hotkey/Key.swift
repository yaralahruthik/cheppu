/// A key that is not a modifier: the half of a chord the user actually strikes.
///
/// A key is a position on the keyboard rather than a letter. The code is what
/// macOS calls `kVK_ANSI_D` and the name is what is printed on that key on an
/// ANSI board — which is what the user is choosing, and what they read back in
/// Settings.
///
/// Only the keys in the table below can be half of a Hotkey. A key Cheppu has
/// no name for is one it could not show the user afterwards, and Escape is
/// absent on purpose: it Cancels a Dictation (ADR-0006), and a Hotkey that was
/// also the way out of one would be a key with two meanings at the same moment.
public struct Key: Equatable, Hashable, Sendable {
    /// Where the key is on the keyboard, as macOS counts positions.
    public let code: UInt16

    /// What is printed on it, and what Settings shows.
    public var name: String { Self.named[code] ?? "" }

    /// How the key is written down in the preferences domain.
    var written: String { name.lowercased() }

    /// Escape, which is deliberately not a key a Hotkey may be built on: it
    /// Cancels a Dictation (ADR-0006), and a key that did both would mean two
    /// things at the same moment.
    ///
    /// Its position is here, beside the table it is kept out of, because both
    /// keyboards Cheppu reads have to recognise it and an app that wrote the
    /// number down twice would eventually write one of them wrongly.
    public static let escape: UInt16 = 53

    /// The key at this position, or nothing where it is not one a Hotkey may be
    /// built on.
    public init?(code: UInt16) {
        guard Self.named[code] != nil else { return nil }
        self.code = code
    }

    /// The key with this name, however it is capitalised.
    public init?(named name: String) {
        let wanted = name.lowercased()
        guard let found = Self.named.first(where: { $0.value.lowercased() == wanted }) else {
            return nil
        }
        self.code = found.key
    }

    /// Every key a Hotkey may be built on, and what is printed on it.
    ///
    /// Everything on an ANSI keyboard that a user could reasonably reach for
    /// and that Cheppu can name back to them: the letters, the digits, the
    /// punctuation, the function row, the arrows, and the big keys under the
    /// hands. What is left out is what Cheppu could not show them afterwards —
    /// the media keys, and the function keys past F12 that only some boards
    /// have — and Escape, which means something else already.
    private static let named: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "\u{27}", 41: ";", 42: "\\", 43: ",", 44: "/",
        47: ".", 50: "`",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
    ]
}
