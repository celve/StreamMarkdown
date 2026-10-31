import Markdown
@testable import StreamMarkdown
import Testing

struct MathExtractorTests {
    @Test func findsAllFourDelimiters() {
        let spans = MathExtractor.extract("Inline $a$, \\(b\\), and\n\n$$\nc\n$$\n\n\\[\nd\n\\]").math.spans
        #expect(spans.map(\.source) == ["$a$", "\\(b\\)", "$$\nc\n$$", "\\[\nd\n\\]"])
        #expect(spans.map(\.tex) == ["a", "b", "\nc\n", "\nd\n"])
        #expect(spans.map(\.isDisplay) == [false, false, true, true])
    }

    @Test func skipsCodeSpansFencesAndIndentedCode() {
        #expect(formulas("Use `$x$` and\n\n```\n$y$\n```\n\n    $z$ indented\n\nbut $w$.") == ["$w$"])
        #expect(formulas("~~~\n$$\nx\n$$\n~~~") == [])
        #expect(formulas("- item\n\n  ```\n  $a$\n  ```") == [])
    }

    @Test func honoursEscapes() {
        #expect(formulas(#"\$5 and \$x$ here"#) == [])
        #expect(formulas(#"\\(not math\\)"#) == [])
        #expect(formulas(#"Price $\$5$ inside"#) == [#"$\$5$"#])
        #expect(formulas(#"$$a \\ b$$"#) == [#"$$a \\ b$$"#], "a TeX line break does not escape the closing delimiter")
        #expect(formulas(#"\(a \) b\)"#) == [#"\(a \)"#])
    }

    @Test(arguments: [
        "It costs $5 and $10.",
        "Between $5-$10 a month.",
        "Pay $1,$2 or $3.",
        "Price: $5 and $6.",
        "US$5 and US$10.",
        "From $20,000 to $30,000.",
        "Costs $5\nand $6 later.",
        "A lone $ sign.",
        "$$ $$",
    ])
    func leavesCurrencyAndStrayDollarsAlone(_ text: String) {
        #expect(formulas(text) == [])
    }

    @Test func keepsMathThatLooksLikeCurrencyBeside() {
        #expect(formulas("The $x$-axis and the $i$th row cost $5.") == ["$x$", "$i$"])
        #expect(formulas("Solve $2x + 1 = 5$.") == ["$2x + 1 = 5$"])
    }

    @Test func inlineMathKeepsToItsLineOrParagraph() {
        #expect(formulas("$a\nb$") == [])
        #expect(formulas("\\(a\n\nb\\)") == [])
        #expect(formulas("\\(a\nb\\)") == ["\\(a\nb\\)"])
        #expect(formulas("$$\nx\n\ny\n$$") == ["$$\nx\n\ny\n$$"], "display math may hold blank lines")
    }

    @Test func bracketsAreDisplayMathOnlyAtTheStartOfALine() {
        #expect(formulas("See \\[1\\] here.") == [])
        #expect(formulas("\\[x\\]") == ["\\[x\\]"])
        #expect(formulas("> \\[x\\]") == ["\\[x\\]"])
        #expect(formulas("- \\[x\\]") == ["\\[x\\]"])
        #expect(formulas("12. \\[x\\]") == ["\\[x\\]"])
        #expect(formulas("  \\[\n  x\n  \\]") == ["\\[\n  x\n  \\]"])
    }

    @Test func skipsLinkDestinationsHTMLImagesAndDefinitions() {
        #expect(formulas(#"[$a$](https://x.com/$b$ "$c$") and <https://x.com/$d$>"#) == ["$a$"])
        #expect(formulas(#"<span title="$a$">$b$</span>"#) == ["$b$"])
        #expect(formulas("<div>\n$a$\n</div>") == [])
        #expect(formulas("![$a$](x.png)") == [])
        #expect(formulas("[r]: https://x.com/$a$\n\nText $b$.") == ["$b$"])
    }

    @Test func formulasInQuotesLoseTheirLineMarkers() {
        let spans = MathExtractor.extract("> $$\n> a\n>b\n> $$").math.spans
        #expect(spans.map(\.tex) == ["\na\nb\n"])
        #expect(MathExtractor.extract("> > Then $$x\n> > y$$").math.spans.map(\.tex) == ["x\ny"])
    }

    @Test func markdownInsideFormulasIsNotParsed() throws {
        let blocks = BlockParser.parse("Take $a*b*c$ and $x_1 + y_1$ here.")
        #expect(blocks.map(\.kind) == [.paragraph])
        let paragraph = try #require(blocks.first?.markup)
        #expect(paragraph.children.allSatisfy { $0 is Text }, "no emphasis from the asterisks or underscores in TeX")
    }

