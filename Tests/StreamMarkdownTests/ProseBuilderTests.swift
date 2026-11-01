import AppKit
import Markdown
@testable import StreamMarkdown
import Testing

struct ProseBuilderTests {
    let style = ResolvedStyle(RenderEnvironment())

    @Test func paragraphIsSerifBodyText() throws {
        let text = build("Plain words.")
        #expect(text.string.string == "Plain words.")
        let font = try #require(font(text, at: 0))
        #expect(font.pointSize == style.body.size)
        #expect(font.fontName.contains("NewYork"), "the body face is the system serif, got \(font.fontName)")
        #expect(color(text, at: 0) == style.text)
    }

    @Test func headingsUseTheirLevelsFontAndReportTheLevel() throws {
        let h2 = build("## Results")
        #expect(h2.string.string == "Results")
        #expect(h2.headingLevel == 2)
        let font = try #require(font(h2, at: 0))
        #expect(font.pointSize == style.heading(2).size)
        #expect(font.pointSize > style.body.size)
        #expect(font.fontName.contains("NewYork"), "headings are in the answer's serif face, as Claude sets them")
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(build("Text").headingLevel == nil)
    }

    @Test func emphasisStrongAndStrikethroughStyleTheirRuns() throws {
        let text = build("a *b* **c** ~~d~~ ***e***")
        #expect(text.string.string == "a b c d e")
        let italic = try #require(font(text, at: 2)), bold = try #require(font(text, at: 4))
        #expect(italic.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(!italic.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(bold.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(text.string.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(text.string.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) == nil)
        let both = try #require(font(text, at: 8)).fontDescriptor.symbolicTraits
        #expect(both.contains(.bold) && both.contains(.italic))
    }

    @Test func inlineCodeIsMonospacedOnAChip() throws {
        let text = build("Use `W_q` here")
        let code = try #require(font(text, at: 4))
        #expect(code.fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(code.pointSize < style.body.size)
        #expect(color(text, at: 4) == style.inlineCodeText)
        let chip = try #require(text.string.attribute(.streamMarkdownInlineCode, at: 4, effectiveRange: nil) as? InlineCodeChip)
        #expect(chip.fill == style.inlineCodeBackground)
        #expect(text.string.attribute(.streamMarkdownInlineCode, at: 0, effectiveRange: nil) == nil)
        #expect(text.string.attribute(.backgroundColor, at: 4, effectiveRange: nil) == nil)
        #expect(text.string.attribute(.kern, at: 3, effectiveRange: nil) as? CGFloat == chip.padding, "room before the chip")
        #expect(text.string.attribute(.kern, at: 6, effectiveRange: nil) as? CGFloat == chip.padding, "room after it")
        #expect(text.string.attribute(.kern, at: 5, effectiveRange: nil) == nil)
    }

    @Test func aChipCoversItsCodeAndStaysClearOfTheTextAroundIt() throws {
        let fragment = try #require(layOut(build("Use `W_q` here").string) as? InlineCodeFragment)
        let line = try #require(fragment.textLineFragments.first)
        let chip = try #require(fragment.chips().first)
        let x = { (index: Int) in line.typographicBounds.minX + line.locationForCharacter(at: index).x }
        #expect(chip.rect.minX == x(4) - chip.style.padding, "starts its padding before W")
        #expect(chip.rect.minX > x(3), "after the space before it, which the builder widened")
        #expect(chip.rect.maxX == x(7), "ends where the space after it starts")
        #expect(chip.rect.minY >= line.typographicBounds.minY - 2 && chip.rect.maxY <= line.typographicBounds.maxY + 2)
        #expect(fragment.chips().count == 1)
        #expect(!(layOut(build("No code here").string) is InlineCodeFragment))
    }

    @Test func codeAtALinesStartKeepsItsChipInsideTheText() throws {
        let fragment = try #require(layOut(build("`start` of a line").string) as? InlineCodeFragment)
        let chip = try #require(fragment.chips().first)
        #expect(chip.rect.minX == 0)
        #expect(build("`start` of a line").string.attribute(.kern, at: 0, effectiveRange: nil) == nil, "nothing before it to kern")
    }

