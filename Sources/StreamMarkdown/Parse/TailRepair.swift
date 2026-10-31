import Foundation
import Markdown

/// What an answer still being written shows at its end. Syntax that is not finished yet is closed early where what it
/// marks can show as it grows (`**bold` draws bold, `` `code`` as code) and cut otherwise (`[text](ht`, a table row
/// without its line break, a closing fence still being typed), so raw markers never flash and are taken back. It reads
/// the extracted text, where formulas are placeholders, so TeX never reads as Markdown.
enum TailRepair {
    /// What to parse instead of the text: its first `keep` bytes, then `closers`.
    struct Result: Equatable {
        let keep: Int
        let closers: String
    }

    /// A destination for reference links whose definition has not arrived yet: drawn in the link colour, not tappable.
    static let pendingLink = "streammarkdown:pending"

    /// The repair of `text`, parsed as `document`, or nil when its end needs none. A full or collapsed reference link
    /// (`[text][label]`, `[text][]`) gets a pending definition after the text, since definitions usually come last;
    /// one already defined keeps its own, as cmark takes the first.
    static func repair(_ text: String, document: Document) -> Result? {
        let tail = Tail(bytes: Array(text.utf8), lines: LineStarts(text))
        let leaf = leaf(of: document)
        var result = tail.repair(leaf: leaf) ?? Result(keep: tail.bytes.count, closers: "")
        if !(leaf is CodeBlock || leaf is HTMLBlock) {
            let labels = tail.referenceLabels(before: result.keep)
            if !labels.isEmpty {
                result = Result(keep: result.keep, closers: result.closers + "\n\n" + labels.map { "[\($0)]: <\(pendingLink)>\n" }.joined())
            }
        }
        return result == Result(keep: tail.bytes.count, closers: "") ? nil : result
    }

    /// Whether an unclosed formula at the end is held back: a display one until it closes, an inline one while it is at
    /// most 100 bytes long and does not read as a price (`$5 per`, where `$1 - p` is math), so a dollar sign never
    /// holds back the rest of a line.
    static func holds(_ math: MathExtractor.UnfinishedMath, in text: String) -> Bool {
        guard !math.delimiter.isDisplay else { return true }
        let rest = text.utf8.dropFirst(math.start + math.delimiter.delimiters.open.utf8.count)
        guard rest.count <= 100 else { return false }
        guard math.delimiter == .dollar, let first = rest.first, first.isDigit else { return true }
        let after = rest.drop { $0.isDigit || $0 == .period || $0 == .comma }
        let word = after.drop { $0 == .space || $0 == .tab }
        guard word.count < after.count, let next = word.first else { return true }
        return !((UInt8(ascii: "a")...UInt8(ascii: "z")).contains(next | 0x20))
    }

    /// The deepest last block: the one the text ends in, inside any quotes and list items holding it.
    static func leaf(of document: Document) -> Markup? {
        guard document.childCount > 0 else { return nil }
        var node = document.child(at: document.childCount - 1)!
        while node is BlockQuote || node is ListItemContainer || node is ListItem, node.childCount > 0 {
            node = node.child(at: node.childCount - 1)!
        }
        return node
    }
}

private struct Tail {
    let bytes: [UInt8]
    let lines: LineStarts

    /// How far a bracket may be from the end and still be held back as an unfinished link.
    private static let linkReach = 300

    func repair(leaf: Markup?) -> TailRepair.Result? {
        guard !bytes.isEmpty else { return nil }
        // The line the text ends on, or the one before a final line break: the paragraph it ends stays open.
        var lineEnd = bytes.count
        if bytes[lineEnd - 1] == .newline { lineEnd -= 1 }
        if lineEnd > 0, bytes[lineEnd - 1] == .carriageReturn { lineEnd -= 1 }
        let endsLine = lineEnd < bytes.count
        let lineStart = start(ofLineAt: lineEnd)
        guard (lineStart..<lineEnd).contains(where: { !bytes[$0].isWhitespace }) else { return nil }
        let inLeaf = leaf.flatMap { $0.range }.map { lines.offset(of: $0.upperBound) >= lineStart } ?? false

        switch inLeaf ? leaf : nil {
        case let code as CodeBlock:
            return repairFence(code, lineStart: lineStart, lineEnd: lineEnd, endsLine: endsLine)
        case is HTMLBlock:
            return nil
        case let table as Table:
            guard !endsLine else { return nil }
            // A row waits for its line break; a table whose delimiter row is still being typed waits from its header.
            return keep(table.body.childCount == 0 && lineStart > 0 ? start(ofLineAt: lineStart - 1) : lineStart)
        case is ThematicBreak:
            return endsLine ? nil : keep(lineStart)
        case let paragraph as Paragraph:
            if let held = holdTableHeader(paragraph, lineStart: lineStart) { return held }
            return repairProse(lineStart: lineStart, lineEnd: lineEnd, endsLine: endsLine)
        default:
            return repairProse(lineStart: lineStart, lineEnd: lineEnd, endsLine: endsLine)
        }
    }

