import Foundation

/// Releases a growing answer at a steady pace instead of in the lumps it arrives in. Every 50 ms it shows enough of
/// the backlog to clear it in about a third of a second, and at least 60 characters a second, so steady input comes
/// out at its own rate and a burst drains quickly but evenly. The text it starts with shows at once.
struct RevealPacer {
    static let tick = 0.05
    static let catchUp = 0.35
    static let minimumRate = 60.0
    /// A frame that lands this close before a tick is due takes it, so ticks keep to the frames they fall in.
    private static let slack = 0.004

    /// Everything received.
    private(set) var text: String
    /// UTF-8 length of the part shown.
    private(set) var shown: Int
    /// Characters received and not shown yet.
    private(set) var backlog = 0
    private var lastTick: Double?
    private var carry = 0.0

    init(_ text: String = "") {
        self.text = text
        shown = text.utf8.count
    }

    var revealed: String { String(decoding: Array(text.utf8.prefix(shown)), as: UTF8.self) }

    /// Takes the whole answer so far. A text that does not extend the last one replaces it and shows at once.
    mutating func receive(_ new: String) {
        guard new.utf8.count != text.utf8.count || new != text else { return }
        guard new.utf8.starts(with: text.utf8) else {
            self = RevealPacer(new)
            return
        }
        backlog += String(decoding: Array(new.utf8.dropFirst(text.utf8.count)), as: UTF8.self).count
        text = new
    }

    mutating func revealAll() {
        shown = text.utf8.count
        backlog = 0
        carry = 0
        lastTick = nil
    }

    /// Shows the next stretch if a tick is due at `now` (seconds); returns whether more is shown. Unpaced, each tick
    /// shows the whole backlog, which still gathers what arrives between ticks into one update.
    mutating func advance(to now: Double, paced: Bool) -> Bool {
        guard backlog > 0 else {
            lastTick = nil
            return false
        }
        if let lastTick, now - lastTick < Self.tick - Self.slack { return false }
        let elapsed = lastTick.map { min(now - $0, 0.25) } ?? Self.tick
        lastTick = now
        var count = backlog
        if paced {
            let exact = max(Double(backlog) / Self.catchUp, Self.minimumRate) * elapsed + carry
            count = min(backlog, Int(exact))
            carry = count < backlog ? exact - Double(count) : 0
        }
        guard count > 0 else { return false }
        let utf8 = text.utf8
        var index = utf8.index(utf8.startIndex, offsetBy: shown)
        for _ in 0..<count where index < text.endIndex { text.formIndex(after: &index) }
        shown = max(shown, utf8.distance(from: utf8.startIndex, to: index))
        backlog -= count
        if shown == utf8.count { backlog = 0 }
        return true
    }
}
