@testable import StreamMarkdown
import Testing

struct BlockParserTests {
    @Test func rootBlocksCarryKindsAndTheirExactSource() {
        let text = """
        # Title

        A paragraph
        over two lines.

        - one
        - two

        > quoted

        ```swift
        let x = 1
        ```

        | a | b |
        |---|---|
        | 1 | 2 |

        ---

        <div>html</div>
        """
        let blocks = BlockParser.parse(text)
        #expect(blocks.map(\.kind) == [.heading(level: 1), .paragraph, .unorderedList, .blockQuote, .codeBlock(language: "swift"), .table, .thematicBreak, .html])
        #expect(blocks.map(\.source) == ["# Title", "A paragraph\nover two lines.", "- one\n- two", "> quoted", "```swift\nlet x = 1\n```", "| a | b |\n|---|---|\n| 1 | 2 |", "---", "<div>html</div>"])
        #expect(blocks.map(\.index) == Array(0..<8))
        for block in blocks { #expect(substring(text, block.range) == block.source) }
    }

    @Test func rangesAreUTF8OffsetsPastMultibyteText() {
        let text = "## 结果 🎉\n\nCafé — naïve **bold**\n\n1. 第一\n2. second"
        let blocks = BlockParser.parse(text)
        #expect(blocks.map(\.source) == ["## 结果 🎉", "Café — naïve **bold**", "1. 第一\n2. second"])
        for block in blocks { #expect(substring(text, block.range) == block.source) }
    }

    @Test func carriageReturnLineEndingsKeepRanges() {
        let text = "First\r\n\r\nSecond line\r\nwraps\r\n\r\n- item"
        let blocks = BlockParser.parse(text)
        #expect(blocks.map(\.kind) == [.paragraph, .paragraph, .unorderedList])
        #expect(blocks[1].source == "Second line\r\nwraps")
        #expect(blocks[2].source == "- item")
    }

    @Test func indentedBlocksStartAtTheirLine() {
        let blocks = BlockParser.parse("Intro\n\n   > indented quote\n\n  - indented item")
        #expect(blocks.map(\.source) == ["Intro", "   > indented quote", "  - indented item"])
    }

    /// Cut at a blank line, a growing answer parses its earlier blocks exactly as the whole answer does.
    @Test func earlierBlocksKeepTheirIndexAndSourceAsTheAnswerGrows() {
        let whole = BlockParser.parse(Samples.answer)
        var cut = Samples.answer.startIndex
        while let blank = Samples.answer[cut...].range(of: "\n\n") {
            let prefix = String(Samples.answer[..<blank.lowerBound])
            let blocks = BlockParser.parse(prefix)
            #expect(blocks.map(\.source) == whole.prefix(blocks.count).map(\.source), "cut at \(prefix.utf8.count)")
            #expect(blocks.map(\.kind) == whole.prefix(blocks.count).map(\.kind))
            cut = blank.upperBound
        }
    }

    @Test func aReferenceDefinitionIsContextForTheBlockThatUsesIt() {
        let use = "See [the paper][lora] and [this](https://example.com)."
        let unresolved = BlockParser.parse(use + "\n\nMore.")
        #expect(unresolved[0].references == "")

        let resolved = BlockParser.parse(use + "\n\nMore.\n\n[lora]: https://arxiv.org/abs/2106.09685 \"LoRA\"")
        #expect(resolved.count == 2, "a definition draws nothing")
        #expect(resolved[0].references.contains("https://arxiv.org/abs/2106.09685"))
        #expect(resolved[0].references.contains("LoRA"))
        #expect(resolved[0].key != unresolved[0].key)
        #expect(resolved[1].key == unresolved[1].key)
    }

    @Test func aDefinitionBeforeItsUseResolvesToo() {
        let blocks = BlockParser.parse("[d]: https://duoxiv.app\n\nRead [Duoxiv][d].")
        #expect(blocks.count == 1)
        #expect(blocks[0].references.contains("https://duoxiv.app"))
    }

    @Test func emptyTextHasNoBlocks() {
        #expect(BlockParser.parse("").isEmpty)
        #expect(BlockParser.parse("\n\n  \n").isEmpty)
    }

    private func substring(_ text: String, _ range: Range<Int>) -> String {
        String(decoding: Array(text.utf8)[range], as: UTF8.self)
    }
}