    // MARK: Blocks

    /// An opening fence without its line break yet, or a closing fence still being typed, waits for its line to finish.
    private func repairFence(_ code: CodeBlock, lineStart: Int, lineEnd: Int, endsLine: Bool) -> TailRepair.Result? {
        guard !endsLine, let range = code.range else { return nil }
        let first = lines.lineStart(of: range.lowerBound.line)
        let firstEnd = endOfLine(from: first)
        let (openStart, _) = contentStart(first, before: firstEnd)
        guard openStart < firstEnd, bytes[openStart] == .backtick || bytes[openStart] == .tilde else { return nil }
        let marker = bytes[openStart]
        let length = run(of: marker, at: openStart, before: firstEnd)
        guard length >= 3 else { return nil }
        if first == lineStart { return keep(lineStart) }
        let (cursor, _) = contentStart(lineStart, before: lineEnd)
        let typed = run(of: marker, at: cursor, before: lineEnd)
        return typed > 0 && typed < length && cursor + typed == lineEnd ? keep(lineStart) : nil
    }

    /// Lines starting with `|` at the end of a paragraph may become a table once a delimiter row follows: held from the
    /// first of them, so a table never shows as raw pipes first.
    private func holdTableHeader(_ paragraph: Paragraph, lineStart: Int) -> TailRepair.Result? {
        guard let range = paragraph.range else { return nil }
        return holdTableHeader(from: lineStart, floor: lines.lineStart(of: range.lowerBound.line))
    }

    private func holdTableHeader(from lineStart: Int, floor: Int) -> TailRepair.Result? {
        var held: Int?
        var line = lineStart
        while true {
            let end = endOfLine(from: line)
            let (content, _) = contentStart(line, before: end)
            guard content < end, bytes[content] == .pipe else { break }
            held = line
            guard line > floor, line > 0 else { break }
            line = start(ofLineAt: line - 1)
        }
        return held.map(keep)
    }

    // MARK: Prose

    private func repairProse(lineStart: Int, lineEnd: Int, endsLine: Bool) -> TailRepair.Result? {
        let (content, afterMarker) = contentStart(lineStart, before: lineEnd)
        let end = trimmedEnd(content, lineEnd)
        if !endsLine, startsSomethingElse(content..<end, afterMarker: afterMarker) { return keep(lineStart) }
        guard content < end else { return nil }

        var limit = end
        var didCut = false
        // A cut can leave a marker at the new end, so look again until nothing changes.
        for _ in 0..<4 {
            let scan = scanInlines(content..<limit, afterMarker: afterMarker)
            var cut = scan.cut
            let runs = scan.runs.filter { $0.end <= (cut ?? limit) }
            let kept = trimmedEnd(content, cut ?? limit)
            let open = matchEmphasis(runs.filter { $0.end <= kept })
            if let dangling = unmatchedAtEnd(runs, kept) {
                cut = min(cut ?? dangling.start, dangling.start)
            }
            if let code = scan.openCode, code.start < kept, kept <= code.start + code.length {
                cut = min(cut ?? code.start, code.start)
            }
            if let cut {
                didCut = true
                limit = trimmedEnd(content, cut)
                if limit <= content { return keep(lineStart) }
                continue
            }
            var closers = ""
            if let code = scan.openCode, code.start < kept { closers += String(repeating: "`", count: code.length) }
            for opener in open.reversed() where opener.count > 0 {
                closers += String(repeating: Character(Unicode.Scalar(opener.run.marker)), count: opener.count)
            }
            if closers.isEmpty { return didCut ? keep(kept) : nil }
            return TailRepair.Result(keep: kept, closers: closers)
        }
        return keep(limit)
    }

