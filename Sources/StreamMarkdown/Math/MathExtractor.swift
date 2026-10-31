import Foundation
import Markdown

/// A formula in the answer, as its delimiters mark it.
struct MathSpan: Hashable, Sendable {
    enum Delimiter: Hashable, Sendable {
        /// `$…$`, inline.
        case dollar
        /// `$$…$$`, display.
        case doubleDollar
        /// `\(…\)`, inline.
        case parenthesis
        /// `\[…\]`, display.
        case bracket

        var isDisplay: Bool { self == .doubleDollar || self == .bracket }

        var delimiters: (open: String, close: String) {
            switch self {
            case .dollar: ("$", "$")
            case .doubleDollar: ("$$", "$$")
            case .parenthesis: ("\\(", "\\)")
            case .bracket: ("\\[", "\\]")
            }
        }
    }

    let delimiter: Delimiter
    /// UTF-8 offsets into the answer, delimiters included.
    let range: Range<Int>
    /// The TeX between the delimiters, without the quote markers of the lines it continues on.
    let tex: String

    var isDisplay: Bool { delimiter.isDisplay }
    /// What VoiceOver reads for the formula.
    var label: String { tex.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The formula as written, delimiters included.
    var source: String { delimiter.delimiters.open + tex + delimiter.delimiters.close }
}

/// The formulas of one parse, each standing in the parsed text as one private-use scalar.
struct MathTable: Sendable {
    static let empty = MathTable(spans: [])
    private static let base: UInt32 = 0xF0000

    let spans: [MathSpan]

    static func placeholder(_ index: Int) -> String { String(Character(Unicode.Scalar(base + UInt32(index))!)) }

    func span(_ scalar: Unicode.Scalar) -> MathSpan? {
        let index = Int(scalar.value) - Int(Self.base)
        return spans.indices.contains(index) ? spans[index] : nil
    }

    enum Segment {
        case text(Substring)
        case math(MathSpan)
    }

    /// A parsed text cut into its plain runs and its formulas.
    func segments(_ string: String) -> [Segment] {
        guard !spans.isEmpty else { return [.text(string[...])] }
        var segments: [Segment] = []
        var start = string.unicodeScalars.startIndex
        for index in string.unicodeScalars.indices {
            guard let span = span(string.unicodeScalars[index]) else { continue }
            if start < index { segments.append(.text(Substring(string.unicodeScalars[start..<index]))) }
            segments.append(.math(span))
            start = string.unicodeScalars.index(after: index)
        }
        if start < string.unicodeScalars.endIndex { segments.append(.text(Substring(string.unicodeScalars[start...]))) }
        return segments
    }

    /// The text with each formula written back as its source, for what is drawn as source.
    func restoring(_ string: String) -> String {
        guard !spans.isEmpty else { return string }
        return segments(string).map {
            switch $0 {
            case .text(let text): String(text)
            case .math(let span): span.source
            }
        }.joined()
    }

    /// Whether a paragraph holds display formulas and nothing else but white space.
    func isDisplayOnly(_ markup: Markup) -> Bool {
        guard markup is Paragraph, !spans.isEmpty else { return false }
        var found = false
        for child in markup.children {
            switch child {
            case is SoftBreak, is LineBreak: continue
            case let text as Text:
                for segment in segments(text.string) {
                    switch segment {
                    case .text(let run): if run.contains(where: { !$0.isWhitespace }) { return false }
                    case .math(let span): if span.isDisplay { found = true } else { return false }
                    }
                }
            default: return false
            }
        }
        return found
    }
}

/// The answer as the block parse sees it: each formula replaced by its placeholder, so cmark never reads TeX as Markdown.
struct MathExtraction {
    /// The answer with placeholders.
    let text: String
    let math: MathTable
    /// `text` parsed.
    let document: Document
    private let replacements: [Replacement]

    /// Where a stretch of the answer became its placeholder, in UTF-8 offsets of both texts.
    struct Replacement {
        let answer: Range<Int>
        let formula: Range<Int>
        let parsed: Range<Int>
        /// Where the placeholder starts in the parsed text: blank lines may come before it.
        let placeholder: Int
    }

