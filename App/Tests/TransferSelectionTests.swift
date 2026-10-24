import XCTest
@testable import RoomRemote

final class TransferSelectionTests: XCTestCase {
    private var payload: RoomTransferPayload {
        let first = RemoteDevice(id: "living-tv", kind: .samsung, name: "Living TV", address: "192.168.1.20", port: 8002)
        let second = RemoteDevice(id: "family-tv", kind: .samsung, name: "Family TV", address: "192.168.1.21", port: 8002)
        return RoomTransferPayload(devices: [first, second], rooms: [
            RoomProfile(id: "living", name: "Living Room", samsungID: first.id),
            RoomProfile(id: "family", name: "Family Room", samsungID: second.id)
        ], samsungPairings: [SamsungPairingTransfer(deviceID: first.id, token: "synthetic-only-token", certificateSHA256: Data(repeating: 1, count: 32), clientName: SamsungProtocol.clientName(deviceID: first.id))])
    }

    func testTVOnlyTransferRoundTripsWithoutManufacturingARoom() throws {
        let selected = try payload.selecting(deviceIDs: ["living-tv"], roomIDs: [], includePairings: true)
        let data = try RoomTransfer.encrypt(selected, code: "cable lunar velvet walnut")
        let decoded = try RoomTransfer.decrypt(data, code: "cable lunar velvet walnut")
        XCTAssertTrue(decoded.rooms.isEmpty)
        XCTAssertEqual(decoded.devices.map(\.id), ["living-tv"])
        let existing = DeviceRegistry(rooms: [RoomProfile(id: "mine", name: "My Room")])
        let plan = try RoomTransferPlan(payload: decoded, existing: existing)
        XCTAssertEqual(plan.registry.rooms, existing.rooms)
        XCTAssertEqual(plan.addedRoomCount, 0)
        XCTAssertEqual(plan.samsungPairings.count, 1)
    }

    func testSelectiveImportFiltersCredentialsAndClearsExcludedRoomSlots() throws {
        let selected = try payload.selecting(deviceIDs: ["family-tv"], roomIDs: ["living", "family"], includePairings: true)
        XCTAssertEqual(selected.devices.map(\.id), ["family-tv"])
        XCTAssertTrue(selected.samsungPairings.isEmpty)
        XCTAssertNil(selected.rooms.first { $0.id == "living" }?.samsungID)
        XCTAssertEqual(selected.rooms.first { $0.id == "family" }?.samsungID, "family-tv")
        XCTAssertEqual(payload.rooms[0].samsungID, "living-tv")
    }

    func testReceiverCanDeclineAllSharedAccessIndependentlyOfRoomGroups() throws {
        let selected = try payload.selecting(deviceIDs: ["living-tv", "family-tv"], roomIDs: ["living"], includePairings: false)
        XCTAssertTrue(selected.samsungPairings.isEmpty)
        XCTAssertEqual(selected.rooms.map(\.id), ["living"])
        XCTAssertEqual(selected.devices.count, 2)
    }

    func testExcludedMaliciousEntriesCannotBypassValidation() {
        var invalid = payload
        invalid.devices[1].address = "8.8.8.8"
        XCTAssertThrowsError(try invalid.selecting(deviceIDs: ["living-tv"], roomIDs: ["living"], includePairings: false))
        invalid = payload
        invalid.samsungPairings[0] = SamsungPairingTransfer(deviceID: "unknown", token: "synthetic-only-token", certificateSHA256: Data(repeating: 1, count: 32), clientName: "fixture")
        XCTAssertThrowsError(try invalid.selecting(deviceIDs: ["family-tv"], roomIDs: [], includePairings: false))
    }

    func testConflictedTVIsVisibleAndCannotEnterTheDefaultSelection() throws {
        var saved = payload.devices[0]; saved.address = "192.168.1.99"
        let existing = DeviceRegistry(devices: [saved], rooms: [])
        let review = try RoomTransferReview(payload: payload, existing: existing)
        XCTAssertNotNil(review.devices[0].conflict)
        XCTAssertEqual(review.selectableDeviceIDs, ["family-tv"])
        let selected = try payload.selecting(deviceIDs: review.selectableDeviceIDs, roomIDs: ["living", "family"], includePairings: true)
        let plan = try RoomTransferPlan(payload: selected, existing: existing)
        XCTAssertEqual(plan.registry.devices.first { $0.id == saved.id }?.address, saved.address)
        XCTAssertTrue(plan.samsungPairings.isEmpty)
        XCTAssertThrowsError(try RoomTransferPlan(payload: payload, existing: existing))
    }

    func testSameAddressDifferentIdentityIsNeverMistakenForSavedAccess() throws {
        var saved = payload.devices[0]; saved.id = "different-identity"
        let review = try RoomTransferReview(payload: payload, existing: DeviceRegistry(devices: [saved], rooms: []))
        XCTAssertNil(review.devices[0].existing)
        XCTAssertNil(review.devices[0].conflict)
        XCTAssertTrue(review.devices[0].hasSharedAccess)
    }

    func testSameNameAndAssignmentsReuseLocalRoomDespiteDifferentRoomID() throws {
        var local = payload.rooms[0]; local.id = "local-room"; local.name = "living room"
        let existing = DeviceRegistry(devices: payload.devices, rooms: [local])
        var incoming = payload; incoming.rooms[0].name = " Living Room "
        let plan = try RoomTransferPlan(payload: incoming, existing: existing)
        let result = try XCTUnwrap(plan.roomResults.first { $0.incomingID == "living" })
        XCTAssertFalse(result.isAdded)
        XCTAssertEqual(result.room, local)
        XCTAssertEqual(plan.addedRoomCount, 1)
        XCTAssertEqual(plan.registry.rooms[0], local)
        XCTAssertTrue(plan.samsungPairings.isEmpty)
    }

    func testPreviewNamesAndRoomBindingsExactlyMatchCommitAndRepeatImport() throws {
        let original = DeviceRegistry(rooms: [RoomProfile(id: "living", name: "Living Room")])
        let plan = try RoomTransferPlan(payload: payload, existing: original)
        let copy = try XCTUnwrap(plan.roomResults.first { $0.incomingID == "living" })
        XCTAssertTrue(copy.isAdded)
        XCTAssertEqual(copy.room.name, "Living Room (shared)")
        XCTAssertEqual(plan.registry.rooms.first { $0.id == copy.room.id }, copy.room)
        XCTAssertEqual(plan.registry.rooms[0], original.rooms[0])
        let repeated = try RoomTransferPlan(payload: payload, existing: plan.registry)
        XCTAssertEqual(repeated.registry, plan.registry)
        XCTAssertTrue(repeated.roomResults.allSatisfy { !$0.isAdded })
    }

    func testEmptySelectionRejectsWhileAnExplicitEmptyRoomIsValid() throws {
        XCTAssertThrowsError(try payload.selecting(deviceIDs: [], roomIDs: [], includePairings: false))
        XCTAssertThrowsError(try RoomTransferPayload(devices: [], rooms: []).validate())
        let selected = try payload.selecting(deviceIDs: [], roomIDs: ["living"], includePairings: true)
        XCTAssertTrue(selected.devices.isEmpty)
        XCTAssertTrue(selected.samsungPairings.isEmpty)
        XCTAssertNil(selected.rooms[0].samsungID)
        try selected.validate()
    }
}