    @Test(arguments: [("שלום `abc` עולם", "abc", 320.0), ("Use `אבג` here", "אבג", 320.0), ("שלום עולם `abc xyz` עוד", "abc xyz", 100.0)])
    func aChipCoversEveryCodeCharacterWhereTheDirectionChanges(_ markdown: String, code: String, width: Double) throws {
        let text = build(markdown).string
        let fragment = try #require(layOut(text, width: width) as? InlineCodeFragment)
        let layout = try #require(fragment.textLayoutManager)
        let chips = fragment.chips().map(\.rect)
        let code = (text.string as NSString).range(of: code)
        for index in code.location..<code.upperBound where (text.string as NSString).character(at: index) != 0x20 {
            let range = try #require(NSTextRange(NSRange(location: index, length: 1), in: layout.textContentManager!))
            var center: CGPoint?
            layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, segment, _, _ in
                center = CGPoint(x: segment.midX - fragment.layoutFragmentFrame.minX, y: segment.midY - fragment.layoutFragmentFrame.minY)
                return false
            }
            let point = try #require(center)
            #expect(chips.contains { $0.contains(point) }, "character \(index) of \(markdown.debugDescription) is on no chip: \(chips)")
        }
        #expect(chips.allSatisfy { $0.width > 4 }, "no chip is just its padding: \(chips)")
    }

    @Test func linksAreUnderlinedInTheLinkColour() {
        let text = build("See [the paper](https://arxiv.org/abs/2106.09685).")
        #expect(color(text, at: 4) == style.link)
        #expect(text.string.attribute(.underlineStyle, at: 4, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(text.string.attribute(.underlineColor, at: 4, effectiveRange: nil) as? NSColor == style.linkUnderline)
        #expect(text.string.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
    }

    @Test func linksCarryTheirURL() {
        let text = build("See [the paper](https://arxiv.org/abs/2106.09685) and <https://duoxiv.app>.")
        #expect(text.string.string == "See the paper and https://duoxiv.app.")
        #expect(text.string.attribute(.link, at: 4, effectiveRange: nil) as? URL == URL(string: "https://arxiv.org/abs/2106.09685"))
        #expect(text.string.attribute(.link, at: 18, effectiveRange: nil) as? URL == URL(string: "https://duoxiv.app"))
        #expect(text.string.attribute(.link, at: 0, effectiveRange: nil) == nil)
        #expect(color(text, at: 4) == style.link)
    }

    @Test func softBreaksAreSpacesAndHardBreaksStayInTheParagraph() {
        #expect(build("one\ntwo").string.string == "one two")
        #expect(build("one  \ntwo\\\nthree").string.string == "one\u{2028}two\u{2028}three")
        #expect(build("one<br>two").string.string == "one\u{2028}two")
    }

    @Test func nestedListsGetMarkersAndDeeperIndents() throws {
        let text = build("- one\n  - nested\n    - deeper\n- two")
        #expect(text.string.string == "\t\u{2022}\tone\n\t\u{25E6}\tnested\n\t\u{25AA}\tdeeper\n\t\u{2022}\ttwo")
        let levels = try [0, 1, 2].map { line in try #require(paragraph(text, line: line)) }
        #expect(levels[0].firstLineHeadIndent == 0)
        #expect(levels[1].firstLineHeadIndent == levels[0].headIndent, "a nested marker starts where its parent's text does")
        #expect(levels[2].firstLineHeadIndent == levels[1].headIndent)
        #expect(levels[1].headIndent > levels[0].headIndent)
        #expect(levels[0].tabStops.map(\.location) == [levels[0].headIndent - style.em * 0.4, levels[0].headIndent])
        #expect(levels[0].tabStops.first?.alignment == .right)
        #expect(levels[0].paragraphSpacingBefore == 0)
        #expect(levels[1].paragraphSpacingBefore == style.style.listItemSpacing * style.em)
    }

    @Test func orderedListsCountFromTheirStartAndFitWideMarkers() throws {
        #expect(build("7. seven\n8. eight").string.string == "\t7.\tseven\n\t8.\teight")
        let long = build((1...12).map { "\($0). item" }.joined(separator: "\n"))
        #expect(long.string.string.hasSuffix("\t12.\titem"))
        let paragraph = try #require(paragraph(long, line: 0))
        let markerFont = try #require(font(long, at: 1))
        let width = NSAttributedString(string: "12.", attributes: [.font: markerFont]).size().width
        #expect(paragraph.headIndent - style.em * 0.4 >= width, "the right-aligned marker fits before the text")
    }

    @Test func taskItemsShowTheirState() {
        #expect(build("- [x] done\n- [ ] todo").string.string == "\t\u{2611}\u{FE0E}\tdone\n\t\u{2610}\u{FE0E}\ttodo")
    }

    @Test func looseItemsKeepTheirParagraphsAtTheTextIndent() throws {
        let text = build("1. first\n\n   second paragraph\n2. next")
        #expect(text.string.string == "\t1.\tfirst\nsecond paragraph\n\t2.\tnext")
        let first = try #require(paragraph(text, line: 0)), second = try #require(paragraph(text, line: 1))
        #expect(second.firstLineHeadIndent == first.headIndent)
        #expect(second.paragraphSpacingBefore == style.style.blockSpacing * style.em)
    }

    @Test func anItemThatStartsWithAListGetsItsMarkerOnItsOwnLine() {
        #expect(build("- - inner").string.string == "\t\u{2022}\t\n\t\u{25E6}\tinner")
        #expect(build("- \n- b").string.string == "\t\u{2022}\t\n\t\u{2022}\tb")
    }

    @Test func quotesAndHTMLInsideAnItemStayInItsText() throws {
        let text = build("- item\n\n  > quoted\n\n  <div>\n  html\n  </div>")
        #expect(text.string.string == "\t\u{2022}\titem\nquoted\n<div>\u{2028}html\u{2028}</div>")
        let item = try #require(paragraph(text, line: 0)), quote = try #require(paragraph(text, line: 1))
        #expect(quote.headIndent > item.headIndent)
        #expect(color(text, at: 8) == style.quoteText)
        #expect(try #require(font(text, at: 15)).fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    @Test func quotesRenderTheirOwnBlocks() throws {
        let document = Document(parsing: "> First\n>\n> - item\n>\n> ---")
        let quote = try #require(document.child(at: 0))
        guard case .quote(let blocks) = BlockRenderer.render(quote, kind: .blockQuote, source: "", style: style, math: .empty) else {
            Issue.record("not a quote")
            return
        }
        #expect(blocks.map(\.kind) == [.paragraph, .unorderedList, .thematicBreak])
        guard case .text(let first) = blocks[0].content else { Issue.record("not text"); return }
        #expect(first.string.string == "First")
        #expect(color(first, at: 0) == style.quoteText)
        guard case .rule = blocks[2].content else { Issue.record("not a rule"); return }
    }

    @Test func htmlFallsBackToItsSource() throws {
        let html = try render("<details>x</details>", kind: .html)
        #expect(html.string.string == "<details>x</details>")
        #expect(try #require(font(html, at: 0)).fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    private func build(_ markdown: String) -> RichText {
        let document = Document(parsing: markdown, options: [.disableSmartOpts])
        let block = document.child(at: 0) ?? document
        guard case .text(let text) = ProseBuilder.content(block, style: style, math: .empty) else {
            Issue.record("\(markdown) did not build into one text")
            return RichText(NSAttributedString())
        }
        return text
    }

    private func render(_ markdown: String, kind: BlockKind) throws -> RichText {
        let markup = try #require(Document(parsing: markdown).child(at: 0))
        guard case .source(let text) = BlockRenderer.render(markup, kind: kind, source: markdown, style: style, math: .empty) else {
            throw RenderError.notSource
        }
        return text
    }

    private enum RenderError: Error { case notSource }

    private func font(_ text: RichText, at index: Int) -> NSFont? {
        text.string.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func color(_ text: RichText, at index: Int) -> NSColor? {
        text.string.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    /// The first paragraph's layout fragment, laid out by TextKit 2 as an answer's text view lays it out.
    private func layOut(_ text: NSAttributedString, width: CGFloat = 320) -> NSTextLayoutFragment? {
        let content = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        layout.delegate = InlineCodeLayout.shared
        content.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: width, height: 0))
        container.lineFragmentPadding = 0
        layout.textContainer = container
        content.textStorage?.setAttributedString(text)
        var first: NSTextLayoutFragment?
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            first = fragment
            return false
        }
        return first
    }

    private func paragraph(_ text: RichText, line: Int) -> NSParagraphStyle? {
        let lines = text.string.string.components(separatedBy: "\n")
        let offset = lines.prefix(line).reduce(0) { $0 + ($1 as NSString).length + 1 }
        return text.string.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
    }
}
