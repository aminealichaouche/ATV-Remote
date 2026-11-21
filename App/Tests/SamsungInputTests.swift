import XCTest
@testable import RoomRemote

final class SamsungInputTests: XCTestCase {
    private let backToStart = Array(repeating: RemoteAction.left, count: 8)

    private func rights(_ count: Int) -> [RemoteAction] { Array(repeating: .right, count: count) }

    func testEachInputOpensTheMenuReturnsToTheStartThenStepsRight() {
        // SmartThings and Connected Devices sit left of TV.
        XCTAssertEqual(SamsungInput.tv.keys, [.source] + backToStart + rights(2) + [.select])
        XCTAssertEqual(SamsungInput.hdmi1.keys, [.source] + backToStart + rights(3) + [.select])
        XCTAssertEqual(SamsungInput.hdmi2.keys, [.source] + backToStart + rights(4) + [.select])
        XCTAssertEqual(SamsungInput.hdmi4.keys, [.source] + backToStart + rights(6) + [.select])
        XCTAssertEqual(SamsungInput.allCases.map(\.title), ["TV", "HDMI 1", "HDMI 2", "HDMI 3", "HDMI 4"])
    }

    func testTheMenuHasTimeToOpenAndKeysAreSpacedOut() {
        for input in SamsungInput.allCases {
            let steps = input.steps
            XCTAssertEqual(steps[1], .pause(SamsungInput.menuOpenDelay), input.title)
            XCTAssertEqual(steps.last, .key(.select), input.title)
            // Every key but the final Enter is followed by a pause.
            for (index, step) in steps.enumerated().dropLast() {
                guard case .key = step else { continue }
                guard case .pause = steps[index + 1] else { return XCTFail("\(input.title): key \(index) has no pause after it") }
            }
        }
    }

    /// Switching should feel quick, even for the furthest input.
    func testEveryInputSwitchesInUnderTwoAndThreeQuarterSeconds() {
        for input in SamsungInput.allCases {
            let total = input.steps.reduce(Duration.zero) { sum, step in
                if case .pause(let duration) = step { sum + duration } else { sum }
            }
            XCTAssertLessThan(total, .milliseconds(2750), input.title)
        }
    }
}
