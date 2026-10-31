import XCTest

/// Checks on the demo that need a simulator: links reach `openURL`, one block holds a selection, headings carry the
/// header trait, and screenshots of the showcase. Shots go to `SHOTS_DIR` with `SHOTS_SUFFIX`, passed with a `TEST_RUNNER_` prefix.
@MainActor
final class DemoUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-answer", "showcase", "-rate", "0", "-hud", "0"]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 20))
    }

    func testLinksGoToOpenURL() {
        let link = app.links["link"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        let opened = app.staticTexts["opened-url"]
        XCTAssertTrue(opened.waitForExistence(timeout: 5))
        XCTAssertEqual(opened.label, "openURL: https://arxiv.org/abs/2106.09685")

        let reference = app.links["reference link"].firstMatch
        XCTAssertTrue(reference.exists, "a reference link resolves from the definition at the end of the answer")
    }

    func testHeadingsAreHeaders() throws {
        let heading = app.textViews.firstMatch
        XCTAssertEqual(heading.value as? String, "Every prose block")
        let paragraph = app.textViews.element(boundBy: 1)
        XCTAssertTrue(try traits(of: heading).contains(.header))
        XCTAssertFalse(try traits(of: paragraph).contains(.header))
    }

    /// XCTest keeps an element's traits on its snapshot without a public accessor.
    private func traits(of element: XCUIElement) throws -> UIAccessibilityTraits {
        let snapshot = try element.snapshot() as AnyObject
        return UIAccessibilityTraits(rawValue: (snapshot.value(forKey: "traits") as? UInt64) ?? 0)
    }

    func testOneBlockHoldsTheSelection() {
        app.terminate()
        app.launchArguments = ["-answer", "showcase", "-rate", "0", "-hud", "1"]
        app.launch()
        let meter = app.staticTexts["meter"]
        XCTAssertTrue(meter.waitForExistence(timeout: 20))
        let paragraphs = app.textViews.allElementsBoundByIndex.filter { ($0.value as? String)?.hasPrefix("This answer") == true || ($0.value as? String)?.hasPrefix("A soft break") == true }
        XCTAssertEqual(paragraphs.count, 2)
        paragraphs[0].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).doubleTap()
        XCTAssertTrue(meter.waitFor(label: "· 1 selected"), meter.label)
        shoot("selection-first")
        paragraphs[1].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3)).doubleTap()
        sleep(2)
        XCTAssertTrue(meter.waitFor(label: "· 1 selected"), "the first block still holds its selection: \(meter.label)")
        shoot("selection-second")
    }

    func testShots() {
        shoot("showcase-top")
        app.swipeUp(velocity: .slow)
        shoot("showcase-middle")
        app.swipeUp(velocity: .slow)
        app.swipeUp(velocity: .slow)
        shoot("showcase-end")
    }

    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            let suffix = ProcessInfo.processInfo.environment["SHOTS_SUFFIX"] ?? ""
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png"))
        }
    }
}

private extension XCUIElement {
    /// The meter reads its counters once a second, so wait for the next readings.
    func waitFor(label suffix: String) -> Bool {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if label.hasSuffix(suffix) { return true }
            usleep(200_000)
        }
        return label.hasSuffix(suffix)
    }
}
