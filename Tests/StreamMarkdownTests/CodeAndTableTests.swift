import AppKit
import Markdown
@testable import StreamMarkdown
import Testing

@MainActor
struct CodeAndTableTests {
    let style = ResolvedStyle(RenderEnvironment())

    // MARK: Code blocks

    @Test func aClosedCodeBlockIsHighlightedAndCopiesItsCode() throws {
        let code = try code(compile("```python\ndef f(x):\n\treturn x  # id\n```").last)
        #expect(code.language == "python")
        #expect(code.code == "def f(x):\n\treturn x  # id")
        #expect(code.isHighlighted)
        let text = code.text.string
        #expect(text.string == code.code)
        #expect(color(text, at: 0) == style.codeColor(.keyword))
        #expect(font(text, at: 0)?.fontDescriptor.symbolicTraits.contains(.bold) == true, "keywords are semibold")
        #expect(color(text, at: 4) == style.codeColor(.function))
        #expect(color(text, at: 6) == style.text)
        #expect(font(text, at: 6)?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        let paragraph = try #require(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let space = NSAttributedString(string: " ", attributes: [.font: try #require(font(text, at: 6))]).size().width
        #expect(abs(paragraph.defaultTabInterval - 4 * space) < 0.01)
    }

    @Test func anUnknownLanguageOrNoneStaysPlain() throws {
        for markdown in ["```\nplain words\n```", "```text\nplain words\n```"] {
            let code = try code(compile(markdown).last)
            #expect(!code.isHighlighted)
            #expect(color(code.text.string, at: 0) == style.text)
        }
        #expect(try code(compile("```\nx\n```").last).language == nil)
    }

    @Test func codeIsPlainWhileItsFenceIsOpenAndHighlightedOnceItCloses() throws {
        let open = compile("Intro\n\n```swift\nlet x = 1", streaming: true)
        #expect(try !code(open.last).isHighlighted)
        let closed = compile("Intro\n\n```swift\nlet x = 1\n```", streaming: true)
        #expect(try code(closed.last).isHighlighted)
        #expect(open.last?.key != closed.last?.key, "the closing fence alone must redraw the block")
        #expect(open.first?.key == closed.first?.key)
    }

    @Test func aFenceThatNeverClosesIsHighlightedWhenTheAnswerEnds() throws {
        let text = "```swift\nlet x = 1"
        #expect(try !code(compile(text, streaming: true).last).isHighlighted)
        #expect(try code(compile(text, streaming: false).last).isHighlighted)
        #expect(try !code(compile("```swift\nlet x = 1\n``", streaming: true).last).isHighlighted, "two backticks do not close a fence")
        #expect(try !code(compile("````swift\nlet x = 1\n```", streaming: true).last).isHighlighted, "a shorter fence does not close a longer one")
    }

    @Test func codeTheHighlighterCannotColourIsNotRedrawnWhenItCloses() {
        for text in ["Intro\n\n    let x = 1", "Intro\n\n```text\nwords"] {
            #expect(compile(text, streaming: true).last?.key == compile(text, streaming: false).last?.key, "\(text)")
        }
        #expect(compile("```swift\nlet x", streaming: true).last?.key != compile("```swift\nlet x", streaming: false).last?.key)
    }

    @Test func deferredHighlightingDrawsPlainUntilTheParseOffMain() throws {
        let deferred = compile("```swift\nlet x = 1\n```", defers: true)
        #expect(try !code(deferred.last).isHighlighted)
        #expect(deferred.last?.key != compile("```swift\nlet x = 1\n```").last?.key)
    }

    @Test func theStreamHighlightsWhenTheAnswerStopsStreaming() async throws {
        let stream = MarkdownStream()
        stream.start(text: "```swift\nlet x = 1", environment: RenderEnvironment(), isStreaming: true)
        await stream.settled()
        #expect(try !code(stream.blocks.last).isHighlighted)
        stream.update(isStreaming: false)
        await stream.settled()
        #expect(try code(stream.blocks.last).isHighlighted)
    }

