import XCTest
import SwiftATV
@testable import RoomRemote

final class RemoteCommandDeliveryTests: XCTestCase {
    private actor Attempts {
        var count = 0
        func next() -> Int { count += 1; return count }
    }

    private func timeout(_ protocolType: ATVProtocol = .companion, operation: String = "request", id: String = "_hidC") -> ATVError {
        .operationTimeout(TimeoutContext(protocol: protocolType, operation: operation, requestID: id, duration: 5))
    }

    func testLostHIDAcknowledgementRequestsRefreshWithoutReplayingPress() async throws {
        let attempts = Attempts()
        let error = timeout()
        let delivery = await RemoteCommandDelivery.perform(.select, to: .appleTV) {
            // A resend would succeed, hiding the potentially duplicated press.
            if await attempts.next() == 1 { throw error }
        }
        let count = await attempts.count
        XCTAssertEqual(count, 1)
        XCTAssertTrue(delivery.refreshAppleTVConnection)
        XCTAssertNotNil(delivery.error)
    }

    func testSuccessfulPressIsSentOnceAndDoesNotRefresh() async {
        let attempts = Attempts()
        let delivery = await RemoteCommandDelivery.perform(.up, to: .appleTV) { _ = await attempts.next() }
        let count = await attempts.count
        XCTAssertEqual(count, 1)
        XCTAssertNil(delivery.error)
        XCTAssertFalse(delivery.refreshAppleTVConnection)
    }

    func testSleepAndPowerOffDoNotReconnectOrResend() async {
        let error = timeout()
        for action in [RemoteAction.sleep, .powerOff] {
            let attempts = Attempts()
            let delivery = await RemoteCommandDelivery.perform(action, to: .appleTV) {
                _ = await attempts.next(); throw error
            }
            let count = await attempts.count
            XCTAssertEqual(count, 1)
            XCTAssertNotNil(delivery.error)
            XCTAssertFalse(delivery.refreshAppleTVConnection)
        }
    }

    func testWakeAcknowledgementTimeoutCanRefreshButNeverRepeatsWake() async {
        let attempts = Attempts()
        let error = timeout()
        let delivery = await RemoteCommandDelivery.perform(.wake, to: .appleTV) {
            _ = await attempts.next(); throw error
        }
        let count = await attempts.count
        XCTAssertEqual(count, 1)
        XCTAssertTrue(delivery.refreshAppleTVConnection)
    }

    func testUnrelatedProtocolAndRequestTimeoutsDoNotRefresh() async {
        for error in [timeout(.mrp), timeout(id: "_touchStart"), timeout(id: "FetchLaunchableApplicationsEvent"), timeout(operation: "connect")] {
            let delivery = await RemoteCommandDelivery.perform(.home, to: .appleTV) { throw error }
            XCTAssertNotNil(delivery.error)
            XCTAssertFalse(delivery.refreshAppleTVConnection)
        }
    }

    func testSamsungErrorCannotReconnectAppleTV() async {
        let error = timeout()
        let delivery = await RemoteCommandDelivery.perform(.volumeUp, to: .samsung) { throw error }
        XCTAssertNotNil(delivery.error)
        XCTAssertFalse(delivery.refreshAppleTVConnection)
    }

    func testCancellationIsPreservedAndNeverTriggersRecovery() async {
        let delivery = await RemoteCommandDelivery.perform(.back, to: .appleTV) { throw CancellationError() }
        XCTAssertTrue(delivery.error is CancellationError)
        XCTAssertFalse(delivery.refreshAppleTVConnection)
    }

    func testRestartStageKeepsHIDTimeoutRecoveryWithoutReplayingShortcut() {
        let switcherError = AppRestartFailure(stage: .switcher, underlying: timeout())
        XCTAssertTrue(RemoteCommandDelivery.shouldRefresh(after: switcherError, action: .home, to: .appleTV))
        XCTAssertTrue(switcherError.localizedDescription.hasPrefix("Open app switcher failed:"))
        let launchError = AppRestartFailure(stage: .reopening, underlying: timeout(id: "_launchApp"))
        XCTAssertFalse(RemoteCommandDelivery.shouldRefresh(after: launchError, action: .home, to: .appleTV))
        XCTAssertTrue(launchError.localizedDescription.hasPrefix("Reopen app failed:"))
    }
}
