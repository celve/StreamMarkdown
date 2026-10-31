import CoreText
import Foundation
import Markdown
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A code block as drawn: its language, its code as written, and the code's text.
struct CodeContent: Sendable {
    let language: String?
    /// The code as written, for the copy button.
    let code: String
    let text: RichText
    let isHighlighted: Bool
}

/// Builds a code block's text: monospaced, tabs four spaces wide, coloured by ``CodeHighlighter`` when `highlighted`.
enum CodeBuilder {
    static func build(_ block: CodeBlock, highlighted: Bool, style: ResolvedStyle) -> CodeContent {
        let language = block.language.flatMap { $0.isEmpty ? nil : $0 }
        let code = block.code.trimmingFinalNewline
        let regular = style.source.font
        var boldSpec = style.source
        boldSpec.weight = PlatformFont.Weight.semibold.rawValue
        let bold = boldSpec.font

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = (style.source.size * style.style.lineSpacing).rounded()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = 4 * width(of: " ", font: regular)
        let text = NSMutableAttributedString(string: code, attributes: [.font: regular, .foregroundColor: style.text, .paragraphStyle: paragraph])
        let tokens = highlighted ? CodeHighlighter.tokens(code, language: language) : nil
        for token in tokens ?? [] {
            text.addAttribute(.foregroundColor, value: style.codeColor(token.kind), range: token.range)
            if token.kind == .keyword { text.addAttribute(.font, value: bold, range: token.range) }
        }
        return CodeContent(language: language, code: code, text: RichText(text), isHighlighted: tokens != nil)
    }

    private static func width(of text: String, font: PlatformFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
