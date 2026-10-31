import CoreText
import Foundation
import Markdown
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Builds one prose block (a paragraph, a heading or a whole list) into an attributed string for one text view.
/// Each paragraph inside it gets its own indents and spacing; list markers sit right-aligned on a tab before the text.
struct ProseBuilder: MarkupWalker {

    private struct Marker {
        let text: String
        /// Where the item's line starts, and where its text and continuation lines start.
        let start: CGFloat
        let content: CGFloat
    }

    private let style: ResolvedStyle
    private let output = NSMutableAttributedString()
    private var fonts: [FontSpec: PlatformFont] = [:]

    private var indent: CGFloat = 0
    private var color: PlatformColor
    private var blockFont: FontSpec
    private var listDepth = 0
    private var pendingMarker: Marker?
    /// The space above the next paragraph, when a container sets one; otherwise the style's block spacing.
    private var pendingGap: CGFloat?
    private var paragraphStart = 0
    private var paragraphStyle = NSParagraphStyle()
    private var separatorAttributes: [NSAttributedString.Key: Any] = [:]
    private var headingLevel: Int?

    private var bold = false
    private var italic = false
    private var strikethrough = false
    private var link: URL?

    private init(style: ResolvedStyle, color: PlatformColor?) {
        self.style = style
        self.color = color ?? style.text
        blockFont = style.body
    }

    static func build(_ markup: Markup, style: ResolvedStyle, color: PlatformColor? = nil) -> RichText {
        var builder = ProseBuilder(style: style, color: color)
        builder.visit(markup)
        return RichText(builder.output, headingLevel: (markup as? Heading)?.level)
    }

    /// Text drawn as it is, in the style's monospaced source font.
    static func source(_ text: String, style: ResolvedStyle) -> RichText {
        var builder = ProseBuilder(style: style, color: nil)
        builder.beginParagraph(style.source)
        builder.append(text, font: builder.font(style.source))
        builder.endParagraph()
        return RichText(builder.output)
    }

    // MARK: Blocks

    mutating func visitParagraph(_ paragraph: Paragraph) {
        beginParagraph(style.body)
        descendInto(paragraph)
        endParagraph()
    }

    mutating func visitHeading(_ heading: Heading) {
        beginParagraph(style.heading(heading.level))
        headingLevel = heading.level
        descendInto(heading)
        endParagraph()
    }

    mutating func visitUnorderedList(_ list: UnorderedList) {
        visitList(Array(list.listItems), start: nil)
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        visitList(Array(list.listItems), start: Int(list.startIndex))
    }

    private mutating func visitList(_ items: [ListItem], start: Int?) {
        flushMarker()
        let outer = indent
        let markers = items.indices.map { index -> String in
            if let checkbox = items[index].checkbox { return checkbox == .checked ? "\u{2611}\u{FE0E}" : "\u{2610}\u{FE0E}" }
            if let start { return "\(start + index)." }
            return ["\u{2022}", "\u{25E6}", "\u{25AA}"][listDepth % 3]
        }
        let gap = style.em * 0.4
        let bodyFont = font(style.body)
        let widest = markers.map { width(of: $0, font: bodyFont) }.max() ?? 0
        let content = outer + max(style.style.listIndent * style.em, (widest + 2 * gap).rounded(.up))
        listDepth += 1
        for (item, marker) in zip(items, markers) {
            flushMarker()
            pendingGap = style.style.listItemSpacing * style.em
            pendingMarker = Marker(text: marker, start: outer, content: content)
            indent = content
            for child in item.children { visit(child) }
            flushMarker()
            indent = outer
        }
        listDepth -= 1
        pendingGap = nil
    }

    mutating func visitBlockQuote(_ quote: BlockQuote) {
        flushMarker()
        let (outerIndent, outerColor) = (indent, color)
        indent += style.style.quoteIndent * style.em + style.style.quoteBarWidth
        color = style.quoteText
        descendInto(quote)
        (indent, color) = (outerIndent, outerColor)
    }

    mutating func visitCodeBlock(_ code: CodeBlock) {
        sourceParagraph(code.code.trimmingFinalNewline)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        sourceParagraph(html.rawHTML.trimmingCharacters(in: .newlines))
    }

    mutating func visitTable(_ table: Table) {
        sourceParagraph(table.format())
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        beginParagraph(style.body)
        append("\u{2E3B}", font: font(style.body), color: style.secondaryText)
        endParagraph()
    }

