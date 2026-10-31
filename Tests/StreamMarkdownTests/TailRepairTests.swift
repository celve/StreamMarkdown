import Foundation
@testable import StreamMarkdown
import Testing

struct TailRepairTests {
    /// What a streaming answer ending here shows, and what it must not show while it is still being written.
    @Test(arguments: [
        // Emphasis closes early, so the words draw emphasised as they arrive.
        ("A **bol", "A bol"), ("A *ita", "A ita"), ("A ***both", "A both"), ("A __bol", "A bol"), ("A ~~gon", "A gon"),
        ("**bold *in", "bold in"), ("A **bold** and *it", "A bold and it"), ("A **bold ", "A bold"),
        // A marker with nothing after it waits.
        ("A **", "A"), ("A *", "A"), ("Done **bold**", "Done bold"), ("A `", "A"), ("A ``", "A"),
        // Inline code closes early; a backslash waits.
        ("Run `pip ins", "Run pip ins"), ("Use ``a`b", "Use a`b"), ("A \\", "A"),
        // Links and images wait until their destination closes; text before them shows.
        ("See [the pa", "See"), ("See [the paper]", "See"), ("See [the paper](https://arx", "See"),
        ("See [the paper](https://arxiv.org) now", "See the paper now"), ("A ![chart](ht", "A"), ("A [ref][lo", "A"),
        ("**See [the", "See"),
        // Lines that may still become something else wait.
        ("Para\n#", "Para"), ("Para\n\n-", "Para"), ("Para\n\n- ", "Para"), ("Para\n\n1", "Para"), ("Para\n\n12.", "Para"),
        ("Para\n\n>", "Para"), ("Title\n-", "Title"), ("Title\n==", "Title"), ("Para\n\n***", "Para"), ("Para\n\n- [", "Para"),
        ("Para\n\n- [x]", "Para"), ("Para\n\n[ref]: https://ex", "Para"),
        // Fences: an opening line waits for its break, a closing fence for its last backtick.
        ("Para\n\n```pyt", "Para"), ("```py\nx = 1\n``", "x = 1"), ("```py\nx = 1\n", "x = 1"), ("~~~~\na\n~~~", "a"),
        // Tables wait for their delimiter row, and each row for its line break.
        ("Intro\n| a | b |", "Intro"), ("Intro\n| a | b |\n|---|-", "Intro"), ("| a | b |\n|---|---|\n| 1 | 2", "a | b"),
        ("| a | b |\n|---|---|\n| 1 | 2 |\n", "a | b\n1 | 2"),
        // Math waits for its closing delimiter, but a price does not hold back the line.
        ("Rank $r", "Rank"), ("Then\n$$\nx^2", "Then"), ("It costs $5 per hour", "It costs $5 per hour"), ("It puts $1 - p", "It puts"), ("Then \\(x", "Then"),
        ("A link: <https://arx", "A link:"), ("If a < b", "If a < b"),
        // Nested in containers.
        ("> A **bol", "A bol"), ("- item **bol", "\t•\titem bol"), ("1. one\n2", "\t1.\tone"),
        // Spans across soft breaks: an opener on an earlier line of the paragraph still counts.
        ("A **bold\ncontinued", "A bold continued"), ("A **bold\ncontinued** done", "A bold continued done"),
        ("A **bold\ncontinued**", "A bold continued"), ("A `code\ncontinued", "A code continued"),
        ("See [the\npaper](https://arx", "See"), ("> A **bold\n> continued", "A bold continued"),
        ("- A *it\n  goes on", "\t•\tA it goes on"),
        // Single tildes strike through as cmark-gfm reads them once closed, but never open early: `~5%` is "about".
        ("a ~b~", "a b"), ("about ~5% more", "about ~5% more"), ("a ~~b", "a b"), ("a ~stri", "a ~stri"),
        // A last line of only markers or white space goes, and the line above it is repaired in turn.
        ("> A **bold that\n>", "A bold that"), ("- A *it that\n  ", "\t•\tA it that"),
    ])
    func streamingTailShows(_ text: String, _ expected: String) {
        #expect(Self.visible(text, streaming: true) == expected, "\(text.debugDescription)")
    }

