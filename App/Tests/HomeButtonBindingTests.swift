import XCTest
@testable import RoomRemote

final class HomeButtonBindingTests: XCTestCase {
    func testAppleHomeGesturesMapToDistinctActions() {
        let binding = HomeButtonBinding(kind: .appleTV, deviceID: "apple", epoch: 1)
        XCTAssertEqual(binding.action(for: .singleTap), .home)
        XCTAssertEqual(binding.action(for: .doubleTap), .appSwitcher)
        XCTAssertEqual(binding.action(for: .hold), .controlCenter)
    }

    func testSamsungKeepsSingleHomeWithoutAppleGestures() {
        let binding = HomeButtonBinding(kind: .samsung, deviceID: "samsung", epoch: 1)
        XCTAssertEqual(binding.action(for: .singleTap), .home)
        XCTAssertNil(binding.action(for: .doubleTap))
        XCTAssertNil(binding.action(for: .hold))
    }

    func testDelayedInputCannotMatchAnotherTVNavigationTargetOrNewSession() {
        let captured = HomeButtonBinding(kind: .appleTV, deviceID: "apple", epoch: 1)
        XCTAssertNotEqual(captured, HomeButtonBinding(kind: .appleTV, deviceID: "other", epoch: 1))
        XCTAssertNotEqual(captured, HomeButtonBinding(kind: .samsung, deviceID: "apple", epoch: 1))
        XCTAssertNotEqual(captured, HomeButtonBinding(kind: .appleTV, deviceID: "apple", epoch: 2))
    }
}