    // MARK: Blocks

    @Test func displayMathInARootParagraphBecomesItsOwnBlock() {
        let text = "Compute\n$$\nx\n$$\nthen more,  $$y$$   and the rest."
        let blocks = BlockParser.parse(text)
        #expect(blocks.map(\.kind) == [.paragraph, .displayMath, .paragraph, .displayMath, .paragraph])
        #expect(blocks.map(\.source) == ["Compute", "$$\nx\n$$", "then more,", "$$y$$", "and the rest."])
        expectRangesMatch(text, blocks)
    }

    @Test func displayMathInsideAListStaysInTheList() {
        let blocks = BlockParser.parse("- item\n\n  $$\n  x\n  $$\n- next")
        #expect(blocks.map(\.kind) == [.unorderedList])
        #expect(blocks[0].math.spans.map(\.source) == ["$$\n  x\n  $$"])
    }

    @Test func adjacentDisplayFormulasAreBlocksEach() {
        let text = "$$a$$ $$b$$\n\n\\[c\\]"
        let blocks = BlockParser.parse(text)
        #expect(blocks.map(\.kind) == [.displayMath, .displayMath, .displayMath])
        #expect(blocks.map(\.source) == ["$$a$$", "$$b$$", "\\[c\\]"])
        expectRangesMatch(text, blocks)
    }

    @Test func rangesStayTheAnswersPastMultibyteText() {
        let text = "## 结果 $x$ 🎉\n\nCafé $$\\alpha$$ naïve\n\n- $y$ 第一\n- two"
        let blocks = BlockParser.parse(text)
        #expect(blocks.map(\.kind) == [.heading(level: 2), .paragraph, .displayMath, .paragraph, .unorderedList])
        #expect(blocks.map(\.source) == ["## 结果 $x$ 🎉", "Café", "$$\\alpha$$", "naïve", "- $y$ 第一\n- two"])
        expectRangesMatch(text, blocks)
    }

    @Test func keysNameFormulasByContentNotPosition() {
        let early = BlockParser.parse("$a$ first\n\nThen $b$.")
        let late = BlockParser.parse("No math first\n\nThen $b$.")
        #expect(early[1].key == late[1].key)
        #expect(BlockParser.parse("Then $c$.")[0].key != late[1].key)
        #expect(BlockParser.parse("Then \\(b\\).")[0].key != late[1].key, "the source decides a failed formula's fallback")
    }

    @Test func answersWithoutMathParseAsBefore() {
        for answer in Self.lin2404Answers where !answer.contains("$") && !answer.contains("\\[") && !answer.contains("\\(") {
            let blocks = BlockParser.parse(answer)
            #expect(blocks.map { $0.markup.format() } == Document(parsing: answer, options: [.disableSmartOpts]).children.map { $0.format() })
            #expect(blocks.allSatisfy { $0.math.spans.isEmpty })
        }
    }

    // MARK: LIN-2404's regression cases (folio AskTests.answers and docs/ask-stub/math.md)

    /// The answers Ask's block cut was tested on, in folio's `AskTests.answers`.
    static let lin2404Answers = [
        "1. First\n\n1. Second\n\n1. Third",
        "Read [the paper][p].\n\nMore text.\n\n[p]: https://arxiv.org/abs/2106.09685",
        "[p]: https://arxiv.org/abs/2106.09685\n\nRead [the paper][p].",
        "Code:\n\n    x = 1\n\n    y = 2\n\nAfter.",
        "````markdown\n```\n\n## still code\n````\n\nAfter.",
        "## Results\n\nLoRA freezes $W_0$.\n\n$$\nh = W_0 x\n\n+ BAx\n$$\n\n1. First\n   - nested\n\n   continued\n2. Second",
        "| A | B |\n|---|---|\n| 1 | 2 |\n> quote\n>\n> more\n\n~~~\nx\n\ny\n~~~\nDone.",
        "```python\nx = 1\n```\n\n[p]: https://arxiv.org/abs/2106.09685\n\nRead [the paper][p].",
        "    x = 1\n\n[p]: https://arxiv.org/abs/2106.09685\n\nRead [the paper][p].",
        "Read [the paper][p].\n\nOther text.\n\n[p]:\n  https://arxiv.org/abs/2106.09685",
        "Read [paper][p].\n\n- Example:\n\n  ```text\n  [p]: https://example.org/fake\n  ```",
        "Use `$$` for display math:\n\n$$\n- x^2\n$$",
        "\\[\n- x^2\n\\]",
        "Inline \\(a\\) and $b$.\n\n$$\n\\begin{aligned}\nx &= 1\n\n\\\\ y &= 2\n\\end{aligned}\n$$\n\nPrice: $5 and $6.",
    ]

