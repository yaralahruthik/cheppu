import AppKit
import CheppuCore

/// Everything the pasteboard is holding, in a form it can be given back.
///
/// A string would not do. The user may have copied a screenshot, a file, or
/// styled text, and putting a string back where one of those was is not
/// restoring their clipboard — it is replacing it with something smaller.
struct PasteboardContents: Equatable, Sendable {
    /// What plain text is called on a pasteboard. Named here so that the one
    /// type Cheppu ever writes is not a string literal in three places.
    static let plainText = NSPasteboard.PasteboardType.string.rawValue

    /// One entry per item on the pasteboard, each holding the item's data under
    /// every type it was offered as.
    let items: [[String: Data]]

    init(items: [[String: Data]]) {
        self.items = items
    }
}

/// The pasteboard Cheppu borrows and gives back.
///
/// Narrow on purpose: read it, put the Final Text on it, put back what was
/// there. When it is borrowed, what is checked before borrowing it, and what is
/// given back sits above this line and is tested there.
protocol Pasteboard: Sendable {
    /// Everything it holds this instant.
    func contents() -> PasteboardContents

    /// Replaces everything on it with the Final Text, which is what the Target
    /// App will paste.
    func replace(with text: String)

    /// Puts back what was there — including having been empty, which is a state
    /// the user can tell apart from "still holding what Cheppu borrowed it for".
    func restore(_ contents: PasteboardContents)
}

/// The Mac's pasteboard: the one every app pastes from, which is why Insertion
/// has to borrow it rather than use one of its own.
struct SystemPasteboard: Pasteboard {
    private var pasteboard: NSPasteboard { .general }

    func contents() -> PasteboardContents {
        PasteboardContents(
            items: (pasteboard.pasteboardItems ?? []).map { item in
                var kept: [String: Data] = [:]
                for type in item.types {
                    // A promised type has nothing behind it until the app that
                    // put it there is asked to produce it, and only the app
                    // pasting can ask. What cannot be read cannot be given
                    // back, so it is left out rather than given back empty.
                    if let data = item.data(forType: type) {
                        kept[type.rawValue] = data
                    }
                }
                return kept
            }
        )
    }

    func replace(with text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func restore(_ contents: PasteboardContents) {
        // Clearing first is what makes an empty clipboard restorable: without
        // it, giving back nothing would leave the Final Text sitting there.
        pasteboard.clearContents()
        guard !contents.items.isEmpty else { return }

        pasteboard.writeObjects(
            contents.items.map { kept in
                let item = NSPasteboardItem()
                for (type, data) in kept {
                    item.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
                return item
            }
        )
    }
}

/// The Clipboard port, over the same pasteboard Insertion borrows.
///
/// Text only, because the one thing Cheppu ever puts on the clipboard
/// deliberately is a Final Text — the Clipboard Fallback, when the words could
/// not be inserted (#14). Reading and restoring in full is Insertion's, above.
///
/// It is here now, doing nothing, because a `DictationCore` is handed all of
/// its ports at once and the alternative was a stand-in that quietly threw the
/// user's clipboard away the first time #14 called it.
public struct SystemClipboard: ClipboardPort {
    public init() {}

    public func read() async -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    public func write(_ text: String) async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