    fileprivate init(text: String, math: MathTable, document: Document, replacements: [Replacement]) {
        self.text = text
        self.math = math
        self.document = document
        self.replacements = replacements
    }

    /// An offset into the parsed text as an offset into the answer; one inside a replacement goes to its formula's start or end.
    func answerOffset(_ offset: Int) -> Int {
        var shift = 0
        for replacement in replacements {
            if offset <= replacement.parsed.lowerBound {
                return offset == replacement.parsed.lowerBound ? replacement.answer.lowerBound : offset + shift
            }
            if offset < replacement.parsed.upperBound {
                return offset <= replacement.placeholder ? replacement.formula.lowerBound : replacement.formula.upperBound
            }
            shift = replacement.answer.upperBound - replacement.parsed.upperBound
        }
        return offset + shift
    }
}

/// Finds the formulas in an answer: `$…$`, `$$…$$`, `\(…\)` and `\[…\]`, outside code, HTML, link destinations and
/// escapes. Inline dollars follow Pandoc's rule, so `$5 and $10` stays currency: the opening `$` is followed by a non-space,
/// the closing one is preceded by a non-space and not followed by a digit.
enum MathExtractor {
    static let parseOptions: ParseOptions = [.disableSmartOpts]

    /// Where an answer still being written ends inside a formula that has no closing delimiter yet.
    struct UnfinishedMath: Hashable, Sendable {
        let delimiter: MathSpan.Delimiter
        /// UTF-8 offset of the opening delimiter in the answer.
        let start: Int
    }

    static func extract(_ text: String) -> MathExtraction {
        let scan = Scan(text)
        guard !scan.spans.isEmpty else {
            return MathExtraction(text: text, math: .empty, document: scan.document ?? Document(parsing: text, options: parseOptions), replacements: [])
        }
        var parsed: [UInt8] = []
        parsed.reserveCapacity(scan.bytes.count + scan.spans.count * 8)
        var replacements: [MathExtraction.Replacement] = []
        var cursor = 0
        for (index, found) in scan.spans.enumerated() {
            parsed.append(contentsOf: scan.bytes[cursor..<found.replaced.lowerBound])
            let start = parsed.count
            if found.ownBlock { parsed.append(contentsOf: [0x0A, 0x0A]) }
            let placeholder = parsed.count
            parsed.append(contentsOf: Array(MathTable.placeholder(index).utf8))
            if found.ownBlock { parsed.append(contentsOf: [0x0A, 0x0A]) }
            replacements.append(.init(answer: found.replaced, formula: found.span.range, parsed: start..<parsed.count, placeholder: placeholder))
            cursor = found.replaced.upperBound
        }
        parsed.append(contentsOf: scan.bytes[cursor...])
        let parsedText = String(decoding: parsed, as: UTF8.self)
        return MathExtraction(
            text: parsedText,
            math: MathTable(spans: scan.spans.map(\.span)),
            document: Document(parsing: parsedText, options: parseOptions),
            replacements: replacements
        )
    }

    /// The opening delimiter of the formula the answer ends inside, if it ends inside one: the question the streaming tail
    /// repair asks before it holds text back. A `$` that may yet turn out to be currency counts.
    static func unfinishedMath(in text: String) -> UnfinishedMath? {
        Scan(text).unfinished
    }
}

/// One pass over an answer: cmark's parse says where math may not be, and a byte scan finds the formulas elsewhere.
private struct Scan {
    struct Found {
        let span: MathSpan
        /// What the placeholder replaces: the formula, and around a display formula that becomes its own block, the
        /// spaces beside it on its line.
        let replaced: Range<Int>
        let ownBlock: Bool
    }

    let bytes: [UInt8]
    /// The answer parsed as it is, when it had to be parsed to find the formulas.
    private(set) var document: Document?
    private(set) var spans: [Found] = []
    private(set) var unfinished: MathExtractor.UnfinishedMath?
    private var rootParagraphs: [Range<Int>] = []

    init(_ text: String) {
        bytes = Array(text.utf8)
        guard Self.mayHoldMath(bytes) else { return }
        let document = Document(parsing: text, options: MathExtractor.parseOptions)
        self.document = document
        var ranges = AllowedRanges(text: text)
        ranges.visit(document)
        rootParagraphs = ranges.rootParagraphs
        for segment in ranges.allowed() { scan(segment) }
    }