    /// A last line that may still become something else: only container markers, `#`s, a rule or setext underline,
    /// digits of an ordered list's number, backticks of a fence, a task box not yet closed, or a link reference
    /// definition, which draws nothing once its destination arrives.
    private func startsSomethingElse(_ content: Range<Int>, afterMarker: Bool) -> Bool {
        let text = bytes[content]
        if text.isEmpty { return true }
        if text.first == .openBracket, let close = text.firstIndex(of: .closeBracket), close + 1 < content.upperBound, bytes[close + 1] == .colon { return true }
        if text.allSatisfy({ $0 == .hash }) && text.count <= 6 { return true }
        if text.allSatisfy({ $0 == .hyphen || $0 == .equals || $0 == .asterisk || $0 == .underscore || $0 == .space || $0 == .tab }) { return true }
        if text.allSatisfy(\.isDigit) || text.allSatisfy({ $0 == .backtick }) || text.allSatisfy({ $0 == .tilde }) { return true }
        if afterMarker, text.first == .openBracket, text.count <= 3 {
            let box = Array(text)
            return box.count == 1 || ([.space, .x, .upperX].contains(box[1]) && (box.count == 2 || box[2] == .closeBracket))
        }
        return false
    }

    private struct Run {
        let marker: UInt8
        let start: Int
        let length: Int
        let canOpen: Bool
        let canClose: Bool
        var end: Int { start + length }
    }

    private struct Opener {
        let run: Run
        var count: Int
        var start: Int { run.start }
    }

    private struct InlineScan {
        var runs: [Run] = []
        var openCode: (start: Int, length: Int)?
        var cut: Int?
    }

    /// Code spans, links and emphasis delimiters on the line, left to right as cmark reads them.
    private func scanInlines(_ line: Range<Int>, afterMarker: Bool) -> InlineScan {
        var scan = InlineScan()
        var brackets: [Int] = []
        var index = line.lowerBound
        let end = line.upperBound
        func hold(_ opener: Int) {
            if end - opener <= Self.linkReach { scan.cut = min(scan.cut ?? opener, opener) }
        }
        while index < end {
            let byte = bytes[index]
            switch byte {
            case .backslash:
                if index + 1 >= end { scan.cut = min(scan.cut ?? index, index) }
                index += 2
            case .backtick:
                let length = run(of: .backtick, at: index, before: end)
                if let close = closingCode(length, from: index + length, before: end) {
                    index = close + length
                } else if (index..<end).contains(where: { isPlaceholder(at: $0) }) {
                    // Closing it would show a formula's placeholder as code, so it waits for its own closer.
                    scan.cut = min(scan.cut ?? index, index)
                    index = end
                } else {
                    scan.openCode = (index, length)
                    index = end
                }
            case .bang where index + 1 < end && bytes[index + 1] == .openBracket:
                brackets.append(index)
                index += 2
            case .openBracket:
                brackets.append(index)
                index += 1
            case .closeBracket:
                guard let opener = brackets.popLast() else {
                    index += 1
                    continue
                }
                let next = index + 1
                let isTaskBox = afterMarker && opener == line.lowerBound && index - opener == 2
                if next >= end {
                    if !isTaskBox { hold(opener) }
                    index = next
                } else if bytes[next] == .openParen {
                    if let close = destinationEnd(from: next + 1, before: end) { index = close + 1 } else { hold(opener); index = end }
                } else if bytes[next] == .openBracket {
                    if let close = (next + 1..<end).first(where: { bytes[$0] == .closeBracket }) { index = close + 1 } else { hold(opener); index = end }
                } else {
                    index = next
                }
            case .asterisk, .underscore, .tilde:
                let length = run(of: byte, at: index, before: end)
                var run = delimiterRun(byte, start: index, length: length, lineStart: line.lowerBound, end: end)
                // GFM strikes through between tildes of the same count; a single one is usually "about", so it never opens.
                if byte == .tilde && length != 2 { run = Run(marker: byte, start: index, length: length, canOpen: false, canClose: false) }
                scan.runs.append(run)
                index += length
            case .lessThan:
                // An autolink or tag still being typed: `<` and what follows up to the end, with no space in between.
                if index + 1 >= end || ((UInt8(ascii: "a")...UInt8(ascii: "z")).contains(bytes[index + 1] | 0x20)
                    && !(index + 1..<end).contains(where: { bytes[$0] == .greaterThan || bytes[$0].isWhitespace })) {
                    scan.cut = min(scan.cut ?? index, index)
                    index = end
                } else {
                    index += 1
                }
            case .dollar:
                // Every formula is a placeholder by now, so a dollar sign at the end may still open one.
                let length = run(of: .dollar, at: index, before: end)
                if index + length == end { scan.cut = min(scan.cut ?? index, index) }
                index += length
            default:
                index += 1
            }
        }
        if let first = brackets.first(where: { end - $0 <= Self.linkReach }) { hold(first) }
        return scan
    }

