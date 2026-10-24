import XCTest
@testable import RoomRemote

final class AutoRoomTests: XCTestCase {
    private func registry() -> DeviceRegistry {
        var result = DeviceRegistry()
        result.devices = [
            RemoteDevice(id: "living-apple", kind: .appleTV, name: "Living Apple", address: "192.168.1.10"),
            RemoteDevice(id: "family-samsung", kind: .samsung, name: "Family TV", address: "192.168.1.20"),
            RemoteDevice(id: "unassigned", kind: .samsung, name: "Unassigned", address: "192.168.1.30")
        ]
        result.rooms = [RoomProfile(id: "living", name: "Living Room", appleID: "living-apple"),
                        RoomProfile(id: "family", name: "Family Room", samsungID: "family-samsung")]
        return result
    }

    func testCandidatesUseOnlySavedRoomSlotsAndPreserveRegistry() {
        let original = registry()
        let candidates = AutoRoomPolicy.candidates(registry: original, preferredRoomID: "family", intent: ConnectionIntent())
        XCTAssertEqual(candidates.map(\.device.id), ["family-samsung", "living-apple"])
        XCTAssertEqual(original, registry())
        XCTAssertFalse(candidates.contains { $0.device.id == "unassigned" })
    }

    func testManualDisconnectExcludesOnlyThatTVFromAutomaticTrials() {
        var intent = ConnectionIntent()
        intent.disconnect("living-apple")
        let candidates = AutoRoomPolicy.candidates(registry: registry(), preferredRoomID: "living", intent: intent)
        XCTAssertEqual(candidates.map(\.device.id), ["family-samsung"])
    }

    func testSharedTVHasOneTrialAndPrefersTheCurrentMatchingRoom() {
        var registry = registry()
        registry.rooms[1].appleID = "living-apple"
        let candidates = AutoRoomPolicy.candidates(registry: registry, preferredRoomID: "family", intent: ConnectionIntent())
        let shared = candidates.filter { $0.device.id == "living-apple" }
        XCTAssertEqual(shared.count, 1)
        XCTAssertEqual(shared[0].roomIDs, ["family", "living"])
        XCTAssertEqual(AutoRoomPolicy.connectedRoom(candidates: candidates, deviceIDs: ["living-apple"]), "family")
    }

    func testInvalidReferencesAndEmptyRoomsDoNotCreateTrials() {
        var registry = registry()
        registry.rooms = [RoomProfile(id: "empty", name: "Empty"),
                          RoomProfile(id: "wrong-kind", name: "Wrong", appleID: "family-samsung"),
                          RoomProfile(id: "missing", name: "Missing", samsungID: "missing")]
        XCTAssertTrue(AutoRoomPolicy.candidates(registry: registry, preferredRoomID: "empty", intent: ConnectionIntent()).isEmpty)
    }

    func testExistingConnectionResolvesItsRoomButUnknownConnectionDoesNot() {
        let candidates = AutoRoomPolicy.candidates(registry: registry(), preferredRoomID: "living", intent: ConnectionIntent())
        XCTAssertEqual(AutoRoomPolicy.connectedRoom(candidates: candidates, deviceIDs: ["family-samsung"]), "family")
        XCTAssertNil(AutoRoomPolicy.connectedRoom(candidates: candidates, deviceIDs: ["unassigned", "missing"]))
    }

    func testPollingDowngradesStaleGreenWithoutOverwritingErrorsOrInventingAuthentication() {
        XCTAssertEqual(AutoRoomPolicy.refreshedState(.connected, transportConnected: false), .disconnected)
        XCTAssertEqual(AutoRoomPolicy.refreshedState(.connected, transportConnected: true), .connected)
        let states: [DeviceConnectionState] = [.disconnected, .connecting, .awaitingApproval, .awaitingPin,
                                               .trustRequired(fingerprint: "fixture"), .failed("peer rejected")]
        for state in states {
            XCTAssertEqual(AutoRoomPolicy.refreshedState(state, transportConnected: false), state)
            XCTAssertEqual(AutoRoomPolicy.refreshedState(state, transportConnected: true), state)
        }
    }

    func testFirstSuccessWinsAndLateSuccessfulLosersAreClosed() async throws {
        let fixture = AutoTrialFixture()
        let task = Task { await AutoRoomRace.firstSuccess(targets: [0, 1, 2],
            probe: { await fixture.probe($0) }, discard: { await fixture.discard($0) }) }
        try await fixture.waitForStarts(3)
        await fixture.complete(1, connection: 101)
        try await fixture.waitForCancellations(2)
        await fixture.complete(0, connection: 100)
        await fixture.complete(2, connection: 102)
        let winner = await task.value
        XCTAssertEqual(winner?.target, 1)
        XCTAssertEqual(winner?.connection, 101)
        let discarded = await fixture.discarded.sorted()
        XCTAssertEqual(discarded, [100, 102])
    }

