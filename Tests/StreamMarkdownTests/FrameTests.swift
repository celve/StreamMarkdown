import Foundation
import Observation
@testable import StreamMarkdown
import Testing

/// The stream driven by a frame clock, as the view drives it: paced text, blocks published at frame starts, slots.
@MainActor
struct FrameTests {
    @Test func aStreamingAnswerIsPacedAndPublishedOnlyAtFrameStarts() async throws {
        let (stream, clock) = Self.streaming()
        let answer = "First paragraph of the answer.\n\nSecond paragraph, which keeps growing for a while longer."
        stream.receive(answer)
        #expect(clock.requests > 0)
        #expect(stream.text.isEmpty, "nothing shows before a frame")

        var time = 0.0
        _ = stream.frame(at: time)
        let first = stream.text
        #expect(!first.isEmpty && first.count < answer.count, "the first tick shows a stretch, not everything")
        await Self.parsed(stream)
        #expect(stream.blocks.isEmpty, "a finished parse waits for the next frame")
        time += 1 / 60
        _ = stream.frame(at: time)
        #expect(stream.blocks.map(\.source).joined() == first.trimmingCharacters(in: .whitespacesAndNewlines))

        var shown = [first]
        while stream.frame(at: time) || stream.isParsing {
            if stream.text != shown.last { shown.append(stream.text) }
            time += 1 / 60
            await Self.parsed(stream)
        }
        #expect(stream.text == answer)
        #expect(shown.count >= 5, "revealed over several ticks: \(shown.count)")
        #expect(zip(shown, shown.dropFirst()).allSatisfy { $1.hasPrefix($0) })

        stream.update(isStreaming: false)
        await stream.settled()
        #expect(stream.blocks.map(\.source) == BlockParser.parse(answer).map(\.source))
    }

    @Test func endingTheStreamShowsTheRestAtOnce() async {
        let (stream, clock) = Self.streaming()
        stream.receive(String(repeating: "Words keep coming. ", count: 40))
        _ = stream.frame(at: 0)
        #expect(stream.text.count < 760)
        stream.update(isStreaming: false)
        await stream.settled()
        #expect(stream.text.count == 760)
        #expect(stream.blocks.count == 1)
        withExtendedLifetime(clock) {}
    }

    @Test func underReduceMotionEachTickShowsEverythingThatArrived() async {
        let (stream, clock) = Self.streaming(reduceMotion: true)
        let answer = String(repeating: "Words keep coming. ", count: 40)
        stream.receive(answer)
        #expect(stream.text.isEmpty, "still gathered onto the tick")
        _ = stream.frame(at: 0)
        #expect(stream.text == answer)
        await Self.parsed(stream)
        _ = stream.frame(at: 1 / 60)
        #expect(stream.slots.allSatisfy { !$0.fadesIn }, "nothing fades under Reduce Motion")
        withExtendedLifetime(clock) {}
    }

    @Test func blocksArrivingWhileStreamingFadeInAndThoseShownAtOnceDoNot() async {
        let (stream, clock) = Self.streaming(text: "Shown when the view appeared.")
        await Self.drain(stream)
        stream.receive("Shown when the view appeared.\n\nArrived later.")
        await Self.drain(stream)
        #expect(stream.slots.map(\.fadesIn) == [false, true])
        withExtendedLifetime(clock) {}
    }

    @Test func onlyTheSlotBeingWrittenChanges() async throws {
        let stream = MarkdownStream()
        stream.update(text: "# Title\n\nFirst paragraph.\n\nSecond")
        await stream.settled()
        let slots = stream.slots
        let revisions = slots.map(\.revision)
        let finished = Flag(), list = Flag()
        withObservationTracking { _ = (slots[0].content, slots[0].kind, slots[1].content, slots[1].kind) } onChange: { finished.set() }
        withObservationTracking { _ = stream.slots } onChange: { list.set() }

        stream.update(text: "# Title\n\nFirst paragraph.\n\nSecond paragraph grows")
        await stream.settled()
        #expect(!finished.value, "finished blocks were not touched")
        #expect(!list.value, "the slot list is unchanged while no block is added")
        #expect(stream.slots.map(ObjectIdentifier.init) == slots.map(ObjectIdentifier.init))
        #expect(stream.slots[2].revision != revisions[2])
        #expect(Array(stream.slots.prefix(2).map(\.revision)) == Array(revisions.prefix(2)))

        stream.update(text: "# Title\n\nFirst paragraph.\n\nSecond paragraph grows.\n\nThird")
        await stream.settled()
        #expect(list.value, "a new block changes the list")
        #expect(stream.slots.count == 4)
        #expect(stream.slots.prefix(3).map(ObjectIdentifier.init) == slots.map(ObjectIdentifier.init), "existing slots are kept")
    }

    // MARK: Helpers

    static func streaming(text: String = "", reduceMotion: Bool = false) -> (MarkdownStream, ManualClock) {
        let stream = MarkdownStream()
        let clock = ManualClock()
        stream.start(text: text, environment: RenderEnvironment(), isStreaming: true, reduceMotion: reduceMotion, clock: clock)
        return (stream, clock)
    }

    /// Waits for the parse running off the main thread, without publishing it.
    static func parsed(_ stream: MarkdownStream) async {
        while stream.isParsing { try? await Task.sleep(for: .milliseconds(1)) }
    }

    /// Runs frames until everything received is shown and published.
    static func drain(_ stream: MarkdownStream) async {
        var time = 0.0
        while stream.frame(at: time) || stream.isParsing {
            time += 1 / 60
            await parsed(stream)
        }
    }
}

@MainActor
final class ManualClock: FrameClock {
    private(set) var requests = 0
    func requestFrames() { requests += 1 }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false
    var value: Bool { lock.withLock { isSet } }
    func set() { lock.withLock { isSet = true } }
}
