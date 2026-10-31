import AppKit
import Foundation
import Observation
@testable import StreamMarkdown
import Testing

@MainActor
struct MarkdownStreamTests {
    @Test func parsesOffTheMainThreadAndPublishesTheBlocks() async {
        let probe = Probe()
        let stream = MarkdownStream(compile: probe.compile)
        stream.update(text: "# Title\n\nBody")
        await stream.settled()
        #expect(probe.onMain == [false])
        #expect(stream.blocks.map(\.kind) == [.heading(level: 1), .paragraph])
        #expect(stream.blocks.map(\.id) == [0, 1])
        #expect(stream.blocks.map(\.range) == [0..<7, 9..<13])
    }

    @Test func runsOneParseAtATimeAndParsesOnlyTheLatestTextNext() async {
        let probe = Probe(delay: 0.03)
        let stream = MarkdownStream(compile: probe.compile)
        let text = Samples.answer
        for end in stride(from: 10, through: text.count, by: 10) {
            stream.update(text: String(text.prefix(end)))
            await Task.yield()
        }
        stream.update(text: text)
        await stream.settled()
        #expect(probe.mostAtOnce == 1)
        #expect(probe.texts.count < text.count / 10, "texts that arrived during a parse were coalesced")
        #expect(probe.texts.last == text)
        #expect(stream.blocks.map(\.source) == BlockParser.parse(text).map(\.source))
    }

    @Test func finishedBlocksAreNeverBuiltAgain() async {
        let stream = MarkdownStream()
        let text = Samples.answer
        var previous: [MarkdownBlock] = []
        var expectedBuilds = 0
        for end in stride(from: 7, through: text.count + 6, by: 7) {
            stream.update(text: String(text.prefix(end)))
            await stream.settled()
            let blocks = stream.blocks
            for block in blocks {
                if block.id < previous.count - 1 {
                    #expect(block.key == previous[block.id].key, "block \(block.id) changed after a later block began")
                }
                if block.id < previous.count, previous[block.id].key == block.key {
                    #expect(block.revision == previous[block.id].revision, "block \(block.id) was rebuilt with unchanged source")
                } else {
                    expectedBuilds += 1
                }
            }
            previous = blocks
        }
        #expect(stream.builtCount == expectedBuilds)
        let finished = previous.dropLast()
        #expect(finished.allSatisfy { $0.revision < previous.last!.revision }, "the last revisions went to the block being written")
    }

    @Test func aDefinitionThatArrivesLaterRebuildsOnlyTheBlockUsingIt() async throws {
        let stream = MarkdownStream()
        let body = "See [the paper][lora].\n\nUnrelated text."
        stream.update(text: body)
        await stream.settled()
        let before = stream.blocks
        #expect(try text(before[0]).attribute(.link, at: 4, effectiveRange: nil) == nil)

        stream.update(text: body + "\n\n[lora]: https://arxiv.org/abs/2106.09685")
        await stream.settled()
        let after = stream.blocks
        #expect(after.count == 2)
        #expect(after[0].revision != before[0].revision)
        #expect(after[1].revision == before[1].revision)
        #expect(try text(after[0]).string == "See the paper.")
        #expect(try text(after[0]).attribute(.link, at: 4, effectiveRange: nil) as? URL == URL(string: "https://arxiv.org/abs/2106.09685"))
    }

    @Test func aNewEnvironmentRebuildsEveryBlock() async throws {
        let stream = MarkdownStream()
        stream.update(text: Samples.answer)
        await stream.settled()
        let before = stream.blocks
        var style = StreamMarkdownStyle()
        style.body = .init(.title3, design: .serif)
        stream.update(environment: RenderEnvironment(style: style))
        await stream.settled()
        #expect(stream.blocks.count == before.count)
        #expect(zip(before, stream.blocks).allSatisfy { $0.revision != $1.revision })
        let font = try #require(try text(stream.blocks[1]).attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == stream.style.body.size)
        #expect(stream.style.body.size > ResolvedStyle(RenderEnvironment()).body.size)
    }

    @Test func aFinishedAnswerCanBeLaidOutAtOnce() {
        let probe = Probe()
        let stream = MarkdownStream(compile: probe.compile)
        stream.start(text: Samples.answer, environment: RenderEnvironment(), now: true)
        #expect(stream.blocks.count == BlockParser.parse(Samples.answer).count)
        #expect(probe.onMain == [true])
    }

    @Test func anUnchangedParseLeavesTheBlocksAlone() async {
        let stream = MarkdownStream()
        stream.update(text: "One\n\nTwo")
        await stream.settled()
        let observed = Flag()
        withObservationTracking { _ = stream.blocks } onChange: { observed.set() }
        stream.update(text: "One\n\nTwo\n")
        await stream.settled()
        #expect(!observed.value, "a parse that changes no block publishes nothing")
    }

    private func text(_ block: MarkdownBlock) throws -> NSAttributedString {
        guard case .text(let text) = block.content else { throw Failure.notText }
        return text.string
    }

    private enum Failure: Error { case notText }
}

/// Wraps the real compile, recording the thread, the texts parsed and how many ran at once.
private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private let delay: TimeInterval
    private var running = 0
    private(set) var mostAtOnce = 0
    private(set) var onMain: [Bool] = []
    private(set) var texts: [String] = []

    init(delay: TimeInterval = 0) {
        self.delay = delay
    }

    var compile: MarkdownStream.Compile {
        { [self] text, style, previous, revision in
            lock.withLock {
                running += 1
                mostAtOnce = max(mostAtOnce, running)
                onMain.append(Thread.isMainThread)
                texts.append(text)
            }
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            defer { lock.withLock { running -= 1 } }
            return MarkdownCompiler.compile(text, style: style, previous: previous, nextRevision: revision)
        }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false
    var value: Bool { lock.withLock { isSet } }
    func set() { lock.withLock { isSet = true } }
}