    /// CommonMark's flanking rules, with the end of the text read as white space.
    private func delimiterRun(_ marker: UInt8, start: Int, length: Int, lineStart: Int, end: Int) -> Run {
        let before = start > lineStart ? kind(endingAt: start) : .whitespace
        let after = start + length < end ? kind(startingAt: start + length) : .whitespace
        let left = after != .whitespace && (after != .punctuation || before != .other)
        let right = before != .whitespace && (before != .punctuation || after != .other)
        if marker == .underscore {
            return Run(marker: marker, start: start, length: length, canOpen: left && (!right || before == .punctuation),
                       canClose: right && (!left || after == .punctuation))
        }
        return Run(marker: marker, start: start, length: length, canOpen: left, canClose: right)
    }

    /// The openers left without a closer, after matching each closer to the nearest opener of its marker.
    private func matchEmphasis(_ runs: [Run]) -> [Opener] {
        var openers: [Opener] = []
        for run in runs {
            var count = run.length
            if run.canClose {
                while count > 0, let index = openers.lastIndex(where: { $0.run.marker == run.marker && ($0.run.marker != .tilde || $0.count == count) }) {
                    let used = min(count, openers[index].count)
                    openers[index].count -= used
                    count -= used
                    openers.removeSubrange((index + 1)...)
                    if openers[index].count == 0 { openers.remove(at: index) }
                }
            }
            if count > 0, run.canOpen { openers.append(Opener(run: run, count: count)) }
        }
        return openers
    }

    /// A delimiter run at the very end that closed nothing: it may still open something, so it waits.
    private func unmatchedAtEnd(_ runs: [Run], _ end: Int) -> Opener? {
        guard let last = runs.last, last.end == end else { return nil }
        let before = matchEmphasis(Array(runs.dropLast()))
        let after = matchEmphasis(runs)
        let closedSomething = after.reduce(0) { $0 + $1.count } < before.reduce(0) { $0 + $1.count }
        return closedSomething ? nil : Opener(run: last, count: last.length)
    }

    /// The labels of full and collapsed reference links in the first `end` bytes.
    func referenceLabels(before end: Int) -> [String] {
        var labels: [String] = []
        var index = 1
        while index + 1 < end {
            defer { index += 1 }
            guard bytes[index] == .closeBracket, bytes[index + 1] == .openBracket else { continue }
            guard let close = (index + 2..<min(end, index + 1001)).first(where: { [.closeBracket, .openBracket, .newline].contains(bytes[$0]) }),
                  bytes[close] == .closeBracket else { continue }
            var label = index + 2..<close
            if label.isEmpty {
                guard let open = (max(0, index - 1000)..<index).last(where: { [.closeBracket, .openBracket, .newline].contains(bytes[$0]) }),
                      bytes[open] == .openBracket else { continue }
                label = open + 1..<index
            }
            if !label.isEmpty { labels.append(String(decoding: bytes[label], as: UTF8.self)) }
        }
        return labels
    }

    // MARK: Reading the bytes

    /// Whether a formula's placeholder, a scalar from U+F0000, starts here.
    private func isPlaceholder(at index: Int) -> Bool {
        bytes[index] == 0xF3 && index + 1 < bytes.count && bytes[index + 1] >= 0xB0
    }

    private enum Kind { case whitespace, punctuation, other }

    private func kind(endingAt index: Int) -> Kind {
        var start = index - 1
        while start > 0, bytes[start] & 0xC0 == 0x80 { start -= 1 }
        return kind(of: start..<index)
    }

    private func kind(startingAt index: Int) -> Kind {
        var end = index + 1
        while end < bytes.count, bytes[end] & 0xC0 == 0x80 { end += 1 }
        return kind(of: index..<end)
    }