    /// Code, HTML or a table inside a list or quote: monospaced, its lines kept in one paragraph.
    private mutating func sourceParagraph(_ text: String) {
        beginParagraph(style.source)
        var source = attributes(font: font(style.source))
        source[.backgroundColor] = style.inlineCodeBackground
        output.append(NSAttributedString(string: text.replacingOccurrences(of: "\n", with: "\u{2028}"), attributes: source))
        endParagraph()
    }

    // MARK: Inlines

    mutating func visitText(_ text: Text) {
        append(text.string, font: currentFont())
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        let outer = italic
        italic = true
        descendInto(emphasis)
        italic = outer
    }

    mutating func visitStrong(_ strong: Strong) {
        let outer = bold
        bold = true
        descendInto(strong)
        bold = outer
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        let outer = self.strikethrough
        self.strikethrough = true
        descendInto(strikethrough)
        self.strikethrough = outer
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        let spec = FontSpec(size: (blockFont.size * style.style.inlineCodeScale).rounded(), design: .monospaced, weight: bold ? FontSpec.boldWeight : 0)
        var code = attributes(font: font(spec))
        code[.backgroundColor] = style.inlineCodeBackground
        output.append(NSAttributedString(string: inlineCode.code, attributes: code))
    }

    mutating func visitLink(_ link: Link) {
        let outer = self.link
        self.link = link.destination.flatMap(URL.init(string:)) ?? outer
        descendInto(link)
        self.link = outer
    }

    mutating func visitImage(_ image: Image) {
        let outer = (link, color)
        link = link ?? image.source.flatMap(URL.init(string:))
        color = style.secondaryText
        descendInto(image)
        (link, color) = outer
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        append(" ", font: currentFont())
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        append("\u{2028}", font: currentFont())
    }

    mutating func visitInlineHTML(_ html: InlineHTML) {
        let isBreak = html.rawHTML.lowercased().filter { !$0.isWhitespace }.wholeMatch(of: /<br\/?>/) != nil
        append(isBreak ? "\u{2028}" : html.rawHTML, font: currentFont())
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
        append(symbolLink.destination ?? "", font: currentFont())
    }

    // MARK: Output

    private mutating func currentFont() -> PlatformFont {
        var spec = blockFont
        if bold { spec.weight = max(spec.weight, FontSpec.boldWeight) }
        spec.italic = italic
        return font(spec)
    }

    private mutating func font(_ spec: FontSpec) -> PlatformFont {
        if let font = fonts[spec] { return font }
        let font = spec.font
        fonts[spec] = font
        return font
    }

    private func attributes(font: PlatformFont, color: PlatformColor? = nil) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color ?? self.color]
        if strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link {
            attributes[.link] = link
            attributes[.foregroundColor] = style.link
        }
        return attributes
    }

    private func append(_ string: String, font: PlatformFont, color: PlatformColor? = nil) {
        output.append(NSAttributedString(string: string, attributes: attributes(font: font, color: color)))
    }

    private mutating func beginParagraph(_ spec: FontSpec) {
        let gap = output.length == 0 ? 0 : pendingGap ?? style.style.blockSpacing * style.em
        pendingGap = nil
        if output.length > 0 { output.append(NSAttributedString(string: "\n", attributes: separatorAttributes)) }
        paragraphStart = output.length
        blockFont = spec
        headingLevel = nil
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = (spec.size * style.style.lineSpacing).rounded()
        paragraph.paragraphSpacingBefore = gap
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        if let marker = pendingMarker {
            pendingMarker = nil
            paragraph.firstLineHeadIndent = marker.start
            paragraph.headIndent = marker.content
            paragraph.tabStops = [
                NSTextTab(textAlignment: .right, location: marker.content - style.em * 0.4),
                NSTextTab(textAlignment: .left, location: marker.content),
            ]
            let markerFont = font(FontSpec(size: style.body.size, design: style.body.design, weight: style.body.weight))
            output.append(NSAttributedString(string: "\t\(marker.text)\t", attributes: [.font: markerFont, .foregroundColor: color]))
        }
        paragraphStyle = paragraph
    }

    private mutating func endParagraph() {
        let range = NSRange(location: paragraphStart, length: output.length - paragraphStart)
        output.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        #if canImport(UIKit)
        if let headingLevel { output.addAttribute(.accessibilityTextHeadingLevel, value: headingLevel, range: range) }
        #endif
        separatorAttributes = [.font: font(blockFont), .paragraphStyle: paragraphStyle]
        blockFont = style.body
        headingLevel = nil
    }

    /// An item whose first block is not text (a nested list, a quote, or nothing) gets its marker on a line of its own.
    private mutating func flushMarker() {
        guard pendingMarker != nil else { return }
        beginParagraph(style.body)
        endParagraph()
    }

    private func width(of text: String, font: PlatformFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
