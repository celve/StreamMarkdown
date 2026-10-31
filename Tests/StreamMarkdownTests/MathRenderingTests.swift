import AppKit
import Markdown
@testable import StreamMarkdown
import Testing

struct MathRenderingTests {
    let style = ResolvedStyle(RenderEnvironment())

    @Test func inlineMathIsATemplateImageOnTheBaselineLabelledWithItsTeX() throws {
        let text = build("Rank $r \\ll d$ here.")
        #expect(text.string == "Rank \u{FFFC} here.")
        let attachment = try #require(text.attribute(.attachment, at: 5, effectiveRange: nil) as? MathAttachment)
        #expect(attachment.tex == "r \\ll d")
        #expect(attachment.bounds.minY < 0, "the formula's descent hangs below the baseline")
        #expect(attachment.bounds.maxY > 0)
        #expect(attachment.image?.isTemplate == true, "drawn in the text's colour, so it follows dark mode")
        #expect(text.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor == style.text)
    }

    @Test func inlineMathTakesTheSizeOfTheTextAroundIt() throws {
        let body = try #require(build("$x^2$").attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        let heading = try #require(build("## $x^2$").attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        #expect(heading.bounds.height > body.bounds.height)
    }

    @Test func linkedAndQuotedMathTakesItsRunsColour() throws {
        let linked = build("[$x$](https://example.com)")
        #expect(linked.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == style.link)
        #expect(linked.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
    }

    @Test func aFormulaSwiftMathCannotReadShowsItsSourceAsCode() throws {
        let text = build("See $\\unknowncommand{x}$ here.")
        #expect(text.string == "See $\\unknowncommand{x}$ here.")
        let font = try #require(text.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(text.attribute(.backgroundColor, at: 4, effectiveRange: nil) as? NSColor == style.inlineCodeBackground)
    }

    @Test(arguments: [
        #"\dfrac{a}{b}"#, #"\tfrac{1}{2}"#, #"\operatorname{softmax}(x)"#, #"\operatorname*{arg\,max}_x f(x)"#,
        #"\boldsymbol{\theta}"#, #"\lVert x \rVert"#, #"\begin{align} x &= 1 \\ y &= 2 \end{align}"#, #"\begin{align*} x &= 1 \end{align*}"#,
        #"\begin{equation} x = 1 \end{equation}"#, #"x = 1 \tag{1}"#, #"x \label{eq:1}"#, #"\big( x \big)"#, #"\Bigl[ x \Bigr]"#,
        #"a \dots b"#, #"\intercal"#, #"a \implies b"#, #"\mathds{1}"#, #"\varnothing"#, #"\coloneqq"#, #"\not\in"#,
        #"\overrightarrow{AB}"#, #"\underbrace{a+b}_{n}"#, #"\iint"#, #"a \middle| b"#,
    ])
    func commandsSwiftMathLacksAreRewrittenToOnesItHas(_ tex: String) {
        #expect(MathRenderer.render(tex, fontSize: 17, display: true) != nil, "\(tex) → \(MathRenderer.rewritten(tex) ?? "unchanged")")
    }

    @Test func rewritesLeaveSupportedTeXAlone() {
        #expect(MathRenderer.rewritten(#"\frac{a}{b} + \mathbf{x} \cdot \ldots"#) == nil)
        #expect(MathRenderer.rewritten(#"\dfrac{a}{b}"#) == #"\frac{a}{b}"#)
        #expect(MathRenderer.rewritten(#"\operatorname{Var}(X)"#) == #"\mathrm{Var}(X)"#)
    }

    @Test func eachFormulaIsTypesetOncePerSizeAndStyle() throws {
        let tex = #"\sum_{i=1}^{n} \cache_{probe}"#.replacingOccurrences(of: #"\cache_{probe}"#, with: "x_\(UInt32.random(in: 0...UInt32.max))")
        let first = try #require(MathRenderer.render(tex, fontSize: 17, display: false))
        #expect(MathRenderer.render(tex, fontSize: 17, display: false) === first)
        #expect(MathRenderer.render(tex, fontSize: 17, display: true) !== first)
        #expect(MathRenderer.render(tex, fontSize: 20, display: false) !== first)
    }

