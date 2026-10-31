import Markdown

/// What a root block of the answer is, as swift-markdown parsed it.
public enum BlockKind: Hashable, Sendable {
    case paragraph
    case heading(level: Int)
    case unorderedList
    case orderedList
    case blockQuote
    case thematicBreak
    case codeBlock(language: String?)
    /// A paragraph of display formulas and nothing else.
    case displayMath
    case table
    case html
    /// Anything else swift-markdown may produce, drawn as its source.
    case other

    init(_ markup: Markup) {
        switch markup {
        case is Paragraph: self = .paragraph
        case let heading as Heading: self = .heading(level: heading.level)
        case is UnorderedList: self = .unorderedList
        case is OrderedList: self = .orderedList
        case is BlockQuote: self = .blockQuote
        case is ThematicBreak: self = .thematicBreak
        case let code as CodeBlock: self = .codeBlock(language: code.language)
        case is Table: self = .table
        case is HTMLBlock: self = .html
        default: self = .other
        }
    }

    init(_ markup: Markup, math: MathTable) {
        self = math.isDisplayOnly(markup) ? .displayMath : BlockKind(markup)
    }
}

/// A root block of one parse: its place among the root blocks, its kind, where its source lies, and its parsed tree.
struct ParsedBlock {
    let index: Int
    let kind: BlockKind
    /// UTF-8 offsets into the answer, from the start of the block's first line.
    let range: Range<Int>
    let source: String
    let markup: Markup
    /// The formulas of the parse, which the markup's text names by placeholder.
    let math: MathTable

    /// Its key as a finished block.
    var key: BlockKey { key(RenderContext()) }

    func key(_ context: RenderContext) -> BlockKey {
        BlockKey(kind: kind, inputs: BlockRenderer.inputs(markup, kind: kind, source: source, math: math, context: context))
    }
}

/// Everything a block's rendering reads besides the style: two blocks with equal keys render alike.
struct BlockKey: Hashable, Sendable {
    let kind: BlockKind
    let inputs: String
}

enum BlockParser {
    /// The answer's root blocks, parsed whole by cmark-gfm so every block sees the answer's link reference definitions.
    /// Formulas are taken out first, so cmark never reads TeX as Markdown; ranges and sources are still the answer's.
    static func parse(_ text: String) -> [ParsedBlock] {
        let extraction = MathExtractor.extract(text)
        let lines = LineStarts(extraction.text)
        let bytes = Array(extraction.text.utf8)
        var blocks: [ParsedBlock] = []
        var previousEnd = 0
        for markup in extraction.document.children {
            let range: Range<Int>
            if let sourceRange = markup.range {
                let start = max(lines.lineStart(of: sourceRange.lowerBound.line), previousEnd)
                // cmark ends a list or rule after its line break when a blank line follows, but not at the end of the text.
                var end = max(start, lines.offset(of: sourceRange.upperBound))
                while end > start, bytes[end - 1] == UInt8(ascii: "\n") || bytes[end - 1] == UInt8(ascii: "\r") { end -= 1 }
                range = start..<end
            } else {
                range = previousEnd..<previousEnd
            }
            previousEnd = range.upperBound
            let answerRange = extraction.answerOffset(range.lowerBound)..<extraction.answerOffset(range.upperBound)
            let utf8 = text.utf8
            let source = String(text[utf8.index(utf8.startIndex, offsetBy: answerRange.lowerBound)..<utf8.index(utf8.startIndex, offsetBy: answerRange.upperBound)])
            let kind = BlockKind(markup, math: extraction.math)
            blocks.append(ParsedBlock(index: blocks.count, kind: kind, range: answerRange, source: source, markup: markup, math: extraction.math))
        }
        return blocks
    }
}

/// UTF-8 offsets of the answer's line starts, for turning cmark's line and byte column into an offset.
struct LineStarts {
    private let starts: [Int]
    private let count: Int

    init(_ text: String) {
        var starts = [0]
        var offset = 0
        var previousWasCR = false
        for byte in text.utf8 {
            offset += 1
            if byte == UInt8(ascii: "\n") {
                if previousWasCR { starts[starts.count - 1] = offset } else { starts.append(offset) }
            } else if byte == UInt8(ascii: "\r") {
                starts.append(offset)
            }
            previousWasCR = byte == UInt8(ascii: "\r")
        }
        self.starts = starts
        count = offset
    }

    func lineStart(of line: Int) -> Int {
        starts[min(max(line - 1, 0), starts.count - 1)]
    }

    /// cmark's 1-based line and byte column as an offset, kept within the line it names.
    func offset(of location: SourceLocation) -> Int {
        let line = min(max(location.line - 1, 0), starts.count - 1)
        let lineEnd = line + 1 < starts.count ? starts[line + 1] : count
        return min(starts[line] + max(location.column - 1, 0), lineEnd)
    }
}