    private static func mayHoldMath(_ bytes: [UInt8]) -> Bool {
        for index in bytes.indices {
            switch bytes[index] {
            case .dollar: return true
            case .backslash where index + 1 < bytes.count && (bytes[index + 1] == .openParen || bytes[index + 1] == .openBracket): return true
            default: continue
            }
        }
        return false
    }

    private mutating func scan(_ segment: Range<Int>) {
        let end = segment.upperBound
        let reachesEnd = end == bytes.count
        var index = segment.lowerBound
        while index < end {
            switch bytes[index] {
            case .backslash:
                let next = index + 1 < end ? bytes[index + 1] : 0
                if next == .openParen {
                    if let close = closing([.backslash, .closeParen], from: index + 2, before: end, blankLines: false) {
                        add(.parenthesis, index..<close)
                        index = close
                        continue
                    }
                    if reachesEnd, !hasBlankLine(index + 2..<end) { noteUnfinished(.parenthesis, at: index) }
                } else if next == .openBracket, startsLine(index) {
                    if let close = closing([.backslash, .closeBracket], from: index + 2, before: end, blankLines: true) {
                        add(.bracket, index..<close)
                        index = close
                        continue
                    }
                    if reachesEnd { noteUnfinished(.bracket, at: index) }
                }
                index += 2
            case .dollar where index + 1 < end && bytes[index + 1] == .dollar:
                let close = closing([.dollar, .dollar], from: index + 2, before: end, blankLines: true)
                if let close, bytes[(index + 2)..<(close - 2)].contains(where: { !$0.isSpace }) {
                    add(.doubleDollar, index..<close)
                    index = close
                    continue
                }
                if close == nil, reachesEnd { noteUnfinished(.doubleDollar, at: index) }
                index += 2
            case .dollar:
                switch inlineDollar(at: index, before: end) {
                case .formula(let close):
                    add(.dollar, index..<close)
                    index = close
                    continue
                case .open where reachesEnd:
                    noteUnfinished(.dollar, at: index)
                default:
                    break
                }
                index += 1
            default:
                index += 1
            }
        }
    }

    private enum InlineDollar { case formula(end: Int), open, none }

    /// Pandoc's rule for `$…$` on one line, with an opening `$` not glued to a word or number before it.
    private func inlineDollar(at index: Int, before end: Int) -> InlineDollar {
        guard index + 1 < end, !bytes[index + 1].isSpace else { return .none }
        if index > 0, bytes[index - 1].isAlphanumeric { return .none }
        var cursor = index + 1
        while cursor < end {
            switch bytes[cursor] {
            case .backslash: cursor += 2
            case .newline, .carriageReturn: return .none
            case .dollar:
                let closes = !bytes[cursor - 1].isSpace && !(cursor + 1 < bytes.count && bytes[cursor + 1].isDigit)
                return closes ? .formula(end: cursor + 1) : .none
            default: cursor += 1
            }
        }
        return .open
    }

    /// The end of the first unescaped `token` from `start`, staying within one paragraph unless `blankLines`.
    private func closing(_ token: [UInt8], from start: Int, before end: Int, blankLines: Bool) -> Int? {
        var cursor = start
        while cursor + token.count <= end {
            if bytes[cursor] == token[0], bytes[cursor..<(cursor + token.count)].elementsEqual(token) { return cursor + token.count }
            if bytes[cursor] == .backslash {
                cursor += 2
                continue
            }
            if !blankLines, bytes[cursor] == .newline, startsBlankLine(cursor + 1, before: end) { return nil }
            cursor += 1
        }
        return nil
    }

    private func hasBlankLine(_ range: Range<Int>) -> Bool {
        range.contains { bytes[$0] == .newline && startsBlankLine($0 + 1, before: range.upperBound) }
    }

    private func startsBlankLine(_ start: Int, before end: Int) -> Bool {
        var cursor = start
        while cursor < end, bytes[cursor] == .space || bytes[cursor] == .tab || bytes[cursor] == .carriageReturn { cursor += 1 }
        return cursor < end && bytes[cursor] == .newline
    }