    @Test func aDollarPairInInlineCodeDoesNotSwallowTheEquationAfterIt() {
        let text = "Use `$$` for display math:\n\n$$\n- x^2\n$$"
        let blocks = BlockParser.parse(text)
        #expect(blocks.map(\.kind) == [.paragraph, .displayMath])
        #expect(blocks.map(\.source) == ["Use `$$` for display math:", "$$\n- x^2\n$$"])
        #expect(blocks[1].math.spans.map(\.tex) == ["\n- x^2\n"])
    }

    @Test func aBracketEquationIsNotReadAsAList() {
        let blocks = BlockParser.parse("\\[\n- x^2\n\\]")
        #expect(blocks.map(\.kind) == [.displayMath])
        #expect(blocks[0].source == "\\[\n- x^2\n\\]")
    }

    @Test func aDisplayEquationKeepsItsBlankLinesInOneBlock() {
        let text = "A\n\n$$\nx\n\ny\n$$\n\nB"
        let blocks = BlockParser.parse(text)
        #expect(blocks.map(\.source) == ["A", "$$\nx\n\ny\n$$", "B"])
        #expect(blocks.map(\.kind) == [.paragraph, .displayMath, .paragraph])
        let results = BlockParser.parse(Self.lin2404Answers[5])
        #expect(results.map(\.kind) == [.heading(level: 2), .paragraph, .displayMath, .orderedList])
        #expect(results[2].source == "$$\nh = W_0 x\n\n+ BAx\n$$")
    }

    @Test func mixedInlineBracketAlignedMathAndCurrency() {
        let text = Self.lin2404Answers[13]
        let spans = MathExtractor.extract(text).math.spans
        #expect(spans.filter { !$0.isDisplay }.map(\.source) == ["\\(a\\)", "$b$"])
        #expect(spans.filter(\.isDisplay).map(\.tex) == ["\n\\begin{aligned}\nx &= 1\n\n\\\\ y &= 2\n\\end{aligned}\n"])
        let blocks = BlockParser.parse(text)
        #expect(blocks.map(\.kind) == [.paragraph, .displayMath, .paragraph])
        #expect(blocks[2].source == "Price: $5 and $6.")
    }

    @Test func theStubsMathAnswerCutsAsWritten() {
        let text = """
        ## Display math after inline code

        Use `$$` for display math:

        $$
        - x^2
        $$

        ## Bracket display math

        \\[
        - x^2
        \\]
        """
        let blocks = BlockParser.parse(text)
        #expect(blocks.map(\.kind) == [.heading(level: 2), .paragraph, .displayMath, .heading(level: 2), .displayMath])
        expectRangesMatch(text, blocks)
    }

