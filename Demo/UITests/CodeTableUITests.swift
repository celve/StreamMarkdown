import XCTest

/// Code blocks and tables on the simulator: Copy reaches the pasteboard, long code and wide tables scroll sideways by
/// touch drag while a vertical drag on them still scrolls the answer, and table headers stay on one line.
@MainActor
final class CodeTableUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-answer", "code-tables", "-rate", "0", "-hud", "0"]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 20))
    }

    func testCopyPutsTheCodeOnThePasteboard() {
        let copy = app.buttons["Copy code"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2), "the button says it copied")
        let copied = app.staticTexts["copied"]
        XCTAssertTrue(copied.waitForExistence(timeout: 5))
        XCTAssertEqual(copied.label, "copied: import torch")
        shoot("code-copied")
        sleep(3)
        XCTAssertFalse(app.buttons["Copied"].exists, "the button goes back to Copy")
    }

    func testLongCodeScrollsSidewaysByDrag() {
        let code = textView("import torch")
        let before = code.frame
        XCTAssertGreaterThan(before.maxX, answer.frame.maxX, "long lines do not wrap")
        drag(from: CGPoint(x: answer.frame.minX + answer.frame.width * 0.7, y: before.minY + 40), by: CGVector(dx: -250, dy: 0))
        XCTAssertLessThan(code.frame.minX, before.minX - 100, "the code moved left")
        XCTAssertEqual(code.frame.minY, before.minY, accuracy: 2, "a sideways drag leaves the answer where it was")
        shoot("code-scrolled")
    }

    func testAVerticalDragOnCodeScrollsTheAnswer() {
        let code = textView("import torch")
        let before = code.frame
        drag(from: CGPoint(x: answer.frame.midX, y: before.minY + 60), by: CGVector(dx: 0, dy: -250))
        XCTAssertLessThan(code.frame.minY, before.minY - 100, "the answer scrolled")
        XCTAssertEqual(code.frame.minX, before.minX, accuracy: 2)
    }

    func testAWideTableScrollsSidewaysAndKeepsItsHeaderOnOneLine() {
        let header = textView("Trainable parameters"), first = textView("Method")
        reveal(textView("Prefix tuning"))
        XCTAssertEqual(header.frame.height, first.frame.height, accuracy: 1, "a long header stays on one line")
        XCTAssertGreaterThan(header.frame.width, first.frame.width)
        shoot("table-wide")
        let before = header.frame
        drag(from: CGPoint(x: answer.frame.minX + answer.frame.width * 0.7, y: before.midY + 60), by: CGVector(dx: -300, dy: 0))
        XCTAssertLessThan(header.frame.minX, before.minX - 150, "the table moved left")
        XCTAssertEqual(header.frame.minY, before.minY, accuracy: 2, "a sideways drag leaves the answer where it was")
        XCTAssertTrue(textView("Houlsby et al.").isHittable, "the last column scrolled into view")
        shoot("table-scrolled")
    }

    func testLongCellsWrapAtTheColumnsWidth() {
        let wrapped = textView("Small ranks"), short = textView("Rank r")
        reveal(textView("Barely matters"))
        XCTAssertGreaterThan(wrapped.frame.height, short.frame.height * 1.8, "a long body cell wraps")
        XCTAssertLessThanOrEqual(wrapped.frame.maxX, answer.frame.maxX, "a table of wrapped cells fits the answer's width")
        XCTAssertEqual(textView("Which matrices").frame.height, short.frame.height, accuracy: 1, "the widest column gives way, not the short one")
        shoot("table-wrapped")
    }

    func testCodeInAListItemIsACodeBlock() {
        let code = textView("pip install peft")
        reveal(textView("let config"))
        let item = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Install the libraries")).firstMatch
        XCTAssertGreaterThan(code.frame.minX, item.frame.minX + 15, "a list's code block sits at its item's indent")
        XCTAssertEqual(code.frame.minX, textView("let config").frame.minX, accuracy: 1)
        shoot("code-in-list")
        reveal(textView("epoch 1/3"))
        shoot("code-end")
    }

    func testStreamingCodeIsPlainUntilItCloses() {
        app.terminate()
        app.launchArguments = ["-answer", "code-tables", "-rate", "40", "-hud", "0"]
        app.launch()
        let code = app.textViews.matching(NSPredicate(format: "value BEGINSWITH %@", "import torch")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 20))
        sleep(2)
        shoot("code-streaming")
    }

    private var window: XCUIElement { app.windows.firstMatch }

    /// The answer's vertical scroll view: the tallest one, since each code block and table has its own.
    private var answer: XCUIElement {
        app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height } ?? window
    }

    private func textView(_ prefix: String) -> XCUIElement {
        let view = app.textViews.matching(NSPredicate(format: "value BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(view.waitForExistence(timeout: 5), "no text view starting \(prefix)")
        return view
    }

    /// Scrolls the answer up until the element is on screen, dragging in the left margin.
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 where element.frame.maxY > window.frame.maxY - 80 {
            drag(from: CGPoint(x: 8, y: window.frame.height * 0.7), by: CGVector(dx: 0, dy: -window.frame.height * 0.35))
        }
    }

    private func drag(from point: CGPoint, by offset: CGVector) {
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(offset), withVelocity: 600, thenHoldForDuration: 0.3)
        usleep(500_000)
    }
}