    @Test func aFinishedAnswerHighlightsOffTheMainThread() async throws {
        let stream = MarkdownStream()
        stream.start(text: "```swift\nlet x = 1\n```", environment: RenderEnvironment(), isStreaming: false)
        #expect(try !code(stream.blocks.last).isHighlighted, "the parse on the main thread leaves code plain")
        await stream.settled()
        #expect(try code(stream.blocks.last).isHighlighted)
    }

    // MARK: Code and tables inside lists

    @Test func codeInsideAListItemCutsTheListAtTheItemsIndent() throws {
        let content = BlockRenderer.render(try markup("1. Install:\n\n   ```bash\n   pip install peft\n   ```\n2. Train"), kind: .orderedList, source: nil, style: style)
        guard case .stack(let items) = content else { Issue.record("not a stack: \(content)"); return }
        #expect(items.map(\.id) == [0, 1, 2])
        guard case .text(let first) = items[0].content, case .code(let code) = items[1].content, case .text(let last) = items[2].content else {
            Issue.record("not text, code, text")
            return
        }
        #expect(first.string.string == "\t1.\tInstall:")
        #expect(code.code == "pip install peft")
        #expect(code.isHighlighted)
        #expect(last.string.string == "\t2.\tTrain")
        let item = try #require(first.string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(items[1].indent == item.headIndent, "the code sits at the item's text indent")
        #expect(items[0].gap == 0)
        #expect(items[1].gap == style.style.blockSpacing * style.em)
        #expect(items[2].gap == style.style.blockSpacing * style.em)
        #expect(items[2].indent == 0, "text keeps its indents in its paragraph styles")
    }

    @Test func codeInAnOpenListIsPlainOnlyWhileItIsTheListsLastBlock() throws {
        let open = compile("- step\n\n  ```bash\n  ls", streaming: true)
        let after = compile("- step\n\n  ```bash\n  ls\n  ```\n- next", streaming: true)
        guard case .stack(let openItems) = open.last?.content, case .stack(let afterItems) = after.last?.content,
              case .code(let openCode) = openItems.last?.content, case .code(let afterCode) = afterItems[1].content else {
            Issue.record("no stacks")
            return
        }
        #expect(!openCode.isHighlighted)
        #expect(afterCode.isHighlighted)
    }

    @Test func aTableInsideAListItemIsATable() throws {
        let content = BlockRenderer.render(try markup("- Results:\n\n  | a | b |\n  |---|---|\n  | 1 | 2 |"), kind: .unorderedList, source: nil, style: style)
        guard case .stack(let items) = content, case .table(let table) = items.last?.content else { Issue.record("no table: \(content)"); return }
        #expect(table.rows.map { $0.map(\.text.string.string) } == [["a", "b"], ["1", "2"]])
    }

    @Test func aQuoteDrawsItsCodeAsACodeBlock() throws {
        let content = BlockRenderer.render(try markup("> ```js\n> let x\n> ```"), kind: .blockQuote, source: nil, style: style)
        guard case .quote(let blocks) = content, case .code(let code) = blocks.first?.content else { Issue.record("no code: \(content)"); return }
        #expect(code.code == "let x")
    }

    // MARK: Tables

    @Test func tableCellsGoThroughTheProseBuilderInTheirColumnsAlignment() throws {
        let table = try table(compile("""
        | Method | Params | Score | Note |
        |:--|--:|:-:|---|
        | **LoRA** | 4.7M | `91.7` | [paper](https://arxiv.org/abs/2106.09685) |
        """).last)
        #expect(table.columns == 4)
        #expect(table.rows.map { $0.map(\.text.string.string) } == [["Method", "Params", "Score", "Note"], ["LoRA", "4.7M", "91.7", "paper"]])
        let header = table.rows[0], body = table.rows[1]
        #expect(header.map { alignment($0.text) } == [.left, .right, .center, .natural])
        #expect(body.map { alignment($0.text) } == [.left, .right, .center, .natural])
        let headerFont = try #require(font(header[0].text.string, at: 0))
        #expect(headerFont.pointSize == style.tableHeader.size)
        #expect(headerFont.fontName.contains("NewYork"), "cells are in the serif body face")
        #expect(headerFont.fontDescriptor.symbolicTraits.contains(.bold))
        let plain = try #require(font(body[1].text.string, at: 0))
        #expect(!plain.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(plain.pointSize == style.table.size)
        #expect(try #require(font(body[0].text.string, at: 0)).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(try #require(font(body[2].text.string, at: 0)).fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(body[3].text.string.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://arxiv.org/abs/2106.09685"))
    }

