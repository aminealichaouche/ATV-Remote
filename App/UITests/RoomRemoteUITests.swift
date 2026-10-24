import XCTest

final class RoomRemoteUITests: XCTestCase {
    @MainActor
    func testRoomRoundTripRetainsEveryVisitedSessionAndBackgroundReturn() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-room-sessions"]
        app.launch()
        let log = app.staticTexts["roomSessionLog"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        let original = log.label.split(separator: "|").map(String.init)
        XCTAssertEqual(original.count, 2)
        app.buttons["roomMenu"].tap(); app.buttons["Family Room"].tap()
        _ = expectation(for: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "ui-family-apple=", "ui-family-samsung="), evaluatedWith: log)
        waitForExpectations(timeout: 3)
        // Wait for the synthetic handshake callbacks to reach the actual store.
        _ = expectation(for: NSPredicate { _, _ in log.label.split(separator: "|").allSatisfy { $0.hasSuffix(";1;Connected") } }, evaluatedWith: log)
        waitForExpectations(timeout: 3)
        let all = log.label
        for entry in original { XCTAssertTrue(all.contains(entry)) }
        XCTAssertEqual(all.split(separator: "|").count, 4)
        for _ in 0..<2 {
            app.buttons["roomMenu"].tap(); app.buttons["Living Room"].tap()
            XCTAssertEqual(log.label, all, "Returning must reuse actors and retain all four sessions")
            app.buttons["roomMenu"].tap(); app.buttons["Family Room"].tap()
            XCTAssertEqual(log.label, all)
        }
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 2) || app.wait(for: .runningBackgroundSuspended, timeout: 2))
        app.activate()
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        XCTAssertEqual(log.label, all)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Visited room sessions survive room round trips and foreground return"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testForegroundCheckDowngradesLostUnselectedSessionWithoutDisconnectingFamily() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-room-sessions"]
        app.launch()
        XCTAssertTrue(app.buttons["roomMenu"].waitForExistence(timeout: 10))
        app.buttons["roomMenu"].tap(); app.buttons["Family Room"].tap()
        let log = app.staticTexts["roomSessionLog"]
        _ = expectation(for: NSPredicate { _, _ in log.label.split(separator: "|").count == 4 && log.label.split(separator: "|").allSatisfy { $0.hasSuffix(";1;Connected") } }, evaluatedWith: log)
        waitForExpectations(timeout: 3)
        let family = log.label.split(separator: "|").filter { $0.hasPrefix("ui-family-") }.map(String.init)
        app.buttons["loseLivingOnReturn"].tap()
        XCTAssertFalse(log.label.contains("Not connected"))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 2) || app.wait(for: .runningBackgroundSuspended, timeout: 2))
        app.activate()
        _ = expectation(for: NSPredicate(format: "label CONTAINS %@", ";1;Not connected"), evaluatedWith: log)
        waitForExpectations(timeout: 1.5)
        for entry in family { XCTAssertTrue(log.label.contains(entry)) }
        app.buttons["roomMenu"].tap(); app.buttons["Living Room"].tap()
        let apple = app.descendants(matching: .any)["appleRemoteConnection"].firstMatch
        let samsung = app.descendants(matching: .any)["samsungRemoteConnection"].firstMatch
        XCTAssertEqual(apple.value as? String, "Not connected")
        XCTAssertEqual(samsung.value as? String, "Connected")
        apple.tap()
        _ = expectation(for: NSPredicate(format: "value == %@", "Connected"), evaluatedWith: apple)
        waitForExpectations(timeout: 3)
        for entry in family { XCTAssertTrue(log.label.contains(entry)) }
        XCTAssertTrue(log.label.contains(";2;Connected"))
    }

    @MainActor
    func testUniversalStarsDefaultModeSharedAcrossTVsAndPersistedOffChoice() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        func launch(family: Bool = false, reset: Bool = false) {
            app.terminate()
            app.launchArguments = ["--ui-testing-apps"] + (family ? ["--ui-testing-apps-family"] : []) + (reset ? ["--ui-testing-reset"] : [])
            app.launch()
            XCTAssertTrue(app.buttons["Apps"].waitForExistence(timeout: 10))
        }
        func openApps(expectImport: Bool, starred: Bool) {
            app.buttons["Apps"].tap()
            XCTAssertTrue(app.buttons["starApp.com.comcast.cim.x2"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.buttons["importAppStars"].exists, expectImport)
            XCTAssertEqual(app.buttons["starApp.com.comcast.cim.x2"].value as? String, starred ? "Starred" : "Not starred")
        }
        launch(reset: true)
        app.buttons["remoteSettings"].tap()
        let toggle = app.switches["universalStarsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3)); XCTAssertEqual(toggle.value as? String, "1")
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Universal stars settings default"; image.lifetime = .keepAlways; add(image)
        app.buttons["Done"].tap()
        openApps(expectImport: false, starred: false)
        app.buttons["starApp.com.comcast.cim.x2"].tap()
        launch(family: true)
        openApps(expectImport: false, starred: true)
        app.buttons["starApp.com.comcast.cim.x2"].tap()
        launch()
        openApps(expectImport: false, starred: false)
        app.buttons["Done"].tap()
        _ = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Apps"])
        waitForExpectations(timeout: 3)
        app.buttons["remoteSettings"].tap()
        let offToggle = app.switches["universalStarsToggle"]
        XCTAssertTrue(offToggle.waitForExistence(timeout: 3))
        offToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        _ = expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: offToggle)
        waitForExpectations(timeout: 3)
        app.buttons["Done"].tap()
        openApps(expectImport: true, starred: false)
        app.buttons["starApp.com.comcast.cim.x2"].tap()
        launch(family: true)
        openApps(expectImport: true, starred: false)
        launch()
        openApps(expectImport: true, starred: true)
        app.buttons["Done"].tap()
        _ = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Apps"])
        waitForExpectations(timeout: 3)
        app.buttons["remoteSettings"].tap()
        let onToggle = app.switches["universalStarsToggle"]
        XCTAssertTrue(onToggle.waitForExistence(timeout: 3)); XCTAssertEqual(onToggle.value as? String, "0")
        onToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        _ = expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: onToggle)
        waitForExpectations(timeout: 3)
        app.buttons["Done"].tap()
        openApps(expectImport: false, starred: false)
        launch(family: true)
        openApps(expectImport: false, starred: false)
    }

    @MainActor
    func testAutomaticRetriesAndNavigationSwitchRequestConnections() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-retry"]
        app.launch()
        let count = app.staticTexts["retryAttemptLog"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        _ = expectation(for: NSPredicate(format: "label == %@", "2,2"), evaluatedWith: count)
        waitForExpectations(timeout: 7)
        app.buttons["Samsung"].tap()
        let requests = app.staticTexts["navigationConnectLog"]
        _ = expectation(for: NSPredicate(format: "label == %@", "Samsung TV;"), evaluatedWith: requests)
        waitForExpectations(timeout: 2)
        let samsung = XCTAttachment(screenshot: app.screenshot()); samsung.name = "Larger Samsung Sources tool"; samsung.lifetime = .keepAlways; add(samsung)
        app.buttons["Apple TV"].tap()
        let apple = XCTAttachment(screenshot: app.screenshot()); apple.name = "Larger Keyboard and Apps tools"; apple.lifetime = .keepAlways; add(apple)
        _ = expectation(for: NSPredicate(format: "label == %@", "Samsung TV;Apple TV;"), evaluatedWith: requests)
        waitForExpectations(timeout: 2)
    }

    @MainActor
    func testCompactSettingsSavedTVDisclosureAndAddTVScreen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-connections"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap()
        let apple = app.buttons["appleDeviceMenu"], samsung = app.buttons["samsungDeviceMenu"]
        let appleAction = app.buttons["appleConnectionAction"], samsungAction = app.buttons["samsungConnectionAction"]
        XCTAssertTrue(appleAction.waitForExistence(timeout: 3))
        XCTAssertEqual(apple.value as? String, "Living Room Apple TV, 127.0.0.1")
        XCTAssertEqual(samsung.value as? String, "Living Room TV, 127.0.0.1")
        XCTAssertEqual(apple.frame.minX, samsung.frame.minX, accuracy: 1)
        XCTAssertEqual(appleAction.frame.maxX, samsungAction.frame.maxX, accuracy: 1)
        XCTAssertLessThan(apple.frame.maxX, appleAction.frame.minX)
        XCTAssertEqual(apple.frame.midY, appleAction.frame.midY - 8, accuracy: 20)
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "Compact left TV menus and right connection actions"; settings.lifetime = .keepAlways; add(settings)
        app.buttons["manageDevices"].tap()
        XCTAssertTrue(app.buttons["savedTVsDisclosure"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["manageTV.ui-apple-status"].exists)
        app.buttons["savedTVsDisclosure"].tap()
        XCTAssertTrue(app.buttons["manageTV.ui-apple-status"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Rename"].exists)
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "Compact saved TV rows with inline arrows"; saved.lifetime = .keepAlways; add(saved)
        app.buttons["manageTV.ui-apple-status"].tap()
        XCTAssertTrue(app.navigationBars["Manage TV"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["manageTVHeading"].label, "Living Room (Apple TV)")
        XCTAssertTrue(app.buttons["Re-pair"].exists)
        XCTAssertFalse(app.buttons["Remove saved MAC"].exists)
        app.buttons["clearManageTVIP"].tap()
        let ip = app.textFields["manageTVIP"]
        ip.tap(); ip.typeText("192.168.1.72")
        let name = app.textFields["manageTVName"]
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 11)); name.typeText("Den")
        let save = app.buttons["saveTVNetwork"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.navigationBars["Your TVs"].waitForExistence(timeout: 3))
        app.buttons["manageTV.ui-apple-status"].tap()
        XCTAssertEqual(app.staticTexts["manageTVHeading"].label, "Den (Apple TV)")
        XCTAssertEqual(ip.value as? String, "192.168.1.72")
        tapBack(in: app.navigationBars["Manage TV"], parent: "Your TVs")
        app.buttons["addTV"].tap()
        XCTAssertTrue(app.navigationBars["Add a TV"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["TV’s local IP address"].exists)
    }

    @MainActor
    func testActualAppStarSearchExportImportAndColdRelaunchWithoutRooms() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-apps"]
        app.launch()
        XCTAssertTrue(app.buttons["Apps"].waitForExistence(timeout: 10)); app.buttons["Apps"].tap()
        let star = app.buttons["starApp.com.comcast.cim.x2"]
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        XCTAssertEqual(star.value as? String, "Not starred"); star.tap()
        XCTAssertEqual(star.value as? String, "Starred")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.exists); search.tap(); search.typeText("xfinity")
        XCTAssertTrue(app.buttons["launchApp.com.comcast.cim.x2"].exists)
        XCTAssertEqual(app.buttons["launchApp.com.comcast.cim.x2"].label, "Open Xfinity Stream")
        XCTAssertFalse(app.buttons["launchApp.com.example.Stream"].exists)
        backgroundAndReturn(app)
        XCTAssertTrue(app.navigationBars["Apps"].waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "xfinity")
        XCTAssertTrue(star.isEnabled)
        XCTAssertFalse(app.buttons["launchApp.com.example.Stream"].exists)
        let apps = XCTAttachment(screenshot: app.screenshot()); apps.name = "App search and starred Xfinity Stream"; apps.lifetime = .keepAlways; add(apps)
        if !app.buttons["Done"].exists { app.buttons["Close"].tap() }
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.buttons["remoteSettings"].tap(); app.buttons["transferSetup"].tap()
        XCTAssertTrue(app.buttons["shareRoomGroups"].exists)
        app.buttons["shareRoomGroups"].tap() // Exercise an explicit TV/stars-only transfer.
        XCTAssertEqual(app.buttons["shareRoomGroups"].value as? String, "Not selected")
        XCTAssertFalse(app.buttons["shareTVAccess"].exists)
        if !app.buttons["prepareTransfer"].isHittable { app.swipeUp() }
        app.buttons["prepareTransfer"].tap()
        XCTAssertTrue(app.buttons["shareSetupFile"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["transferCode"].exists)
        backgroundAndReturn(app)
        XCTAssertTrue(app.navigationBars["Transfer setup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shareSetupFile"].exists)
        XCTAssertTrue(app.staticTexts["1 starred app included"].exists)
        let ready = XCTAttachment(screenshot: app.screenshot()); ready.name = "AirDrop ready without transfer phrase"; ready.lifetime = .keepAlways; add(ready)
        app.terminate()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-apps", "--ui-testing-import-last-export"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["transferSetup"].tap()
        XCTAssertFalse(app.secureTextFields["importTransferCode"].exists)
        XCTAssertTrue(app.buttons["importStarredApps"].waitForExistence(timeout: 5))
        backgroundAndReturn(app)
        XCTAssertTrue(app.buttons["importStarredApps"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["importStarredApps"].value as? String, "Selected")
        XCTAssertFalse(app.buttons["importRoom.ui-apps-room"].exists)
        if !app.buttons["confirmSetupImport"].isHittable { app.swipeUp() }
        app.buttons["confirmSetupImport"].tap()
        XCTAssertTrue(app.staticTexts["transferSuccess"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["transferSuccess"].label.contains("Copied starred apps"))
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["roomMenu"].value as? String, "Receiver Room")
        app.buttons["Apps"].tap()
        XCTAssertTrue(star.waitForExistence(timeout: 3)); XCTAssertEqual(star.value as? String, "Starred")
        app.terminate(); app.launchArguments = ["--ui-testing-apps"]; app.launch()
        XCTAssertTrue(app.buttons["Apps"].waitForExistence(timeout: 10)); app.buttons["Apps"].tap()
        XCTAssertTrue(star.waitForExistence(timeout: 3)); XCTAssertEqual(star.value as? String, "Starred")
    }

    @MainActor
    func testProtectedTransferStillRequiresPhraseAndNativeSharingCanBeCancelled() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-apps"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["transferSetup"].tap()
        let protection = app.switches["requireTransferPhrase"]
        if !protection.isHittable { app.swipeUp() }
        XCTAssertEqual(protection.value as? String, "0")
        protection.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(protection.value as? String, "1")
        if !app.buttons["prepareTransfer"].isHittable { app.swipeUp() }
        app.buttons["prepareTransfer"].tap()
        XCTAssertTrue(app.staticTexts["transferCode"].waitForExistence(timeout: 5))
        let phrase = app.staticTexts["transferCode"].label
        app.buttons["shareSetupFile"].tap()
        let shareSheet = app.otherElements["shareSheet.activity.contentView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5))
        let sheet = XCTAttachment(screenshot: app.screenshot()); sheet.name = "Native setup file sharing"; sheet.lifetime = .keepAlways; add(sheet)
        // iOS 27 presents sharing as a floating popover, dismissed outside it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.28)).tap()
        _ = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: shareSheet)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["transferCode"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["transferCode"].label, phrase)
        app.terminate()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-apps", "--ui-testing-import-last-export"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["transferSetup"].tap()
        let field = app.secureTextFields["importTransferCode"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirmSetupImport"].exists)
        field.tap(); field.typeText(phrase); app.buttons["unlockSetup"].tap()
        XCTAssertTrue(app.staticTexts["importSummary"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRoomAssignmentsShareReviewImportAndPersistWithBothTVTypes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-apps", "--ui-testing-transfer-rooms"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["transferSetup"].tap()
        XCTAssertEqual(app.buttons["shareRoomGroups"].value as? String, "Selected")
        if !app.buttons["prepareTransfer"].isHittable { app.swipeUp() }
        app.buttons["prepareTransfer"].tap()
        XCTAssertTrue(app.staticTexts["exportRooms"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["exportRooms"].label, "2 room assignments included")
        XCTAssertFalse(app.staticTexts["transferCode"].exists)
        XCTAssertFalse(app.buttons["saveSetupFile"].exists)
        app.buttons["shareSetupFile"].tap()
        let save = app.cells["Save to Files"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let sharing = XCTAttachment(screenshot: app.screenshot()); sharing.name = "One share sheet offers Save to Files"; sharing.lifetime = .keepAlways; add(sharing)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.28)).tap()
        _ = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.otherElements["shareSheet.activity.contentView"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["exportRooms"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-apps", "--ui-testing-import-last-export"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["transferSetup"].tap()
        XCTAssertFalse(app.secureTextFields["importTransferCode"].exists)
        let living = app.buttons["importRoom.ui-apps-room"]
        for _ in 0..<5 { if living.exists { break }; app.swipeUp() }
        XCTAssertTrue(living.exists)
        XCTAssertEqual(living.value as? String, "Selected")
        let family = app.buttons["importRoom.ui-share-family"]
        for _ in 0..<5 { if family.exists { break }; app.swipeUp() }
        XCTAssertTrue(family.exists)
        let review = XCTAttachment(screenshot: app.screenshot()); review.name = "Room assignments reviewed separately from TV authorization"; review.lifetime = .keepAlways; add(review)
        let confirm = app.buttons["confirmSetupImport"]
        for _ in 0..<5 { if confirm.isHittable { break }; app.swipeUp() }
        confirm.tap()
        XCTAssertTrue(app.staticTexts["transferSuccess"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["transferSuccess"].label.contains("2 room groups"))
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["roomMenu"].value as? String, "Receiver Room")
        app.buttons["roomMenu"].tap(); app.buttons["Family Room"].tap()
        XCTAssertTrue(app.otherElements["appleRemoteConnection"].label.contains("Family Apple TV"))
        let samsung = app.buttons["samsungRemoteConnection"]
        XCTAssertTrue(samsung.label.contains("Family Samsung"))
        app.terminate(); app.launchArguments = ["--ui-testing-wake-save-relaunch"]; app.launch()
        XCTAssertTrue(app.buttons["roomMenu"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["roomMenu"].value as? String, "Family Room")
        XCTAssertTrue(app.buttons["samsungRemoteConnection"].label.contains("Family Samsung"))
        app.buttons["roomMenu"].tap()
        XCTAssertTrue(app.buttons["Receiver Room"].exists)
        XCTAssertTrue(app.buttons["Living Room"].exists)
    }

    @MainActor
    func testDeleteLastRoomKeepsSavedTVsAfterColdRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-apps"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["manageRooms"].tap()
        // Delete stays hidden until Edit so row taps read as opening the room.
        XCTAssertFalse(app.buttons["deleteRoom.ui-apps-room"].exists)
        app.buttons["editRooms"].tap()
        app.buttons["deleteRoom.ui-apps-room"].tap(); app.buttons["Delete room"].tap()
        _ = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["deleteRoom.ui-apps-room"])
        waitForExpectations(timeout: 3)
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["roomMenu"].value as? String, "No room")
        app.terminate(); app.launchArguments = ["--ui-testing-wake-save-relaunch"]; app.launch()
        XCTAssertTrue(app.buttons["roomMenu"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["roomMenu"].value as? String, "No room")
        app.buttons["remoteSettings"].tap(); app.buttons["manageDevices"].tap()
        app.buttons["savedTVsDisclosure"].tap()
        XCTAssertTrue(app.buttons["manageTV.apple:ui-apps-living"].exists)
        XCTAssertTrue(app.buttons["manageTV.apple:ui-apps-family"].exists)
    }

    @MainActor
    func testManageTVDraftSurvivesBackgroundAndClearWaitsForSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-wake-save"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["manageDevices"].tap()
        app.buttons["savedTVsDisclosure"].tap(); app.buttons["manageTV.ui-wake-tv"].tap()
        XCTAssertEqual(app.staticTexts["manageTVHeading"].label, "Living Room TV (Samsung)")
        let ip = app.textFields["manageTVIP"], mac = app.textFields["samsungWakeMAC"]
        let name = app.textFields["manageTVName"]
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14)); name.typeText("Den Samsung")
        app.buttons["clearManageTVIP"].tap(); ip.tap(); ip.typeText("192.168.1.57")
        mac.tap(); mac.typeText("02:11:22:33:44:99")
        backgroundAndReturn(app)
        XCTAssertTrue(app.navigationBars["Manage TV"].waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Den Samsung")
        XCTAssertEqual(ip.value as? String, "192.168.1.57")
        XCTAssertEqual(mac.value as? String, "02:11:22:33:44:99")
        XCTAssertFalse(app.buttons["Remove saved MAC"].exists)
        let save = app.buttons["saveSamsungWakeMAC"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.navigationBars["Your TVs"].waitForExistence(timeout: 3))
        app.buttons["manageTV.ui-wake-tv"].tap()
        XCTAssertEqual(app.staticTexts["manageTVHeading"].label, "Den Samsung (Samsung)")
        app.buttons["clearManageTVMAC"].tap()
        tapBack(in: app.navigationBars["Manage TV"], parent: "Your TVs")
        app.buttons["manageTV.ui-wake-tv"].tap()
        XCTAssertEqual(mac.value as? String, "02:11:22:33:44:99", "Leaving without Save discards the clear")
        app.buttons["clearManageTVMAC"].tap()
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.navigationBars["Your TVs"].waitForExistence(timeout: 3))
        app.terminate(); app.launchArguments = ["--ui-testing-wake-save-relaunch"]; app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["manageDevices"].tap()
        app.buttons["savedTVsDisclosure"].tap(); app.buttons["manageTV.ui-wake-tv"].tap()
        XCTAssertEqual(name.value as? String, "Den Samsung")
        XCTAssertEqual(ip.value as? String, "192.168.1.57")
        XCTAssertEqual(mac.value as? String, "TV MAC address")
        XCTAssertFalse(app.buttons["clearManageTVMAC"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Manage TV name, type, inline address controls and bottom Save"
        screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testManageTVSavesIPAndMACTogetherAndUsesBothWithoutRestart() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-wake-save", "--ui-testing-scan-manual"]
        app.launch()
        XCTAssertTrue(app.buttons["Power"].waitForExistence(timeout: 10))
        app.buttons["Power"].tap(); app.buttons["samsungWakeSetup"].tap()
        XCTAssertTrue(app.navigationBars["Manage TV"].waitForExistence(timeout: 3))
        let ip = app.textFields["manageTVIP"], mac = app.textFields["samsungWakeMAC"]
        XCTAssertEqual(ip.value as? String, "192.168.1.50")
        ip.tap(); ip.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12)); ip.typeText("192.168.1.55")
        XCTAssertEqual(ip.value as? String, "192.168.1.55")
        mac.tap(); mac.typeText("02:11:22:33:44:88")
        app.buttons["scanManageTVIP"].tap()
        XCTAssertTrue(app.buttons["Enter addresses manually"].waitForExistence(timeout: 3))
        app.buttons["Enter addresses manually"].tap()
        let scannedIP = app.textFields["scanTVIP"], scannedMAC = app.textFields["scanTVMAC"]
        XCTAssertEqual(scannedIP.value as? String, "192.168.1.55")
        scannedIP.tap(); scannedIP.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12)); scannedIP.typeText("192.168.1.56")
        scannedMAC.tap(); scannedMAC.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 17)); scannedMAC.typeText("02:11:22:33:44:89")
        backgroundAndReturn(app)
        XCTAssertTrue(app.navigationBars["Scan TV text"].waitForExistence(timeout: 5))
        XCTAssertEqual(scannedIP.value as? String, "192.168.1.56")
        XCTAssertEqual(scannedMAC.value as? String, "02:11:22:33:44:89")
        app.buttons["scanTVApply"].tap(); app.buttons["saveSamsungWakeMAC"].tap()
        app.buttons["wakeSamsung"].tap()
        let expected = "1 · ui-wake-tv · 192.168.1.56 · 02:11:22:33:44:89 · 102 bytes"
        _ = expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: app.staticTexts["wakeTargetDebug"])
        waitForExpectations(timeout: 3)
        app.terminate(); app.launchArguments = ["--ui-testing-wake-save-relaunch"]; app.launch()
        XCTAssertTrue(app.buttons["Power"].waitForExistence(timeout: 10))
        app.buttons["Power"].tap(); app.buttons["samsungWakeSetup"].tap()
        XCTAssertTrue(ip.waitForExistence(timeout: 3))
        XCTAssertEqual(ip.value as? String, "192.168.1.56")
        XCTAssertEqual(mac.value as? String, "02:11:22:33:44:89")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Manage TV retains saved IP and MAC"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testSharedStarsAndRemoteAppearanceAreReviewedImportedAndReexportedAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-transfer-appearance"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["transferSetup"].tap()
        XCTAssertTrue(app.secureTextFields["importTransferCode"].waitForExistence(timeout: 5))
        app.secureTextFields["importTransferCode"].tap(); app.secureTextFields["importTransferCode"].typeText("cable lunar velvet walnut")
        app.buttons["unlockSetup"].tap()
        XCTAssertTrue(app.buttons["importStarredApps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["independentApplePairing"].exists)
        XCTAssertFalse(app.buttons["importTVAccess"].exists)
        XCTAssertEqual(app.buttons["importStarredApps"].value as? String, "Selected")
        if !app.buttons["importRemotePreferences"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["importRemotePreferences"].exists)
        XCTAssertTrue(app.staticTexts["Expanded Apple TV remote · Touchpad"].exists)
        if !app.buttons["confirmSetupImport"].isHittable { app.swipeUp() }
        app.buttons["confirmSetupImport"].tap()
        let success = app.staticTexts["transferSuccess"]
        XCTAssertTrue(success.waitForExistence(timeout: 5))
        XCTAssertTrue(success.label.contains("Copied starred apps for 1 Apple TV"))
        XCTAssertTrue(success.label.contains("Remote layout and pad copied"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.otherElements["remoteTouchpad"].waitForExistence(timeout: 3))
        assertAppleTVRemoteGeometry(in: app, expanded: true)
        app.terminate(); app.launchArguments = ["--ui-testing-wake-save-relaunch"]; app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["transferSetup"].tap()
        XCTAssertTrue(app.buttons["shareStarredApps"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["shareStarredApps"].value as? String, "Selected")
        XCTAssertFalse(app.buttons["shareTVAccess"].exists)
        if !app.buttons["prepareTransfer"].isHittable { app.swipeUp() }
        app.buttons["prepareTransfer"].tap()
        XCTAssertTrue(app.staticTexts["2 starred apps included"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["exportSummary"].label, "1 TV")
        XCTAssertTrue(app.staticTexts["Expanded Apple TV remote · Touchpad"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Shared stars and appearance survive relaunch and reexport"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testSavedAndScannedWakeMACIsUsedImmediatelyAndSurvivesRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-wake-save", "--ui-testing-scan-manual"]
        app.launch()
        XCTAssertTrue(app.buttons["Power"].waitForExistence(timeout: 10))
        app.buttons["Power"].tap()
        app.buttons["wakeSamsung"].tap()
        let mac = app.textFields["samsungWakeMAC"]
        XCTAssertTrue(mac.waitForExistence(timeout: 3))
        mac.tap(); mac.typeText("02-11-22-33-44-66")
        app.buttons["saveSamsungWakeMAC"].tap()
        XCTAssertTrue(app.buttons["wakeSamsung"].waitForExistence(timeout: 3))
        app.buttons["wakeSamsung"].tap()
        assertWakeTarget(in: app, count: 1, mac: "02:11:22:33:44:66")

        app.buttons["samsungWakeSetup"].tap()
        XCTAssertTrue(mac.waitForExistence(timeout: 3))
        XCTAssertEqual(mac.value as? String, "02:11:22:33:44:66")
        app.buttons["scanSamsungWakeMAC"].tap()
        XCTAssertTrue(app.buttons["Enter addresses manually"].waitForExistence(timeout: 3))
        app.buttons["Enter addresses manually"].tap()
        let scanned = app.textFields["scanTVMAC"]
        XCTAssertEqual(scanned.value as? String, "02:11:22:33:44:66")
        scanned.tap(); scanned.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 17))
        scanned.typeText("02:11:22:33:44:88")
        app.buttons["scanTVApply"].tap()
        XCTAssertTrue(mac.waitForExistence(timeout: 3))
        XCTAssertEqual(mac.value as? String, "02:11:22:33:44:88")
        app.buttons["saveSamsungWakeMAC"].tap()
        app.buttons["wakeSamsung"].tap()
        assertWakeTarget(in: app, count: 2, mac: "02:11:22:33:44:88")

        // Re-saving the same value is a real save and does not strand On.
        app.buttons["samsungWakeSetup"].tap()
        XCTAssertEqual(mac.value as? String, "02:11:22:33:44:88")
        app.buttons["saveSamsungWakeMAC"].tap()
        app.buttons["wakeSamsung"].tap()
        assertWakeTarget(in: app, count: 3, mac: "02:11:22:33:44:88")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "On uses the newly saved MAC without app restart"
        screenshot.lifetime = .keepAlways; add(screenshot)

        app.terminate()
        app.launchArguments = ["--ui-testing-wake-save-relaunch"]
        app.launch()
        XCTAssertTrue(app.buttons["Power"].waitForExistence(timeout: 10))
        app.buttons["Power"].tap(); app.buttons["wakeSamsung"].tap()
        assertWakeTarget(in: app, count: 1, mac: "02:11:22:33:44:88")
        app.buttons["Done"].tap()
        app.buttons["roomMenu"].tap(); app.buttons["Family Room"].tap()
        app.buttons["Power"].tap(); app.buttons["samsungWakeSetup"].tap()
        XCTAssertTrue(mac.waitForExistence(timeout: 3))
        XCTAssertEqual(mac.value as? String, "02:AA:BB:CC:DD:EE")
        // Other TVs/rooms are preserved. All wake transport is a DEBUG recorder.
    }

    @MainActor
    func testBlankMACSaveKeepsExistingValueAndRemovalRequiresExplicitAction() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-wake-save"]
        app.launch()
        XCTAssertTrue(app.buttons["roomMenu"].waitForExistence(timeout: 10))
        app.buttons["roomMenu"].tap(); app.buttons["Family Room"].tap()
        app.buttons["Power"].tap(); app.buttons["samsungWakeSetup"].tap()
        let mac = app.textFields["samsungWakeMAC"]
        XCTAssertTrue(mac.waitForExistence(timeout: 3))
        XCTAssertEqual(mac.value as? String, "02:AA:BB:CC:DD:EE")
        mac.tap(); mac.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 17))
        app.buttons["saveSamsungWakeMAC"].tap()
        XCTAssertTrue(app.staticTexts["samsungWakeSaveError"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Manage TV"].exists)
        tapBack(in: app.navigationBars["Manage TV"], parent: "Power")
        app.buttons["samsungWakeSetup"].tap()
        XCTAssertEqual(mac.value as? String, "02:AA:BB:CC:DD:EE")
        app.buttons["Remove saved MAC"].tap()
        app.buttons["wakeSamsung"].tap()
        XCTAssertTrue(mac.waitForExistence(timeout: 3))
        XCTAssertTrue(["", "TV MAC address"].contains(mac.value as? String ?? ""))
        XCTAssertFalse(app.buttons["Remove saved MAC"].exists)
    }

    @MainActor
    private func assertWakeTarget(in app: XCUIApplication, count: Int, mac: String) {
        let output = app.staticTexts["wakeTargetDebug"]
        let expected = "\(count) · ui-wake-tv · 192.168.1.50 · \(mac) · 102 bytes"
        _ = expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: output)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["wakeSamsung"].isEnabled)
        XCTAssertFalse(app.navigationBars["Manage TV"].exists)
    }

    @MainActor
    func testTransferShareCanExcludeRoomsAndSavedAccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-transfer-review"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap()
        app.buttons["transferSetup"].tap()
        XCTAssertTrue(app.buttons["unlockSetup"].waitForExistence(timeout: 5))
        app.buttons["Share"].tap()
        XCTAssertTrue(app.buttons["shareRoomGroups"].exists)
        XCTAssertFalse(app.buttons["shareTVAccess"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Compact share selection with independent room and access choices"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["prepareTransfer"].tap()
        let summary = app.staticTexts["exportSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "1 TV")
        XCTAssertTrue(app.buttons["shareSetupFile"].exists)
        // No share-sheet send, authentication, TV connection or credential export.
        app.buttons["Done"].tap()
    }

    @MainActor
    func testTransferReviewKeepsLocalRoomsAndImportsOnlyChosenTVs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-transfer-review"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap(); app.buttons["transferSetup"].tap()
        let code = app.secureTextFields["importTransferCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap(); code.typeText("cable lunar velvet walnut")
        app.buttons["unlockSetup"].tap()
        let summary = app.staticTexts["importSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "1 new TV")
        XCTAssertTrue(app.staticTexts["Saved here as My Living TV · Access kept"].exists)
        let localTV = app.buttons["importTV.review-existing"]
        localTV.tap()
        XCTAssertFalse(app.buttons["importRoom.review-living"].exists)
        XCTAssertFalse(app.staticTexts["Added as Living Room (shared)"].exists)
        XCTAssertFalse(app.buttons["importTVAccess"].exists)
        let confirm = app.buttons["confirmSetupImport"]
        if !confirm.isHittable { app.swipeUp() }
        confirm.tap()
        XCTAssertTrue(app.staticTexts["transferSuccess"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["transferSuccess"].label.hasPrefix("Added 1 TV."))
        XCTAssertFalse(app.buttons["chooseSetupFile"].exists)
        app.buttons["Done"].tap()
        app.buttons["remoteSettings"].tap(); app.buttons["manageRooms"].tap()
        XCTAssertTrue(app.staticTexts["Living Room"].exists)
        XCTAssertTrue(app.staticTexts["My Living TV"].exists)
        XCTAssertFalse(app.staticTexts["Family Room"].exists)
        XCTAssertFalse(app.staticTexts["Living Room (shared)"].exists)
        // Shared access was declined; fixture credentials never enter Keychain.
    }

    @MainActor
    func testAutoIsHiddenAndSavedAutoFallsBackToNamedRoom() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-home", "--ui-testing-saved-auto"]
        app.launch()
        let room = app.buttons["roomMenu"]
        let apple = app.descendants(matching: .any)["appleRemoteConnection"].firstMatch
        let samsung = app.descendants(matching: .any)["samsungRemoteConnection"].firstMatch
        for launch in 0..<2 {
            XCTAssertTrue(room.waitForExistence(timeout: 10))
            XCTAssertEqual(room.value as? String, "Living Room")
            room.tap()
            let living = app.buttons["Living Room"]
            XCTAssertTrue(living.waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["Auto"].exists)
            living.tap()
            XCTAssertEqual(room.value as? String, "Living Room")
            XCTAssertEqual(apple.value as? String, "Connected")
            XCTAssertEqual(samsung.value as? String, "Connected")
            if launch == 0 {
                app.terminate()
                app.launchArguments = ["--ui-testing-home"]
                app.launch()
            }
        }
    }

    @MainActor
    func testStatusPollReflectsObservedLossWithoutReconnectingOtherTV() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-status-refresh"]
        app.launch()
        let loss = app.buttons["simulateStatusLoss"]
        XCTAssertTrue(loss.waitForExistence(timeout: 10))
        let apple = app.descendants(matching: .any)["appleRemoteConnection"].firstMatch
        let samsung = app.descendants(matching: .any)["samsungRemoteConnection"].firstMatch
        XCTAssertEqual(apple.value as? String, "Connected")
        XCTAssertEqual(samsung.value as? String, "Connected")
        loss.tap()
        _ = expectation(for: NSPredicate(format: "value == %@", "Not connected"), evaluatedWith: apple)
        waitForExpectations(timeout: 4)
        XCTAssertEqual(samsung.value as? String, "Connected")
        XCTAssertTrue(app.buttons["appleRemoteConnection"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Periodic poll downgrades Apple dot while Samsung stays connected"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testBackgroundReturnPreservesBothConnectedIndicatorsAndHomeControl() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-home"]
        app.launch()
        let home = app.buttons["remoteHome"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        let apple = app.descendants(matching: .any)["appleRemoteConnection"].firstMatch
        let samsung = app.descendants(matching: .any)["samsungRemoteConnection"].firstMatch
        XCTAssertEqual(apple.value as? String, "Connected")
        XCTAssertEqual(samsung.value as? String, "Connected")
        home.tap()
        _ = expectation(for: NSPredicate(format: "label == %@", "home"), evaluatedWith: app.staticTexts["homeActionLog"])
        waitForExpectations(timeout: 3)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 2) ||
                      app.wait(for: .runningBackgroundSuspended, timeout: 2))
        app.activate()
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertEqual(apple.value as? String, "Connected")
        XCTAssertEqual(samsung.value as? String, "Connected")
        XCTAssertTrue(home.isEnabled)
        home.tap()
        _ = expectation(for: NSPredicate(format: "label == %@", "home,home"), evaluatedWith: app.staticTexts["homeActionLog"])
        waitForExpectations(timeout: 3)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Both connections retained after background and return"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testHomeSingleDoubleAndHoldDoNotSendExtraSingleTaps() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-home"]
        app.launch()
        let home = app.buttons["remoteHome"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        home.tap()
        _ = expectation(for: NSPredicate(format: "label == %@", "home"), evaluatedWith: app.staticTexts["homeActionLog"])
        waitForExpectations(timeout: 3)
        home.doubleTap()
        _ = expectation(for: NSPredicate(format: "label == %@", "home,appSwitcher"), evaluatedWith: app.staticTexts["homeActionLog"])
        waitForExpectations(timeout: 3)
        home.press(forDuration: 1)
        _ = expectation(for: NSPredicate(format: "label == %@", "home,appSwitcher,controlCenter"), evaluatedWith: app.staticTexts["homeActionLog"])
        waitForExpectations(timeout: 3)
        XCTAssertEqual(app.staticTexts["homeActionLog"].label, "home,appSwitcher,controlCenter")
    }

    @MainActor
    func testShortcutSuccessIsBelowBothButtonsAndCurrentAppHasBackNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-shortcut-success"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteShortcuts"].waitForExistence(timeout: 10))
        app.buttons["remoteShortcuts"].tap()
        let xfinity = app.buttons["restartXfinityStream"]
        let current = app.buttons["restartCurrentApp"]
        let result = app.staticTexts["shortcutCompleted"]
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        XCTAssertTrue(xfinity.exists)
        XCTAssertTrue(current.exists)
        XCTAssertLessThanOrEqual(xfinity.frame.maxY, current.frame.minY)
        XCTAssertGreaterThan(result.frame.minY, current.frame.maxY)
        XCTAssertFalse(app.buttons["closeAndReopenXfinity"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shortcut success diagnostics below both controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        current.tap()
        XCTAssertTrue(app.navigationBars["Current app"].waitForExistence(timeout: 3))
        tapBack(in: app.navigationBars["Current app"], parent: "Shortcuts")
        XCTAssertTrue(app.navigationBars["Shortcuts"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testPendingStatusNameTapRetriesAndSavedTVActionsHaveSpace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-connections"]
        app.launch()
        let apple = app.buttons["appleRemoteConnection"]
        let samsung = app.buttons["samsungRemoteConnection"]
        XCTAssertTrue(samsung.waitForExistence(timeout: 10))
        XCTAssertTrue(apple.exists)
        XCTAssertTrue(apple.isEnabled)
        XCTAssertTrue(samsung.isEnabled)
        XCTAssertEqual(apple.value as? String, "Connecting…")
        XCTAssertEqual(samsung.value as? String, "Allow access on the TV")
        XCTAssertFalse(app.buttons["samsungRemoteConnect"].exists)
        let pending = XCTAttachment(screenshot: app.screenshot())
        pending.name = "Tappable pending indicators with spinners"
        pending.lifetime = .keepAlways
        add(pending)
        // Tap the name at the left of the row, not the icon/dot at its right.
        samsung.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 12, dy: samsung.frame.height / 2)).tap()
        let failed = NSPredicate(format: "value CONTAINS %@", "loopback")
        _ = expectation(for: failed, evaluatedWith: samsung)
        waitForExpectations(timeout: 8)
        XCTAssertEqual(apple.value as? String, "Connecting…")
        app.buttons["remoteSettings"].tap()
        app.buttons["manageDevices"].tap()
        XCTAssertTrue(app.navigationBars["Your TVs"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Rename"].exists)
        app.buttons["savedTVsDisclosure"].tap()
        XCTAssertTrue(app.buttons["manageTV.ui-apple-status"].exists)
        XCTAssertTrue(app.buttons["manageTV.ui-samsung-status"].exists)
        let savedTVs = XCTAttachment(screenshot: app.screenshot())
        savedTVs.name = "Saved TVs with separate device cards and action rows"
        savedTVs.lifetime = .keepAlways
        add(savedTVs)
    }

    @MainActor
    func testManualScannerEntryRetainsExistingDraftAddresses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-scan-manual"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap()
        app.buttons["manageDevices"].tap(); app.buttons["addTV"].tap()
        let ip = app.textFields["TV’s local IP address"]
        XCTAssertTrue(ip.waitForExistence(timeout: 3))
        ip.tap(); ip.typeText("192.168.50.168")
        let mac = app.textFields["newSamsungWakeMAC"]
        mac.tap(); mac.typeText("02:11:22:33:44:66")
        app.buttons["scanNewSamsungTVMAC"].tap()
        XCTAssertTrue(app.buttons["Enter addresses manually"].waitForExistence(timeout: 3))
        app.buttons["Enter addresses manually"].tap()
        XCTAssertEqual(app.textFields["scanTVIP"].value as? String, "192.168.50.168")
        XCTAssertEqual(app.textFields["scanTVMAC"].value as? String, "02:11:22:33:44:66")
        app.buttons["scanTVApply"].tap()
        XCTAssertTrue(app.navigationBars["Add a TV"].waitForExistence(timeout: 3))
        XCTAssertEqual(ip.value as? String, "192.168.50.168")
        XCTAssertEqual(mac.value as? String, "02:11:22:33:44:66")
        XCTAssertTrue(app.navigationBars["Add a TV"].exists)
    }

    @MainActor
    func testLiveTextReviewChoosesAdapterAndFillsDraftWithoutPairing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-scan-text"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap()
        app.buttons["manageDevices"].tap(); app.buttons["addTV"].tap()
        let name = app.textFields["Name, e.g. Bedroom Samsung"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("Family Room Samsung")
        let scan = app.buttons["scanNewSamsungTVIP"]
        XCTAssertTrue(app.buttons["scanNewSamsungTVMAC"].exists)
        if !scan.isHittable { app.swipeUp() }
        scan.tap()
        XCTAssertTrue(app.navigationBars["Scan TV text"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["liveTVTextScanner"].exists)
        XCTAssertEqual(app.textFields["scanTVIP"].value as? String, "192.168.1.50")
        XCTAssertFalse(app.buttons["scanTVApply"].isEnabled)
        app.buttons["scanTVMACPicker"].tap()
        let wireless = app.buttons["scanTVMAC-wireless-02:11:22:33:44:66"]
        XCTAssertTrue(wireless.waitForExistence(timeout: 3))
        wireless.tap()
        XCTAssertTrue(app.buttons["scanTVApply"].isEnabled)
        app.buttons["scanTVApply"].tap()
        XCTAssertTrue(app.navigationBars["Your TVs"].waitForExistence(timeout: 3))
        XCTAssertEqual(name.value as? String, "Family Room Samsung")
        XCTAssertEqual(app.textFields["TV’s local IP address"].value as? String, "192.168.1.50")
        XCTAssertEqual(app.textFields["newSamsungWakeMAC"].value as? String, "02:11:22:33:44:66")
        XCTAssertTrue(app.navigationBars["Add a TV"].exists)
        XCTAssertFalse(app.navigationBars["Pair Samsung TV"].exists)
    }

    @MainActor
    func testExpandedLayoutIsDefaultFirstAndAlternateChoicePersists() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["remotePadModeToggle"].value as? String, "D-pad")
        XCTAssertTrue(app.otherElements["remoteDirectionPad"].exists)
        assertAppleTVRemoteGeometry(in: app, expanded: true)
        app.buttons["remoteSettings"].tap()
        let picker = app.buttons["remoteLayoutPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertEqual(picker.value as? String, "Expanded Apple TV remote")
        if !picker.isHittable { app.swipeUp() }
        picker.tap()
        let expanded = app.buttons["Expanded Apple TV remote"]
        let alternate = app.buttons["Alternate"]
        let compact = app.buttons["Apple TV remote"]
        XCTAssertTrue(expanded.waitForExistence(timeout: 3))
        XCTAssertTrue(alternate.exists)
        XCTAssertTrue(compact.exists)
        XCTAssertFalse(app.buttons["Standard"].exists)
        XCTAssertLessThan(expanded.frame.minY, alternate.frame.minY)
        XCTAssertLessThan(expanded.frame.minY, compact.frame.minY)
        compact.tap()
        app.buttons["Done"].tap()
        assertAppleTVRemoteGeometry(in: app)
        app.buttons["remotePadModeToggle"].tap()
        XCTAssertEqual(app.buttons["remotePadModeToggle"].value as? String, "Touchpad")
        XCTAssertTrue(app.otherElements["remoteTouchpad"].exists)
        XCTAssertFalse(app.otherElements["remoteDirectionPad"].exists)
        assertAppleTVRemoteGeometry(in: app)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["remotePadModeToggle"].value as? String, "Touchpad")
        XCTAssertTrue(app.otherElements["remoteTouchpad"].exists)
        assertAppleTVRemoteGeometry(in: app)

        chooseVolumeLayout("Expanded Apple TV remote", in: app)
        assertAppleTVRemoteGeometry(in: app, expanded: true)
        app.buttons["remotePadModeToggle"].tap()
        XCTAssertTrue(app.otherElements["remoteDirectionPad"].exists)
        assertAppleTVRemoteGeometry(in: app, expanded: true)
        app.buttons["remotePadModeToggle"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["remotePadModeToggle"].value as? String, "Touchpad")
        assertAppleTVRemoteGeometry(in: app, expanded: true)

        chooseVolumeLayout("Alternate", in: app)
        XCTAssertTrue(app.otherElements["remoteTouchpad"].exists)
        assertStandardVolumeGeometry(in: app)
        app.buttons["remotePadModeToggle"].tap()
        XCTAssertEqual(app.buttons["remotePadModeToggle"].value as? String, "D-pad")
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["remotePadModeToggle"].value as? String, "D-pad")
        XCTAssertTrue(app.otherElements["remoteDirectionPad"].exists)
        assertStandardVolumeGeometry(in: app)
    }

    @MainActor
    func testInvalidSamsungWakeMACDoesNotStartPairing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap()
        app.buttons["manageDevices"].tap(); app.buttons["addTV"].tap()
        let name = app.textFields["Name, e.g. Bedroom Samsung"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("Wake validation TV")
        let ip = app.textFields["TV’s local IP address"]
        ip.tap(); ip.typeText("192.168.1.50")
        let mac = app.textFields["newSamsungWakeMAC"]
        mac.tap(); mac.typeText("FF:FF:FF:FF:FF:FF")
        app.swipeUp()
        app.buttons["Add and pair Samsung TV"].tap()
        XCTAssertTrue(app.staticTexts["Enter this Samsung TV's Wi-Fi or Ethernet MAC address, for example 00:12:34:56:78:9A. Use the address for its current network connection."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Add a TV"].exists)
        XCTAssertFalse(app.staticTexts["Wake validation TV"].exists)
        XCTAssertTrue(app.navigationBars["Add a TV"].exists)
    }

    @MainActor
    func testBundledXfinityShortcutIsPresentWithoutDevices() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteShortcuts"].waitForExistence(timeout: 10))
        app.buttons["remoteShortcuts"].tap()
        XCTAssertTrue(app.navigationBars["Shortcuts"].waitForExistence(timeout: 3))
        let restart = app.buttons["restartXfinityStream"]
        XCTAssertTrue(restart.exists)
        XCTAssertFalse(restart.isEnabled)
        XCTAssertTrue(app.staticTexts["Choose an Apple TV in Settings first."].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["remoteShortcuts"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testEncryptedImportRequiresPhraseAndExplicitApproval() throws {
        assertEncryptedImportRequiresSecretAndApproval(
            argument: "--ui-testing-transfer",
            wrongSecret: "walnut velvet lunar cable",
            secret: "cable lunar velvet walnut",
            reviewName: "Shared Bedroom TV",
            importedRoom: "Living Room"
        )
    }

    @MainActor
    func testEncryptedLegacyImportRequiresCodeAndExplicitApproval() throws {
        assertEncryptedImportRequiresSecretAndApproval(
            argument: "--ui-testing-transfer-legacy",
            wrongSecret: String(repeating: "1", count: 32),
            secret: String(repeating: "0", count: 32),
            reviewName: "Living TV",
            importedRoom: "Living Room"
        )
    }

    @MainActor
    private func assertEncryptedImportRequiresSecretAndApproval(argument: String, wrongSecret: String, secret: String, reviewName: String, importedRoom: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", argument]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap()
        XCTAssertTrue(app.buttons["transferSetup"].waitForExistence(timeout: 3))
        app.buttons["transferSetup"].tap()
        XCTAssertTrue(app.buttons["unlockSetup"].waitForExistence(timeout: 10))
        let field = app.secureTextFields["importTransferCode"]
        XCTAssertEqual(field.placeholderValue, "Four-word transfer phrase")
        field.tap(); field.typeText(wrongSecret)
        app.buttons["unlockSetup"].tap()
        XCTAssertTrue(app.staticTexts["transferError"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["confirmSetupImport"].exists)
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: wrongSecret.count))
        field.typeText(secret)
        app.buttons["unlockSetup"].tap()
        XCTAssertTrue(app.buttons["confirmSetupImport"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[reviewName].exists)
        app.buttons["confirmSetupImport"].tap()
        XCTAssertTrue(app.staticTexts["transferSuccess"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        app.buttons["roomMenu"].tap()
        XCTAssertTrue(app.buttons[importedRoom].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRoomGroupsAndInvalidTVSetupWithoutNetwork() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["roomMenu"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["remoteSettings"].exists)
        let roomMenu = app.buttons["roomMenu"]
        let settings = app.buttons["remoteSettings"]
        let shortcuts = app.buttons["remoteShortcuts"]
        XCTAssertEqual(roomMenu.value as? String, "Living Room")
        XCTAssertEqual(roomMenu.frame.height, 44, accuracy: 1)
        XCTAssertEqual(roomMenu.frame.midY, settings.frame.midY, accuracy: 1)
        XCTAssertEqual(roomMenu.frame.midY, shortcuts.frame.midY, accuracy: 1)
        XCTAssertLessThanOrEqual(roomMenu.frame.maxX, settings.frame.minX)
        XCTAssertLessThanOrEqual(settings.frame.maxX, shortcuts.frame.minX)
        XCTAssertFalse(app.buttons["appleDeviceMenu"].exists)
        XCTAssertFalse(app.buttons["samsungDeviceMenu"].exists)
        let remoteAttachment = XCTAttachment(screenshot: app.screenshot())
        remoteAttachment.name = "Compact remote with room menu and settings gear"
        remoteAttachment.lifetime = .keepAlways
        add(remoteAttachment)
        app.buttons["remoteSettings"].tap()
        XCTAssertTrue(app.buttons["appleDeviceMenu"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Living Room"].exists)
        XCTAssertTrue(app.staticTexts["roomGroupTVs"].exists)
        XCTAssertEqual(app.staticTexts["roomGroupTVs"].label, "Living Room")
        XCTAssertTrue(app.buttons["appleDeviceMenu"].exists)
        XCTAssertTrue(app.buttons["samsungDeviceMenu"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["appleDeviceMenu"].exists)
        app.buttons["remoteSettings"].tap()
        app.buttons["manageRooms"].tap()
        app.buttons["Add a room"].tap()
        let name = app.textFields["Room name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Bedroom QA")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Bedroom QA"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        app.buttons["roomMenu"].tap()
        app.buttons["Bedroom QA"].tap()
        XCTAssertEqual(app.buttons["roomMenu"].value as? String, "Bedroom QA")
        app.buttons["remoteSettings"].tap()
        XCTAssertTrue(app.staticTexts["roomGroupTVs"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["roomGroupTVs"].label, "Bedroom QA")
        app.buttons["manageDevices"].tap(); app.buttons["addTV"].tap()
        let tvName = app.textFields["Name, e.g. Bedroom Samsung"]
        XCTAssertTrue(tvName.waitForExistence(timeout: 3))
        tvName.tap(); tvName.typeText("Invalid TV")
        let address = app.textFields["TV’s local IP address"]
        address.tap(); address.typeText("https://invalid")
        app.buttons["Add and pair Samsung TV"].tap()
        XCTAssertTrue(app.navigationBars["Add a TV"].exists)
        XCTAssertFalse(app.staticTexts["Invalid TV"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Native setup rejects an invalid endpoint"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSettingsSubmenusReturnWithBackButtons() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 10))
        app.buttons["remoteSettings"].tap()
        XCTAssertTrue(app.navigationBars["Living Room"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["roomGroupTVs"].exists)
        XCTAssertEqual(app.staticTexts["roomGroupTVs"].label, "Living Room")

        app.buttons["manageDevices"].tap()
        XCTAssertTrue(app.navigationBars["Your TVs"].waitForExistence(timeout: 3))
        app.swipeUp()
        app.buttons["transferSetup"].tap()
        XCTAssertTrue(app.navigationBars["Transfer setup"].waitForExistence(timeout: 3))
        tapBack(in: app.navigationBars["Transfer setup"], parent: "Your TVs")
        XCTAssertTrue(app.navigationBars["Your TVs"].waitForExistence(timeout: 3))
        tapBack(in: app.navigationBars["Your TVs"], parent: "Living Room")
        XCTAssertTrue(app.navigationBars["Living Room"].waitForExistence(timeout: 3))

        app.buttons["manageRooms"].tap()
        XCTAssertTrue(app.navigationBars["Rooms"].waitForExistence(timeout: 3))
        tapBack(in: app.navigationBars["Rooms"], parent: "Living Room")
        XCTAssertTrue(app.navigationBars["Living Room"].waitForExistence(timeout: 3))
        app.buttons["transferSetup"].tap()
        XCTAssertTrue(app.navigationBars["Transfer setup"].waitForExistence(timeout: 3))
        tapBack(in: app.navigationBars["Transfer setup"], parent: "Living Room")
        XCTAssertTrue(app.buttons["appleDeviceMenu"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func backgroundAndReturn(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 2) || app.wait(for: .runningBackgroundSuspended, timeout: 2))
        app.activate()
    }

    @MainActor
    private func chooseVolumeLayout(_ title: String, in app: XCUIApplication) {
        app.buttons["remoteSettings"].tap()
        let picker = app.buttons["remoteLayoutPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        if !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["remoteSettings"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func assertAppleTVRemoteGeometry(in app: XCUIApplication, expanded: Bool = false) {
        let up = app.buttons["remoteVolumeUp"]
        let down = app.buttons["remoteVolumeDown"]
        let mute = app.buttons["remoteMute"]
        let back = app.buttons["remoteBack"]
        let home = app.buttons["remoteHome"]
        let play = app.buttons["remotePlayPause"]
        XCTAssertTrue(up.waitForExistence(timeout: 3))
        XCTAssertTrue(down.exists)
        XCTAssertTrue(mute.exists)
        XCTAssertFalse(up.isEnabled)
        XCTAssertFalse(down.isEnabled)
        XCTAssertFalse(mute.isEnabled)
        XCTAssertTrue(back.exists)
        XCTAssertTrue(home.exists)
        XCTAssertTrue(play.exists)
        XCTAssertTrue(app.buttons["remotePower"].exists)
        XCTAssertEqual(back.frame.midY, home.frame.midY, accuracy: 1)
        XCTAssertEqual(back.frame.midX, play.frame.midX, accuracy: 1)
        XCTAssertEqual(play.frame.midX, mute.frame.midX, accuracy: 1)
        XCTAssertEqual(home.frame.midX, up.frame.midX, accuracy: 1)
        XCTAssertEqual(up.frame.midX, down.frame.midX, accuracy: 1)
        XCTAssertLessThan(mute.frame.maxX, up.frame.minX)
        XCTAssertEqual(play.frame.minY, up.frame.minY, accuracy: 1)
        XCTAssertEqual(mute.frame.maxY, down.frame.maxY, accuracy: 1)
        XCTAssertLessThan(back.frame.maxY, play.frame.minY)
        XCTAssertLessThan(play.frame.maxY, mute.frame.minY)
        XCTAssertEqual(up.frame.maxY, down.frame.minY, accuracy: 1)
        XCTAssertTrue(app.otherElements["remoteVolumeRocker"].exists)
        let touchpad = app.otherElements["remoteTouchpad"]
        let pad = touchpad.exists ? touchpad : app.otherElements["remoteDirectionPad"]
        XCTAssertTrue(pad.exists)
        XCTAssertGreaterThanOrEqual(back.frame.minY - pad.frame.maxY, 23)
        if expanded {
            XCTAssertEqual(pad.frame.height, 228, accuracy: 1)
            XCTAssertEqual(pad.frame.width, touchpad.exists ? app.frame.width - 36 : 228, accuracy: 2)
            XCTAssertEqual(back.frame.width, 76, accuracy: 1)
            XCTAssertEqual(home.frame.minX - back.frame.maxX, 36, accuracy: 1)
            XCTAssertEqual(play.frame.minY - back.frame.maxY, 24, accuracy: 1)
            XCTAssertGreaterThanOrEqual(back.frame.minY - pad.frame.maxY, 31)
        }
        for button in [back, home, play, up, down, mute] {
            XCTAssertGreaterThanOrEqual(button.frame.height, 48)
            XCTAssertGreaterThanOrEqual(button.frame.width, 48)
        }
    }

    @MainActor
    private func assertStandardVolumeGeometry(in app: XCUIApplication) {
        let down = app.buttons["remoteVolumeDown"]
        let mute = app.buttons["remoteMute"]
        let up = app.buttons["remoteVolumeUp"]
        XCTAssertTrue(down.waitForExistence(timeout: 3))
        XCTAssertTrue(mute.exists)
        XCTAssertTrue(up.exists)
        XCTAssertFalse(down.isEnabled)
        XCTAssertFalse(mute.isEnabled)
        XCTAssertFalse(up.isEnabled)
        XCTAssertEqual(down.frame.midY, mute.frame.midY, accuracy: 1)
        XCTAssertEqual(mute.frame.midY, up.frame.midY, accuracy: 1)
        XCTAssertLessThan(down.frame.maxX, mute.frame.minX)
        XCTAssertLessThan(mute.frame.maxX, up.frame.minX)
        let touchpad = app.otherElements["remoteTouchpad"]
        let pad = touchpad.exists ? touchpad : app.otherElements["remoteDirectionPad"]
        XCTAssertTrue(pad.exists)
        XCTAssertGreaterThanOrEqual(app.buttons["remoteBack"].frame.minY - pad.frame.maxY, 23)
        XCTAssertGreaterThanOrEqual(down.frame.height, 44)
        XCTAssertGreaterThanOrEqual(mute.frame.height, 44)
        XCTAssertGreaterThanOrEqual(up.frame.height, 44)
    }

    @MainActor
    private func tapBack(in bar: XCUIElement, parent: String) {
        let named = bar.buttons[parent]
        let back = named.exists ? named : bar.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
    }
}