    @Test func theLoRAStressAnswerFindsEveryFormula() {
        let spans = MathExtractor.extract(Self.lora).math.spans
        #expect(spans.filter { !$0.isDisplay }.map(\.tex) == [
            #"W_0 \in \mathbb{R}^{d \times k}"#, #"B \in \mathbb{R}^{d \times r}"#, #"A \in \mathbb{R}^{r \times k}"#,
            #"r \ll \min(d, k)"#, "BA", "W_0", "r",
        ])
        #expect(spans.filter(\.isDisplay).map(\.tex) == ["\nh = W_0 x + \\Delta W x = W_0 x + B A x\n"])
        let blocks = BlockParser.parse(Self.lora)
        #expect(blocks.count > 5)
        #expect(blocks.filter { $0.kind == .displayMath }.count == 1)
        expectRangesMatch(Self.lora, blocks)
    }

    // MARK: Unfinished math, for the streaming tail

    @Test func reportsTheOpenerOfATailStillInsideAFormula() {
        #expect(MathExtractor.unfinishedMath(in: "Text $$\nx = 1") == .init(delimiter: .doubleDollar, start: 5))
        #expect(MathExtractor.unfinishedMath(in: "\\[\nx") == .init(delimiter: .bracket, start: 0))
        #expect(MathExtractor.unfinishedMath(in: "where \\(a +") == .init(delimiter: .parenthesis, start: 6))
        #expect(MathExtractor.unfinishedMath(in: "where $W_0 \\in") == .init(delimiter: .dollar, start: 6))
        #expect(MathExtractor.unfinishedMath(in: "costs $5") == .init(delimiter: .dollar, start: 6), "currency is not known until it ends")
        #expect(MathExtractor.unfinishedMath(in: "$a$ and $$\nb\n\nc") == .init(delimiter: .doubleDollar, start: 8))
    }

    @Test func aTailEndingInLineBreaksIsStillInsideItsFormula() {
        #expect(MathExtractor.unfinishedMath(in: "$$\n") == .init(delimiter: .doubleDollar, start: 0))
        #expect(MathExtractor.unfinishedMath(in: "$$\nx\n") == .init(delimiter: .doubleDollar, start: 0))
        #expect(MathExtractor.unfinishedMath(in: "$$\nx\n\n") == .init(delimiter: .doubleDollar, start: 0))
        #expect(MathExtractor.unfinishedMath(in: "\\[\n") == .init(delimiter: .bracket, start: 0))
        #expect(MathExtractor.unfinishedMath(in: "\\[\nx\n") == .init(delimiter: .bracket, start: 0))
        #expect(MathExtractor.unfinishedMath(in: "\\(x\n") == .init(delimiter: .parenthesis, start: 0))
        #expect(MathExtractor.unfinishedMath(in: "> $$\n> x\n") == .init(delimiter: .doubleDollar, start: 2))
        #expect(MathExtractor.unfinishedMath(in: "- $$\n  x\n") == .init(delimiter: .doubleDollar, start: 2))
        #expect(MathExtractor.unfinishedMath(in: "Text\r\n$$\r\nx\r\n") == .init(delimiter: .doubleDollar, start: 6))
        #expect(MathExtractor.unfinishedMath(in: "\\(x\n\n") == nil, "an inline formula ends at a blank line")
        #expect(MathExtractor.unfinishedMath(in: "```\n$$\nx\n") == nil)
        #expect(MathExtractor.unfinishedMath(in: "$x\n") == nil)
    }

    @Test func reportsNothingWhenTheTailIsNotInAFormula() {
        for text in ["$a$ done", "```\n$$\nx", "$$\nx\n$$", "\\(a\n\nb", "$a\nb", "costs $ 5", "See \\[1", "Plain text"] {
            #expect(MathExtractor.unfinishedMath(in: text) == nil, "\(text)")
        }
    }

    // MARK: Helpers

    static let lora = """
    ## How LoRA works

    LoRA freezes the pretrained weights $W_0 \\in \\mathbb{R}^{d \\times k}$ and learns a **low-rank** update, so the adapted layer computes

    $$
    h = W_0 x + \\Delta W x = W_0 x + B A x
    $$

    where $B \\in \\mathbb{R}^{d \\times r}$, $A \\in \\mathbb{R}^{r \\times k}$ and $r \\ll \\min(d, k)$ (Section 4.1).

    ### Key results

    1. **Parameters**: 10,000× fewer trainable parameters than full fine-tuning on GPT-3 175B.
    2. *Memory*: GPU memory drops by about 3×.
       - No extra inference latency, since $BA$ merges into $W_0$.
       - Works on `W_q` and `W_v` alone.
    3. Quality matches or beats fine-tuning on RoBERTa, DeBERTa, GPT-2 and GPT-3.

    | Method | Trainable params | WikiSQL | MNLI-m |
    |:--|--:|--:|--:|
    | Fine-tune | 175B | 73.8 | 89.5 |
    | LoRA | 4.7M | **73.4** | **91.7** |

    ```python
    h = x @ W0.T + (x @ A.T) @ B.T * (alpha / r)
    ```

    > The rank $r$ can be as small as 1 or 2 (Section 7.2).

    See [the paper](https://arxiv.org/abs/2106.09685) or the follow-up [QLoRA](https://arxiv.org/abs/2305.14314).
    """

    private func formulas(_ text: String) -> [String] {
        MathExtractor.extract(text).math.spans.map(\.source)
    }

    private func expectRangesMatch(_ text: String, _ blocks: [ParsedBlock], sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        let utf8 = Array(text.utf8)
        for block in blocks {
            #expect(String(decoding: utf8[block.range], as: UTF8.self) == block.source, sourceLocation: sourceLocation)
        }
        #expect(zip(blocks, blocks.dropFirst()).allSatisfy { $0.range.upperBound <= $1.range.lowerBound }, sourceLocation: sourceLocation)
    }
}