    func testBoundedRaceFillsVacancyAfterFailureAndStopsSchedulingAfterWinner() async throws {
        let fixture = AutoTrialFixture()
        let task = Task { await AutoRoomRace.firstSuccess(targets: [0, 1, 2, 3, 4], maximumConcurrent: 2,
            probe: { await fixture.probe($0) }, discard: { await fixture.discard($0) }) }
        try await fixture.waitForStarts(2)
        await fixture.complete(0, connection: nil)
        try await fixture.waitForStarts(3)
        await fixture.complete(2, connection: 102)
        try await fixture.waitForCancellations(1)
        await fixture.complete(1, connection: nil)
        let winner = await task.value
        XCTAssertEqual(winner?.target, 2)
        let started = await fixture.started.sorted()
        let peak = await fixture.peakActive
        XCTAssertEqual(started, [0, 1, 2])
        XCTAssertLessThanOrEqual(peak, 2)
    }

    func testCanceledRaceClosesLateConnectionsAndNeverReturnsWinner() async throws {
        let fixture = AutoTrialFixture()
        let task = Task { await AutoRoomRace.firstSuccess(targets: [0, 1],
            probe: { await fixture.probe($0) }, discard: { await fixture.discard($0) }) }
        try await fixture.waitForStarts(2)
        task.cancel()
        try await fixture.waitForCancellations(2)
        await fixture.complete(0, connection: 100)
        await fixture.complete(1, connection: 101)
        let winner = await task.value
        XCTAssertNil(winner)
        let discarded = await fixture.discarded.sorted()
        XCTAssertEqual(discarded, [100, 101])
    }

    func testEveryFailedCandidateIsTriedWithoutFabricatingWinner() async {
        let counter = AutoTrialCounter()
        let result = await AutoRoomRace.firstSuccess(targets: Array(0..<9), maximumConcurrent: 2,
            probe: { await counter.fail($0) }, discard: { _ in XCTFail("No connection exists to discard") })
        XCTAssertNil(result)
        let started = await counter.started.sorted()
        XCTAssertEqual(started, Array(0..<9))
    }

    func testEmptyRaceStartsNoTrial() async {
        let counter = AutoTrialCounter()
        let result = await AutoRoomRace.firstSuccess(targets: [Int](),
            probe: { await counter.fail($0) }, discard: { _ in XCTFail("No connection exists") })
        XCTAssertNil(result)
        let started = await counter.started
        XCTAssertTrue(started.isEmpty)
    }

    func testAlreadyCancelledTaskStartsNoTrial() async {
        let counter = AutoTrialCounter()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await AutoRoomRace.firstSuccess(targets: [0, 1],
                probe: { await counter.fail($0) }, discard: { _ in XCTFail("No connection exists") })
        }
        let result = await task.value
        XCTAssertNil(result)
        let started = await counter.started
        XCTAssertTrue(started.isEmpty)
    }

    func testUnselectedDriversCannotClaimAnEstablishedConnectionOrInstallObserver() async {
        let vault = KeychainVault()
        let drivers: [any RemoteDriver] = [AppleTVDriver(vault: vault), SamsungDriver(vault: vault)]
        for driver in drivers {
            let connected = await driver.connectionIsConnected(toDeviceID: "not-selected")
            let observed = await driver.observeEstablishedConnection(toDeviceID: "not-selected", onState: { _ in XCTFail("No session exists") })
            let verified = await driver.verifyConnection(toDeviceID: "not-selected")
            XCTAssertFalse(connected)
            XCTAssertFalse(observed)
            XCTAssertFalse(verified)
        }
    }
}

private actor AutoTrialCounter {
    var started: [Int] = []
    func fail(_ target: Int) -> Int? { started.append(target); return nil }
}

/// Deliberately ignores cancellation until the test releases each trial. This
/// exercises late success disposal, rather than relying on cooperative mocks.
private actor AutoTrialFixture {
    struct TimedOut: Error { }
    var started: [Int] = []
    var discarded: [Int] = []
    var peakActive = 0
    private var active = 0
    private var canceled = Set<Int>()
    private var waiters: [Int: CheckedContinuation<Int?, Never>] = [:]

    func probe(_ target: Int) async -> Int? {
        await withTaskCancellationHandler {
            let result: Int? = await withCheckedContinuation { continuation in
                started.append(target)
                active += 1
                peakActive = max(peakActive, active)
                waiters[target] = continuation
            }
            active -= 1
            return result
        } onCancel: { Task { await self.markCanceled(target) } }
    }
    private func markCanceled(_ target: Int) { canceled.insert(target) }
    func complete(_ target: Int, connection: Int?) { waiters.removeValue(forKey: target)?.resume(returning: connection) }
    func discard(_ connection: Int) { discarded.append(connection) }
    func waitForStarts(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while started.count < count {
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            await Task.yield()
        }
    }
    func waitForCancellations(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while canceled.count < count {
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            await Task.yield()
        }
    }
}
