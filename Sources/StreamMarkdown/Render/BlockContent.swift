import Foundation
import Markdown

/// What a block draws as. A piece that renders another kind natively (math, code, tables) adds a case here, a branch in
/// ``BlockRenderer/render(_:kind:source:style:color:context:cells:)``, and a view for it in `BlockContentView`.
enum BlockContent: Sendable {
    /// Prose in one text view: a paragraph, a heading or a whole list.
    case text(RichText)
    /// A bar beside the quote's own blocks.
    case quote([QuotedBlock])
    case rule
    /// A code block, under a header with its language and a copy button.
    case code(CodeContent)
    case table(TableContent)
    /// A list whose items hold code blocks or tables: its text cut around them, each piece at its indent.
    case stack([StackItem])
    /// Monospaced source, for what no renderer handles natively: HTML.
    case source(RichText)

    /// A table's cell texts by their keys, for the next parse of the same block to keep.
    var tableCells: [String: RichText] {
        guard case .table(let table) = self else { return [:] }
        var cells: [String: RichText] = [:]
        for row in table.rows { for cell in row { cells[cell.key] = cell.text } }
        return cells
    }
}

struct QuotedBlock: Sendable, Identifiable {
    let id: Int
    let kind: BlockKind
    let content: BlockContent
}

struct StackItem: Sendable, Identifiable {
    let id: Int
    /// In points: the space above it, and its indent from the block's leading edge.
    let gap: CGFloat
    let indent: CGFloat
    let content: BlockContent
}

/// A built attributed string. Never mutated after the build, so it crosses from the parse job to the main thread.
final class RichText: @unchecked Sendable {
    let string: NSAttributedString
    let headingLevel: Int?

    init(_ string: NSAttributedString, headingLevel: Int? = nil) {
        self.string = string
        self.headingLevel = headingLevel
    }
}

/// Where a block stands in the stream: what its rendering decides beyond its tree.
struct RenderContext: Hashable, Sendable {
    /// The block is the last of an answer still arriving, so its end may still grow.
    var isOpenTail = false
    /// Highlighting waits for a parse off the main thread, for an answer laid out on it at once.
    var defersHighlighting = false

    /// Whether a code block draws highlighted: once nothing more can arrive inside it. `rootSource` is the source of
    /// the root block holding it, or nil when its markers prefix every line.
    func highlights(_ code: CodeBlock, rootSource: String?) -> Bool {
        if defersHighlighting { return false }
        guard isOpenTail, code.isLastInRootBlock else { return true }
        return code.parent is Document && rootSource.map(CodeFence.isClosed) == true
    }
}

/// Turns a parsed block into what it draws as: the seam later pieces extend.
enum BlockRenderer {
    /// `source` is the block's text in the answer, or nil inside a quote, where the quote's markers prefix every line.
    /// `cells` are the cell texts of this block's last parse, which a table keeps where a cell is unchanged.
    static func render(_ markup: Markup, kind: BlockKind, source: String?, style: ResolvedStyle, color: PlatformColor? = nil,
                       context: RenderContext = RenderContext(), cells: [String: RichText] = [:]) -> BlockContent {
        switch kind {
        case .paragraph, .heading:
            return .text(ProseBuilder.build(markup, style: style, color: color))
        case .unorderedList, .orderedList:
            return ProseBuilder.content(markup, style: style, color: color, context: context)
        case .blockQuote:
            return .quote(markup.children.enumerated().map { index, child in
                let kind = BlockKind(child)
                let content = render(child, kind: kind, source: nil, style: style, color: style.quoteText, context: context)
                return QuotedBlock(id: index, kind: kind, content: content)
            })
        case .thematicBreak:
            return .rule
        case .codeBlock:
            guard let code = markup as? CodeBlock else { return .source(ProseBuilder.source(markup.format(), style: style)) }
            return .code(CodeBuilder.build(code, highlighted: context.highlights(code, rootSource: source), style: style))
        case .table:
            guard let table = markup as? Table else { return .source(ProseBuilder.source(markup.format(), style: style)) }
            return .table(TableBuilder.build(table, style: style, color: color, reusing: cells))
        case .html, .other:
            return .source(ProseBuilder.source(sourceText(markup, source: source), style: style))
        }
    }