    private func kind(of range: Range<Int>) -> Kind {
        guard let scalar = String(decoding: bytes[range], as: UTF8.self).unicodeScalars.first else { return .whitespace }
        if scalar.properties.isWhitespace { return .whitespace }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation, .finalPunctuation,
             .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return .punctuation
        default:
            return .other
        }
    }

    /// Where a line's own text starts, after its indentation, quote markers and list markers.
    private func contentStart(_ lineStart: Int, before end: Int) -> (Int, afterMarker: Bool) {
        var cursor = lineStart
        var afterMarker = false
        func spaceOrEnd(_ index: Int) -> Bool { index >= end || bytes[index] == .space || bytes[index] == .tab }
        while cursor < end {
            switch bytes[cursor] {
            case .space, .tab, .greaterThan:
                cursor += 1
            case .hyphen, .plus, .asterisk:
                guard spaceOrEnd(cursor + 1) else { return (cursor, afterMarker) }
                cursor += 1
                afterMarker = true
            case let byte where byte.isDigit:
                var digits = cursor
                while digits < end, bytes[digits].isDigit { digits += 1 }
                guard digits < end, bytes[digits] == .period || bytes[digits] == .closeParen, spaceOrEnd(digits + 1) else { return (cursor, afterMarker) }
                cursor = digits + 1
                afterMarker = true
            default:
                return (cursor, afterMarker)
            }
        }
        return (cursor, afterMarker)
    }

    private func trimmedEnd(_ start: Int, _ end: Int) -> Int {
        var end = end
        while end > start, bytes[end - 1] == .space || bytes[end - 1] == .tab { end -= 1 }
        return end
    }

    private func start(ofLineAt index: Int) -> Int {
        var start = index
        while start > 0, bytes[start - 1] != .newline, bytes[start - 1] != .carriageReturn { start -= 1 }
        return start
    }

    private func endOfLine(from start: Int) -> Int {
        var end = start
        while end < bytes.count, bytes[end] != .newline, bytes[end] != .carriageReturn { end += 1 }
        return end
    }

    private func run(of byte: UInt8, at index: Int, before end: Int) -> Int {
        var cursor = index
        while cursor < end, bytes[cursor] == byte { cursor += 1 }
        return cursor - index
    }

    /// The start of a run of exactly `length` backticks, which closes a code span.
    private func closingCode(_ length: Int, from start: Int, before end: Int) -> Int? {
        var cursor = start
        while cursor < end {
            guard bytes[cursor] == .backtick else {
                cursor += 1
                continue
            }
            let found = run(of: .backtick, at: cursor, before: end)
            if found == length { return cursor }
            cursor += found
        }
        return nil
    }

    /// The `)` that closes a link destination and title opened before `start`, or nil when it has not arrived.
    private func destinationEnd(from start: Int, before end: Int) -> Int? {
        var cursor = start
        var depth = 0
        var quote: UInt8?
        while cursor < end, bytes[cursor] == .space || bytes[cursor] == .tab { cursor += 1 }
        if cursor < end, bytes[cursor] == .lessThan {
            guard let close = (cursor..<end).first(where: { bytes[$0] == .greaterThan }) else { return nil }
            cursor = close + 1
        }
        while cursor < end {
            let byte = bytes[cursor]
            if let open = quote {
                if byte == open { quote = nil } else if byte == .backslash { cursor += 1 }
            } else if byte == .backslash {
                cursor += 1
            } else if (byte == .quote || byte == .apostrophe) && bytes[cursor - 1].isWhitespace {
                quote = byte
            } else if byte == .openParen {
                depth += 1
            } else if byte == .closeParen {
                if depth == 0 { return cursor }
                depth -= 1
            }
            cursor += 1
        }
        return nil
    }

    private func keep(_ count: Int) -> TailRepair.Result { TailRepair.Result(keep: count, closers: "") }
}

private extension UInt8 {
    static let newline = UInt8(ascii: "\n"), carriageReturn = UInt8(ascii: "\r"), space = UInt8(ascii: " "), tab = UInt8(ascii: "\t")
    static let backtick = UInt8(ascii: "`"), tilde = UInt8(ascii: "~"), asterisk = UInt8(ascii: "*"), underscore = UInt8(ascii: "_")
    static let hash = UInt8(ascii: "#"), hyphen = UInt8(ascii: "-"), equals = UInt8(ascii: "="), plus = UInt8(ascii: "+")
    static let pipe = UInt8(ascii: "|"), bang = UInt8(ascii: "!"), backslash = UInt8(ascii: "\\"), greaterThan = UInt8(ascii: ">"), lessThan = UInt8(ascii: "<")
    static let openBracket = UInt8(ascii: "["), closeBracket = UInt8(ascii: "]"), openParen = UInt8(ascii: "("), closeParen = UInt8(ascii: ")")
    static let quote = UInt8(ascii: "\""), apostrophe = UInt8(ascii: "'"), period = UInt8(ascii: "."), comma = UInt8(ascii: ",")
    static let x = UInt8(ascii: "x"), upperX = UInt8(ascii: "X"), colon = UInt8(ascii: ":"), dollar = UInt8(ascii: "$")

    var isWhitespace: Bool { self == .space || self == .tab || self == .newline || self == .carriageReturn }
    var isDigit: Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self) }
}