    private func lineStart(_ index: Int) -> Int {
        var start = index
        while start > 0, bytes[start - 1] != .newline, bytes[start - 1] != .carriageReturn { start -= 1 }
        return start
    }

    /// Whether only white space and container markers (`>`, list markers) come before `index` on its line.
    private func startsLine(_ index: Int) -> Bool {
        var cursor = lineStart(index)
        func skipSpaces() { while cursor < index, bytes[cursor] == .space || bytes[cursor] == .tab { cursor += 1 } }
        skipSpaces()
        while cursor < index {
            if bytes[cursor] == .greaterThan {
                cursor += 1
            } else if bytes[cursor] == .hyphen || bytes[cursor] == .plus || bytes[cursor] == .asterisk {
                guard cursor + 1 < index, bytes[cursor + 1].isSpace else { return false }
                cursor += 1
            } else if bytes[cursor].isDigit {
                while cursor < index, bytes[cursor].isDigit { cursor += 1 }
                guard cursor + 1 < index, bytes[cursor] == .period || bytes[cursor] == .closeParen, bytes[cursor + 1].isSpace else { return false }
                cursor += 1
            } else {
                return false
            }
            skipSpaces()
        }
        return true
    }

    /// How many `>` markers start the line `index` is on.
    private func quoteDepth(_ index: Int) -> Int {
        var cursor = lineStart(index), depth = 0
        while cursor < index {
            switch bytes[cursor] {
            case .space, .tab: cursor += 1
            case .greaterThan: depth += 1; cursor += 1
            default: return depth
            }
        }
        return depth
    }

    private mutating func add(_ delimiter: MathSpan.Delimiter, _ range: Range<Int>) {
        let (open, close) = delimiter.delimiters
        var tex = Array(bytes[(range.lowerBound + open.utf8.count)..<(range.upperBound - close.utf8.count)])
        let depth = quoteDepth(range.lowerBound)
        if depth > 0 { tex = Self.removingQuoteMarkers(tex, depth: depth) }
        let span = MathSpan(delimiter: delimiter, range: range, tex: String(decoding: tex, as: UTF8.self))
        var replaced = range
        let ownBlock = delimiter.isDisplay && rootParagraphs.contains { $0.contains(range.lowerBound) }
        if ownBlock {
            let floor = spans.last?.replaced.upperBound ?? 0
            while replaced.lowerBound > floor, bytes[replaced.lowerBound - 1] == .space || bytes[replaced.lowerBound - 1] == .tab {
                replaced = (replaced.lowerBound - 1)..<replaced.upperBound
            }
            while replaced.upperBound < bytes.count, bytes[replaced.upperBound] == .space || bytes[replaced.upperBound] == .tab {
                replaced = replaced.lowerBound..<(replaced.upperBound + 1)
            }
        }
        spans.append(Found(span: span, replaced: replaced, ownBlock: ownBlock))
    }

    /// TeX that continues over quoted lines, without the `>` markers that begin them.
    private static func removingQuoteMarkers(_ tex: [UInt8], depth: Int) -> [UInt8] {
        var output: [UInt8] = []
        var index = 0
        var atLineStart = false
        while index < tex.count {
            if atLineStart {
                atLineStart = false
                var cursor = index, removed = 0
                while removed < depth {
                    var probe = cursor
                    while probe < tex.count, tex[probe] == .space || tex[probe] == .tab { probe += 1 }
                    guard probe < tex.count, tex[probe] == .greaterThan else { break }
                    cursor = probe + 1
                    if cursor < tex.count, tex[cursor] == .space { cursor += 1 }
                    removed += 1
                }
                index = cursor
                continue
            }
            output.append(tex[index])
            atLineStart = tex[index] == .newline
            index += 1
        }
        return output
    }