    @Test func aShortRowGetsEmptyCells() throws {
        let table = try table(compile("| a | b | c |\n|---|---|---|\n| 1 |").last)
        #expect(table.rows.map { $0.map(\.text.string.string) } == [["a", "b", "c"], ["1", "", ""]])
    }

    @Test func aLateDefinitionUsedInACellRedrawsTheTable() async throws {
        let stream = MarkdownStream()
        let table = "| Paper |\n|---|\n| [LoRA][lora] |"
        stream.update(text: table)
        await stream.settled()
        let before = try #require(stream.blocks.first)
        stream.update(text: table + "\n\n[lora]: https://arxiv.org/abs/2106.09685")
        await stream.settled()
        let after = try #require(stream.blocks.first)
        #expect(after.revision != before.revision)
        let cell = try self.table(after).rows[1][0].text.string
        #expect(cell.string == "LoRA")
        #expect(cell.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://arxiv.org/abs/2106.09685"))
    }

    @Test func aStreamingTableKeepsTheTextOfItsUnchangedCells() async throws {
        let stream = MarkdownStream()
        stream.update(text: "| a | b |\n|---|---|\n| 1 | 2 |\n| 3")
        await stream.settled()
        let before = try table(stream.blocks.first)
        stream.update(text: "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |")
        await stream.settled()
        let after = try table(stream.blocks.first)
        #expect(after.rows[0][0].text === before.rows[0][0].text)
        #expect(after.rows[1][1].text === before.rows[1][1].text)
        #expect(after.rows[2][0].text === before.rows[2][0].text)
        #expect(after.rows[2][1].text !== before.rows[2][1].text)
        #expect(after.rows[2][1].text.string.string == "4")
    }

    /// Streamed in these steps, an answer renders exactly as the last step does parsed fresh.
    @Test(arguments: [
        ["```py\nx = 1", "```py\nx = 1\n```", "```py\nx = 1\n```\n\nText"],
        ["| a | b |\n|---|---|\n| 1", "| a | b |\n|---|---|\n| 1 | 2 |", "| a | b |\n|---|---|\n| 1 | 2 |\n\n[r]: https://x.org"],
        ["- a\n\n  ```sh\n  ls", "- a\n\n  ```sh\n  ls\n  ```\n- b"],
    ])
    func chunksRenderAsTheWholeTextDoes(_ steps: [String]) async {
        let stream = MarkdownStream()
        for step in steps {
            stream.update(text: step)
            await stream.settled()
        }
        let fresh = MarkdownStream()
        fresh.update(text: steps.last!)
        await fresh.settled()
        #expect(stream.blocks.map(\.kind) == fresh.blocks.map(\.kind))
        for (streamed, whole) in zip(stream.blocks, fresh.blocks) {
            #expect(Rendered(streamed.content) == Rendered(whole.content), "block \(streamed.id) after \(steps)")
        }
    }

    // MARK: Helpers

    private func compile(_ text: String, streaming: Bool = false, defers: Bool = false) -> [MarkdownBlock] {
        MarkdownCompiler.compile(text, style: style, previous: [], nextRevision: 1, options: CompileOptions(isStreaming: streaming, defersHighlighting: defers)).blocks
    }

    private func markup(_ markdown: String) throws -> Markup {
        try #require(Document(parsing: markdown).child(at: 0))
    }

    private func code(_ block: MarkdownBlock?) throws -> CodeContent {
        guard case .code(let code) = block?.content else { throw Failure.wrongContent }
        return code
    }

    private func table(_ block: MarkdownBlock?) throws -> TableContent {
        guard case .table(let table) = block?.content else { throw Failure.wrongContent }
        return table
    }

    private enum Failure: Error { case wrongContent }

    private func font(_ text: NSAttributedString, at index: Int) -> NSFont? {
        text.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func color(_ text: NSAttributedString, at index: Int) -> NSColor? {
        text.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    private func alignment(_ text: RichText) -> NSTextAlignment? {
        guard text.string.length > 0 else { return nil }
        return (text.string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment
    }
}
