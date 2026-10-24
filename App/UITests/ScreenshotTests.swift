import XCTest

/// README screenshots from the DEBUG demo rooms; no real TVs are contacted.
/// Run with TEST_RUNNER_ATV_SCREENSHOTS=1 and export the xcresult attachments.
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureReadmeScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ATV_SCREENSHOTS"] == "1", "Screenshots run on request only")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-apps", "--ui-testing-transfer-rooms", "--ui-testing-screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["Apps"].waitForExistence(timeout: 10))
        capture(app, "1-remote")

        app.buttons["Apps"].tap()
        XCTAssertTrue(app.navigationBars["Apps"].waitForExistence(timeout: 5))
        let star = app.buttons["starApp.com.comcast.cim.x2"]
        XCTAssertTrue(star.waitForExistence(timeout: 3)); star.tap()
        capture(app, "2-apps")
        app.buttons["Done"].tap()

        app.buttons["Power"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        capture(app, "3-power")
        app.buttons["Done"].tap()

        app.buttons["remoteSettings"].tap()
        XCTAssertTrue(app.buttons["manageRooms"].waitForExistence(timeout: 3))
        capture(app, "4-settings")
        app.buttons["manageRooms"].tap()
        XCTAssertTrue(app.navigationBars["Rooms"].waitForExistence(timeout: 3))
        capture(app, "5-rooms")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
