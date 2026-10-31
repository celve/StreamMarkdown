import Foundation
import Markdown

/// What a block draws as. A piece that renders another kind natively (math, code, tables) adds a case here, a branch in
/// ``BlockRenderer/render(_:kind:source:style:)``, and a view for it in `BlockView`.
enum BlockContent: Sendable {
    /// Prose in one text view: a paragraph, a heading or a whole list.
    case text(RichText)
    /// A bar beside the quote's own blocks.
    case quote([QuotedBlock])
    case rule
    /// Monospaced source, for what no renderer handles yet: code blocks, tables and HTML.
    case source(RichText)
}

struct QuotedBlock: Sendable, Identifiable {
    let id: Int
    let kind: BlockKind
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

/// Turns a parsed block into what it draws as: the seam later pieces extend.
enum BlockRenderer {
    /// `source` is the block's text in the answer, or nil inside a quote, where the quote's markers prefix every line.
    static func render(_ markup: Markup, kind: BlockKind, source: String?, style: ResolvedStyle, color: PlatformColor? = nil) -> BlockContent {
        switch kind {
        case .paragraph, .heading, .unorderedList, .orderedList:
            return .text(ProseBuilder.build(markup, style: style, color: color))
        case .blockQuote:
            return .quote(markup.children.enumerated().map { index, child in
                let kind = BlockKind(child)
                return QuotedBlock(id: index, kind: kind, content: render(child, kind: kind, source: nil, style: style, color: style.quoteText))
            })
        case .thematicBreak:
            return .rule
        case .codeBlock, .table, .html, .other:
            return .source(ProseBuilder.source(sourceText(markup, kind: kind, source: source), style: style))
        }
    }

    /// Everything `render` reads from a block besides the style: its source text where it draws that, else its tree.
    static func inputs(_ markup: Markup, kind: BlockKind, source: String?) -> String {
        switch kind {
        case .table, .html, .other:
            return sourceText(markup, kind: kind, source: source)
        default:
            var inputs = RenderInputs()
            inputs.visit(markup)
            return inputs.written
        }
    }

    private static func sourceText(_ markup: Markup, kind: BlockKind, source: String?) -> String {
        if case .codeBlock = kind { return ((markup as? CodeBlock)?.code ?? "").trimmingFinalNewline }
        return (source ?? (markup as? HTMLBlock)?.rawHTML ?? markup.format()).trimmingCharacters(in: .newlines)
    }
}

/// A tree written out with every field `ProseBuilder` and `BlockRenderer` read, each value length-prefixed, so trees that
/// would render differently never write the same string. A field a renderer starts reading belongs here too.
struct RenderInputs: MarkupWalker {
    private(set) var written = ""

    mutating func defaultVisit(_ markup: Markup) {
        node(markup)
    }

    mutating func visitText(_ text: Text) { node(text, text.string) }
    mutating func visitInlineCode(_ code: InlineCode) { node(code, code.code) }
    mutating func visitInlineHTML(_ html: InlineHTML) { node(html, html.rawHTML) }
    mutating func visitHTMLBlock(_ html: HTMLBlock) { node(html, html.rawHTML) }
    mutating func visitCodeBlock(_ code: CodeBlock) { node(code, code.language ?? "\u{0}", code.code) }
    mutating func visitTable(_ table: Table) { written += "Table(\(Self.value(table.format())))" }
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

extension String {
    var trimmingFinalNewline: String { hasSuffix("\n") ? String(dropLast()) : self }
}
