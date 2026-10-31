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
    /// Display formulas, each centred on its own line.
    case math([DisplayFormula])
}

/// A display formula as SwiftMath drew it, or its source when SwiftMath could not.
struct DisplayFormula: @unchecked Sendable, Identifiable {
    let id: Int
    let tex: String
    let rendered: RenderedMath?
    let fallback: RichText
    let color: PlatformColor
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
    /// `math` holds the formulas the markup's text names by placeholder.
    static func render(_ markup: Markup, kind: BlockKind, source: String?, style: ResolvedStyle, color: PlatformColor? = nil, math: MathTable = .empty) -> BlockContent {
        switch kind {
        case .paragraph, .heading, .unorderedList, .orderedList:
            return .text(ProseBuilder.build(markup, style: style, color: color, math: math))
        case .displayMath:
            return .math(displayFormulas(markup, style: style, color: color ?? style.text, math: math))
        case .blockQuote:
            return .quote(markup.children.enumerated().map { index, child in
                let kind = BlockKind(child, math: math)
                return QuotedBlock(id: index, kind: kind, content: render(child, kind: kind, source: nil, style: style, color: style.quoteText, math: math))
            })
        case .thematicBreak:
            return .rule
        case .codeBlock, .table, .html, .other:
            return .source(ProseBuilder.source(sourceText(markup, kind: kind, source: source, math: math), style: style))
        }
    }

    /// Everything `render` reads from a block besides the style: its source text where it draws that, else its tree.
    static func inputs(_ markup: Markup, kind: BlockKind, source: String?, math: MathTable = .empty) -> String {
        switch kind {
        case .table, .html, .other:
            return sourceText(markup, kind: kind, source: source, math: math)
        default:
            var inputs = RenderInputs(math: math)
            inputs.visit(markup)
            return inputs.written
        }
    }

    private static func displayFormulas(_ markup: Markup, style: ResolvedStyle, color: PlatformColor, math: MathTable) -> [DisplayFormula] {
        let spans = markup.children.compactMap { $0 as? Text }.flatMap { text in
            math.segments(text.string).compactMap { segment -> MathSpan? in
                if case .math(let span) = segment { span } else { nil }
            }
        }
        return spans.enumerated().map { index, span in
            DisplayFormula(
                id: index,
                tex: span.label,
                rendered: MathRenderer.render(span.tex, fontSize: style.body.size * style.style.mathScale, display: true),
                fallback: ProseBuilder.source(span.source, style: style),
                color: color
            )
        }
    }

    private static func sourceText(_ markup: Markup, kind: BlockKind, source: String?, math: MathTable) -> String {
        if case .codeBlock = kind { return ((markup as? CodeBlock)?.code ?? "").trimmingFinalNewline }
        return (source ?? (markup as? HTMLBlock)?.rawHTML ?? math.restoring(markup.format())).trimmingCharacters(in: .newlines)
    }
}

/// A tree written out with every field `ProseBuilder` and `BlockRenderer` read, each value length-prefixed, so trees that
/// would render differently never write the same string. A field a renderer starts reading belongs here too.
struct RenderInputs: MarkupWalker {
    private(set) var written = ""
    /// Placeholders are written as their formula's source, never their index, so a key names its content.
    let math: MathTable

    init(math: MathTable = .empty) {
        self.math = math
    }

    mutating func defaultVisit(_ markup: Markup) {
        node(markup)
    }

    mutating func visitText(_ text: Text) {
        written += "Text("
        for segment in math.segments(text.string) {
            switch segment {
            case .text(let run): written += Self.value(String(run))
            case .math(let span): written += "$" + Self.value(span.source)
            }
        }
        written += ")"
    }

    mutating func visitInlineCode(_ code: InlineCode) { node(code, code.code) }
    mutating func visitInlineHTML(_ html: InlineHTML) { node(html, html.rawHTML) }
    mutating func visitHTMLBlock(_ html: HTMLBlock) { node(html, html.rawHTML) }
    mutating func visitCodeBlock(_ code: CodeBlock) { node(code, code.language ?? "\u{0}", code.code) }
    mutating func visitTable(_ table: Table) { written += "Table(\(Self.value(math.restoring(table.format()))))" }
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