    private mutating func noteUnfinished(_ delimiter: MathSpan.Delimiter, at index: Int) {
        if unfinished == nil { unfinished = .init(delimiter: delimiter, start: index) }
    }
}

/// Where a formula may be, from cmark's parse of the answer as written: inside root blocks or the white space between
/// them, but not in code, HTML, images, link destinations and titles, or link reference definitions.
private struct AllowedRanges: MarkupWalker {
    private let lines: LineStarts
    private let bytes: [UInt8]
    private var roots: [Range<Int>] = []
    private var excluded: [Range<Int>] = []
    private(set) var rootParagraphs: [Range<Int>] = []

    init(text: String) {
        lines = LineStarts(text)
        bytes = Array(text.utf8)
    }

    func allowed() -> [Range<Int>] {
        var merged: [Range<Int>] = []
        for root in roots.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, last.upperBound >= root.lowerBound || bytes[last.upperBound..<root.lowerBound].allSatisfy(\.isSpace) {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, root.upperBound)
            } else {
                merged.append(root)
            }
        }
        // cmark ends the last block before the answer's closing line breaks; a formula still open runs through them.
        if let last = merged.last, bytes[last.upperBound...].allSatisfy(\.isSpace) {
            merged[merged.count - 1] = last.lowerBound..<bytes.count
        }
        let excluded = excluded.sorted { $0.lowerBound < $1.lowerBound }
        return merged.flatMap { range -> [Range<Int>] in
            var pieces: [Range<Int>] = []
            var start = range.lowerBound
            for cut in excluded where cut.overlaps(range) {
                if start < cut.lowerBound { pieces.append(start..<cut.lowerBound) }
                start = max(start, cut.upperBound)
            }
            if start < range.upperBound { pieces.append(start..<range.upperBound) }
            return pieces
        }
    }

    mutating func visitDocument(_ document: Document) {
        for child in document.children {
            guard let range = offsets(child) else { continue }
            let root = lines.lineStart(of: child.range!.lowerBound.line)..<range.upperBound
            roots.append(root)
            if child is Paragraph { rootParagraphs.append(root) }
            visit(child)
        }
    }

    mutating func defaultVisit(_ markup: Markup) { descendInto(markup) }

    mutating func visitCodeBlock(_ code: CodeBlock) { exclude(code) }
    mutating func visitInlineCode(_ code: InlineCode) { exclude(code) }
    mutating func visitHTMLBlock(_ html: HTMLBlock) { exclude(html) }
    mutating func visitInlineHTML(_ html: InlineHTML) { exclude(html) }
    mutating func visitImage(_ image: Image) { exclude(image) }

    mutating func visitLink(_ link: Link) {
        guard let range = offsets(link) else { return }
        let children = Array(link.children)
        let isAutolink = children.count == 1 && (children[0] as? Text).map { [$0.string, "mailto:" + $0.string].contains(link.destination) } == true
        guard !isAutolink, let first = children.first.flatMap(offsets), let last = children.last.flatMap(offsets) else {
            excluded.append(range)
            return
        }
        excluded.append(range.lowerBound..<first.lowerBound)
        excluded.append(last.upperBound..<range.upperBound)
        descendInto(link)
    }

    private mutating func exclude(_ markup: Markup) {
        if let range = offsets(markup) { excluded.append(range) }
    }

    private func offsets(_ markup: Markup) -> Range<Int>? {
        guard let range = markup.range else { return nil }
        let start = lines.offset(of: range.lowerBound)
        return start..<max(start, lines.offset(of: range.upperBound))
    }
}

private extension UInt8 {
    static let newline = UInt8(ascii: "\n"), carriageReturn = UInt8(ascii: "\r"), space = UInt8(ascii: " "), tab = UInt8(ascii: "\t")
    static let dollar = UInt8(ascii: "$"), backslash = UInt8(ascii: "\\"), greaterThan = UInt8(ascii: ">")
    static let openParen = UInt8(ascii: "("), closeParen = UInt8(ascii: ")"), openBracket = UInt8(ascii: "["), closeBracket = UInt8(ascii: "]")
    static let hyphen = UInt8(ascii: "-"), plus = UInt8(ascii: "+"), asterisk = UInt8(ascii: "*"), period = UInt8(ascii: ".")

    var isSpace: Bool { self == .space || self == .tab || self == .newline || self == .carriageReturn }
    var isDigit: Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self) }
    var isAlphanumeric: Bool { isDigit || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(self | 0x20) }
}