    @Test func aFinishedAnswerIsParsedAsWritten() {
        #expect(Self.visible("A **bol", streaming: false) == "A **bol")
        #expect(Self.visible("See [the pa", streaming: false) == "See [the pa")
    }

    @Test func emphasisClosedEarlyDrawsAsTheFinishedTextDoes() throws {
        let streamed = try #require(Self.text("A **bold *it", streaming: true))
        let finished = try #require(Self.text("A **bold *it***", streaming: false))
        #expect(streamed.isEqual(to: finished))
    }

    /// Streamed a few characters at a time, no answer ever shows text that the finished answer takes back: each visible
    /// rendering is a prefix of the finished one.
    @Test(arguments: ["lora", "showcase", "code-tables", "math-edge", "attention", "paper-summary", "follow-up"])
    func nothingShownIsTakenBack(_ name: String) throws {
        try Self.expectNothingTakenBack(String(contentsOf: Self.answers.appendingPathComponent("\(name).md"), encoding: .utf8))
    }

    /// The same, for spans that wrap onto later lines of their paragraph, in a quote and a list too.
    @Test func nothingShownIsTakenBackAcrossSoftBreaks() throws {
        try Self.expectNothingTakenBack("""
        Some **strong text that
        wraps** onto a second line, with `code that
        wraps too` and a [link whose text
        wraps](https://example.com/a_b) and *emphasis
        over* two lines, and ~~double
        strike~~.

        > A quote with **bold that
        > wraps** inside it.

        - An item with *emphasis that
          wraps* in a list.
        """)
    }

    static func expectNothingTakenBack(_ answer: String) throws {
        let finished = Self.visible(answer, streaming: false)
        var failures: [String] = []
        var end = answer.startIndex
        var previous: [MarkdownBlock] = []
        while end < answer.endIndex {
            end = answer.index(after: end)
            let compilation = MarkdownCompiler.compile(String(answer[..<end]), style: .standard, previous: previous, nextRevision: 1,
                                                       options: CompileOptions(isStreaming: true))
            previous = compilation.blocks
            let shown = compilation.blocks.map { Self.visible($0.content) }.joined(separator: "\n")
            if !finished.hasPrefix(shown) {
                failures.append("at \(answer.distance(from: answer.startIndex, to: end)): …\(String(answer[..<end]).suffix(40).debugDescription) shows …\(shown.suffix(40).debugDescription)")
                if failures.count == 5 { break }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // MARK: Helpers

    static let answers = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Demo/Answers")

    static func compile(_ text: String, streaming: Bool) -> [MarkdownBlock] {
        MarkdownCompiler.compile(text, style: .standard, previous: [], nextRevision: 1, options: CompileOptions(isStreaming: streaming)).blocks
    }

    /// The text an answer draws, block by block: prose as its string, code as its code, table rows with their cells
    /// joined, display formulas as their TeX, a rule as a dash.
    static func visible(_ text: String, streaming: Bool) -> String {
        compile(text, streaming: streaming).map { visible($0.content) }.joined(separator: "\n")
    }

    static func text(_ text: String, streaming: Bool) -> NSAttributedString? {
        guard case .text(let rich) = compile(text, streaming: streaming).first?.content else { return nil }
        return rich.string
    }

    static func visible(_ content: BlockContent) -> String {
        switch content {
        case .text(let text), .source(let text): text.string.string
        case .quote(let blocks): blocks.map { visible($0.content) }.joined(separator: "\n")
        case .rule: "—"
        case .code(let code): code.text.string.string
        case .table(let table): table.rows.map { $0.map(\.text.string.string).joined(separator: " | ") }.joined(separator: "\n")
        case .stack(let items): items.map { visible($0.content) }.joined(separator: "\n")
        case .math(let formulas): formulas.map(\.tex).joined(separator: "\n")
        }
    }
}
