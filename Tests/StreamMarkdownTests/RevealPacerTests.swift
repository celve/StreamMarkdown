@testable import StreamMarkdown
import Testing

struct RevealPacerTests {
    @Test func theFirstTextShowsAtOnceAndLaterTextWaitsForATick() {
        var pacer = RevealPacer("Already here.")
        #expect(pacer.revealed == "Already here.")
        pacer.receive("Already here. More")
        #expect(pacer.revealed == "Already here.")
        #expect(pacer.backlog == 5)
        let ticked1 = pacer.advance(to: 0, paced: true)
        #expect(ticked1)
        #expect(pacer.revealed.count > "Already here.".count)
        let ticked2 = pacer.advance(to: 0.02, paced: true)
        #expect(!ticked2, "no second tick within 50 ms")
    }

    @Test func steadyInputComesOutAtItsOwnRate() {
        var pacer = RevealPacer()
        var text = "", shown: [Int] = []
        for tick in 0..<100 {
            text += String(repeating: "a", count: 24)
            pacer.receive(text)
            let before = pacer.revealed.count
            _ = pacer.advance(to: Double(tick) * 0.05, paced: true)
            shown.append(pacer.revealed.count - before)
        }
        let settled = shown.suffix(50)
        #expect(settled.allSatisfy { (22...26).contains($0) }, "\(settled)")
        #expect(pacer.backlog < 24 * 8, "it lags well under half a second")
    }

    @Test func aBurstDrainsWithinASecondInEvenSteps() {
        var pacer = RevealPacer()
        pacer.receive(String(repeating: "word ", count: 120))
        var steps: [Int] = [], time = 0.0
        while pacer.backlog > 0, time < 2 {
            let before = pacer.revealed.count
            _ = pacer.advance(to: time, paced: true)
            steps.append(pacer.revealed.count - before)
            time += 0.05
        }
        #expect(pacer.backlog == 0)
        #expect(time <= 0.8, "drained after \(time) s")
        #expect(steps.max()! <= 600 / 6, "no step shows more than a sixth of the burst: \(steps)")
        #expect(steps.allSatisfy { $0 > 0 })
    }

    @Test func unpacedTicksShowTheWholeBacklogButOnlyOnTheTick() {
        var pacer = RevealPacer()
        pacer.receive("One two three")
        let ticked3 = pacer.advance(to: 1, paced: false)
        #expect(ticked3)
        #expect(pacer.revealed == "One two three")
        pacer.receive("One two three four")
        let ticked4 = pacer.advance(to: 1.01, paced: false)
        #expect(!ticked4)
        let ticked5 = pacer.advance(to: 1.05, paced: false)
        #expect(ticked5)
        #expect(pacer.revealed == "One two three four")
    }

    @Test func endingRevealsEverythingAndANewTextStartsOver() {
        var pacer = RevealPacer()
        pacer.receive(String(repeating: "x", count: 300))
        _ = pacer.advance(to: 0, paced: true)
        pacer.revealAll()
        #expect(pacer.revealed.count == 300)
        #expect(pacer.backlog == 0)
        pacer.receive("A different answer")
        #expect(pacer.revealed == "A different answer", "text that does not extend the last shows at once")
    }

    @Test func neverSplitsACharacter() {
        var pacer = RevealPacer()
        let text = String(repeating: "é👩🏽‍💻漢", count: 40)
        pacer.receive(text)
        var time = 0.0
        while pacer.backlog > 0 {
            _ = pacer.advance(to: time, paced: true)
            #expect(text.hasPrefix(pacer.revealed))
            #expect(pacer.revealed.utf8.count == pacer.shown)
            time += 0.05
        }
        #expect(pacer.revealed == text)
    }
}