    @Test func displayMathInAListTakesALineOfItsOwn() throws {
        #expect(build("- item\n\n  $$\n  x^2\n  $$\n- next").string == "\t\u{2022}\titem\n\u{FFFC}\n\t\u{2022}\tnext")
        #expect(build("- see\n  $$x$$\n  after").string == "\t\u{2022}\tsee \u{2028}\u{FFFC}\u{2028}after")
        #expect(build("1. $$x$$ then").string == "\t1.\t\u{FFFC}\u{2028}then", "a formula that opens the item stays beside its marker")
        let text = build("- $$\\frac{a}{b}$$")
        let attachment = try #require(text.attribute(.attachment, at: 3, effectiveRange: nil) as? MathAttachment)
        let inline = try #require(MathRenderer.render(#"\frac{a}{b}"#, fontSize: style.body.size * style.style.mathScale, display: false))
        #expect(attachment.bounds.height > inline.size.height, "display style, larger than the same fraction inline")
    }

    @Test func aRootDisplayFormulaIsAMathBlock() throws {
        let block = try #require(BlockParser.parse("$$\n\\int_0^1 x\\,dx\n$$").first)
        #expect(block.kind == .displayMath)
        let content = BlockRenderer.render(block.markup, kind: block.kind, source: block.source, style: style, math: block.math)
        guard case .math(let formulas) = content else { Issue.record("not math: \(content)"); return }
        #expect(formulas.map(\.tex) == ["\\int_0^1 x\\,dx"])
        #expect(formulas[0].rendered != nil)
        #expect(formulas[0].color == style.text)
        #expect(formulas[0].fallback.string.string == "$$\n\\int_0^1 x\\,dx\n$$")
    }

    @Test func aDisplayFormulaSwiftMathCannotReadFallsBackToItsSource() throws {
        let block = try #require(BlockParser.parse("\\[\\unknowncommand\\]").first)
        guard case .math(let formulas) = BlockRenderer.render(block.markup, kind: block.kind, source: block.source, style: style, math: block.math) else {
            Issue.record("not math")
            return
        }
        #expect(formulas[0].rendered == nil)
        #expect(formulas[0].fallback.string.string == "\\[\\unknowncommand\\]")
    }

    @Test func aQuotedDisplayFormulaIsAMathBlockInTheQuoteColour() throws {
        let block = try #require(BlockParser.parse("> Where\n>\n> $$\n> x\n> $$").first)
        guard case .quote(let children) = BlockRenderer.render(block.markup, kind: block.kind, source: block.source, style: style, math: block.math),
              case .math(let formulas) = children.last?.content else {
            Issue.record("not a quote ending in math")
            return
        }
        #expect(children.map(\.kind) == [.paragraph, .displayMath])
        #expect(formulas.map(\.tex) == ["x"])
        #expect(formulas[0].color == style.quoteText)
    }

    @Test func sourceDrawnBlocksShowFormulasAsWritten() throws {
        let list = build("- item\n\n  | $a$ | b |\n  |---|---|\n  | 1 | 2 |")
        #expect(list.string.contains("$a$"))
        let quoted = try #require(BlockParser.parse("> <div>$x$</div>\n>\n> | $a$ |\n> |---|").first)
        guard case .quote(let children) = BlockRenderer.render(quoted.markup, kind: quoted.kind, source: quoted.source, style: style, math: quoted.math) else {
            Issue.record("not a quote")
            return
        }
        let texts = children.compactMap { child -> String? in if case .source(let text) = child.content { text.string.string } else { nil } }
        #expect(texts.contains { $0.contains("$a$") && $0.contains("|") }, "\(texts)")
    }

    private func build(_ markdown: String) -> NSAttributedString {
        let block = BlockParser.parse(markdown)[0]
        return ProseBuilder.build(block.markup, style: style, math: block.math).string
    }
}
