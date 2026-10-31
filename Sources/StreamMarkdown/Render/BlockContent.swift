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
        case .codeBlock:
            return .source(ProseBuilder.source(((markup as? CodeBlock)?.code ?? "").trimmingFinalNewline, style: style))
        case .table, .html, .other:
            let text = source ?? (markup as? HTMLBlock)?.rawHTML ?? markup.format()
            return .source(ProseBuilder.source(text.trimmingCharacters(in: .newlines), style: style))
        }
    }
}

extension String {
    var trimmingFinalNewline: String { hasSuffix("\n") ? String(dropLast()) : self }
}