    /// Everything `render` reads from a block besides the style: its source text where it draws that, else its tree.
    static func inputs(_ markup: Markup, kind: BlockKind, source: String?, context: RenderContext) -> String {
        switch kind {
        case .html, .other:
            return sourceText(markup, source: source)
        default:
            var inputs = RenderInputs(context: context, rootSource: source)
            inputs.visit(markup)
            return inputs.written
        }
    }

    private static func sourceText(_ markup: Markup, source: String?) -> String {
        (source ?? (markup as? HTMLBlock)?.rawHTML ?? markup.format()).trimmingCharacters(in: .newlines)
    }
}

/// A tree written out with every field `ProseBuilder` and `BlockRenderer` read, each value length-prefixed, so trees that
/// would render differently never write the same string. A field a renderer starts reading belongs here too.
struct RenderInputs: MarkupWalker {
    private(set) var written = ""
    private let context: RenderContext
    private let rootSource: String?

    init(context: RenderContext = RenderContext(), rootSource: String? = nil) {
        self.context = context
        self.rootSource = rootSource
    }

    static func of(_ markup: Markup) -> String {
        var inputs = RenderInputs()
        inputs.visit(markup)
        return inputs.written
    }

    mutating func defaultVisit(_ markup: Markup) {
        node(markup)
    }

    mutating func visitText(_ text: Text) { node(text, text.string) }
    mutating func visitInlineCode(_ code: InlineCode) { node(code, code.code) }
    mutating func visitInlineHTML(_ html: InlineHTML) { node(html, html.rawHTML) }
    mutating func visitHTMLBlock(_ html: HTMLBlock) { node(html, html.rawHTML) }
    /// Code in a language the highlighter knows draws differently once highlighted, so that decision is an input too.
    mutating func visitCodeBlock(_ code: CodeBlock) {
        let highlighted = CodeHighlighter.knows(code.language) && context.highlights(code, rootSource: rootSource)
        node(code, code.language ?? "\u{0}", code.code, highlighted ? "highlighted" : "plain")
    }
    mutating func visitTable(_ table: Table) { node(table, table.columnAlignments.map { $0.name }.joined(separator: ",")) }
    mutating func visitLink(_ link: Link) { node(link, link.destination ?? "\u{0}") }
    mutating func visitImage(_ image: Image) { node(image, image.source ?? "\u{0}") }
    mutating func visitSymbolLink(_ link: SymbolLink) { node(link, link.destination ?? "\u{0}") }
    mutating func visitHeading(_ heading: Heading) { node(heading, "\(heading.level)") }
    mutating func visitOrderedList(_ list: OrderedList) { node(list, "\(list.startIndex)") }
    mutating func visitListItem(_ item: ListItem) { node(item, item.checkbox.map { $0 == .checked ? "x" : " " } ?? "") }

    private mutating func node(_ markup: Markup, _ values: String...) {
        written += "\(type(of: markup))("
        for value in values { written += Self.value(value) }
        descendInto(markup)
        written += ")"
    }

    private static func value(_ value: String) -> String { "\(value.utf8.count):\(value)" }
}

/// A fenced code block's fences, read from its source.
enum CodeFence {
    /// Whether the block's source ends with a fence that closes its opening one.
    static func isClosed(_ source: String) -> Bool {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard lines.count >= 2, let open = fence(lines[0]), let close = fence(lines[lines.count - 1]) else { return false }
        return close.marker == open.marker && close.length >= open.length && close.rest.allSatisfy(\.isWhitespace)
    }

    private static func fence(_ line: Substring) -> (marker: Character, length: Int, rest: Substring)? {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3, let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let run = trimmed.prefix { $0 == marker }
        guard run.count >= 3 else { return nil }
        return (marker, run.count, trimmed.dropFirst(run.count))
    }
}

extension Markup {
    /// Whether nothing follows it inside its root block: it is the last child at every level up to the document.
    var isLastInRootBlock: Bool {
        var markup: Markup = self
        while let parent = markup.parent, !(parent is Document) {
            guard markup.indexInParent == parent.childCount - 1 else { return false }
            markup = parent
        }
        return true
    }
}

extension Table.ColumnAlignment? {
    var name: String {
        switch self {
        case .left: "l"
        case .center: "c"
        case .right: "r"
        case nil: "-"
        }
    }
}

extension String {
    var trimmingFinalNewline: String { hasSuffix("\n") ? String(dropLast()) : self }
}
