import XCTest
@testable import RoomRemote

final class PowerConnectionRefreshTests: XCTestCase {
    func testOnlyOffAttemptsScheduleAReadNotWakeOrOrdinaryPresses() {
        for kind in DeviceKind.allCases {
            for action in RemoteAction.allCases {
                let expected = kind == .appleTV ? action == .sleep || action == .powerOff : action == .powerToggle
                XCTAssertEqual(PowerConnectionRefresh.shouldCheck(action, to: kind), expected, "\(kind) \(action)")
            }
        }
    }

    @MainActor
    func testObservedLossDowngradesOnlyTheTarget() async {
        var states: [DeviceKind: DeviceConnectionState] = [.appleTV: .connected, .samsung: .connected]
        var reads = 0
        await PowerConnectionRefresh.run(wait: { _ in }, isCurrent: { true }, observe: {
            reads += 1
            return false
        }, update: { connected in
            states[.samsung] = AutoRoomPolicy.refreshedState(states[.samsung]!, transportConnected: connected)
        })
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(states[.samsung], .disconnected)
        XCTAssertEqual(states[.appleTV], .connected)
    }

    @MainActor
    func testStandbySessionThatRemainsAliveStaysGreen() async {
        var state = DeviceConnectionState.connected
        await PowerConnectionRefresh.run(wait: { _ in }, isCurrent: { true }, observe: { true }, update: {
            state = AutoRoomPolicy.refreshedState(state, transportConnected: $0)
        })
        XCTAssertEqual(state, .connected)
    }

    @MainActor
    func testDriverErrorIsNotErasedByTheDelayedObservation() async {
        var state = DeviceConnectionState.failed("Power delivery uncertain")
        await PowerConnectionRefresh.run(wait: { _ in }, isCurrent: { true }, observe: { false }, update: {
            state = AutoRoomPolicy.refreshedState(state, transportConnected: $0)
        })
        XCTAssertEqual(state, .failed("Power delivery uncertain"))
    }

    @MainActor
    func testSelectionOrSessionChangeDuringDelayPreventsReadingAndUpdating() async throws {
        let gate = PowerRefreshGate()
        var current = true
        var reads = 0
        var updates = 0
        let task = Task {
            await PowerConnectionRefresh.run(wait: { _ in await gate.wait() }, isCurrent: { current }, observe: {
                reads += 1; return false
            }, update: { _ in updates += 1 })
        }
        try await gate.waitUntilBlocked()
        current = false
        await gate.release()
        await task.value
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(updates, 0)
    }

    @MainActor
    func testOldObservationCannotDowngradeAReplacementSession() async throws {
        let gate = PowerRefreshGate()
        var current = true
        var state = DeviceConnectionState.connected
        let task = Task {
            await PowerConnectionRefresh.run(wait: { _ in }, isCurrent: { current }, observe: {
                await gate.wait(); return false
            }, update: { state = AutoRoomPolicy.refreshedState(state, transportConnected: $0) })
        }
        try await gate.waitUntilBlocked()
        current = false
        await gate.release()
        await task.value
        XCTAssertEqual(state, .connected)
    }

    @MainActor
    func testBackgroundCancellationPreventsLateObservationEvenWithUncancellableWait() async throws {
        let gate = PowerRefreshGate()
        var reads = 0
        var updates = 0
        let task = Task {
            await PowerConnectionRefresh.run(wait: { _ in await gate.wait() }, isCurrent: { true }, observe: {
                reads += 1; return false
            }, update: { _ in updates += 1 })
        }
        try await gate.waitUntilBlocked()
        task.cancel()
        await gate.release()
        await task.value
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(updates, 0)
    }

    @MainActor
    func testCancelledSleepDoesNotReadOrPublish() async {
        var reads = 0
        var updates = 0
        await PowerConnectionRefresh.run(wait: { _ in throw CancellationError() }, isCurrent: { true }, observe: {
            reads += 1; return false
        }, update: { _ in updates += 1 })
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(updates, 0)
    }
}

private actor PowerRefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
    func waitUntilBlocked() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if continuation != nil { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw RemoteFailure.message("Power-check fixture did not suspend")
    }
}
