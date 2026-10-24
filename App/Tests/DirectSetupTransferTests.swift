import XCTest
import CoreTransferable
@testable import RoomRemote

final class DirectSetupTransferTests: XCTestCase {
    private var fixture: RoomTransferPayload {
        let samsung = RemoteDevice(id: "samsung-direct", kind: .samsung, name: "Living TV", address: "192.168.1.20", port: 8002,
                                   wakeMACAddress: "02:11:22:33:44:66")
        let apple = RemoteDevice(id: "apple:direct", kind: .appleTV, name: "Living Room", address: "192.168.1.21", port: 49152,
                                 serviceName: "direct", serviceType: "_companion-link._tcp", serviceDomain: "local.")
        return RoomTransferPayload(version: 3, devices: [samsung, apple],
            rooms: [RoomProfile(id: "living", name: "Living Room", samsungID: samsung.id, appleID: apple.id)],
            samsungPairings: [SamsungPairingTransfer(deviceID: samsung.id, token: "synthetic-private-token", certificateSHA256: Data(repeating: 1, count: 32), clientName: SamsungProtocol.clientName(deviceID: samsung.id))],
            starredApps: [apple.id: ["com.comcast.cim.x2"]], remotePreferences: SharedRemotePreferences(layout: .defaultLayout, useTouchpad: true),
            universalStars: SharedUniversalStars(enabled: true, appIDs: ["com.comcast.cim.x2", "com.example.Missing"]))
    }

    func testDirectFileOpensWithoutPhrasePreservesConfigAndNeverExportsTokensOrRooms() throws {
        let file = try RoomTransfer.directFile(fixture)
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("synthetic-private-token"))
        let decoded = try XCTUnwrap(RoomTransfer.directPayload(from: file))
        XCTAssertEqual(decoded.devices, fixture.devices)
        XCTAssertEqual(decoded.starredApps, fixture.starredApps)
        XCTAssertEqual(decoded.universalStars, fixture.universalStars)
        XCTAssertEqual(decoded.remotePreferences, fixture.remotePreferences)
        XCTAssertTrue(decoded.rooms.isEmpty); XCTAssertTrue(decoded.applePairings.isEmpty); XCTAssertTrue(decoded.samsungPairings.isEmpty)
        let existing = DeviceRegistry(rooms: [RoomProfile(id: "mine", name: "My Room")])
        let plan = try RoomTransferPlan(payload: decoded, existing: existing)
        XCTAssertEqual(plan.registry.rooms, existing.rooms)
        XCTAssertTrue(plan.samsungPairings.isEmpty)
        let repeatPlan = try RoomTransferPlan(payload: decoded, existing: plan.registry)
        XCTAssertEqual(repeatPlan.registry, plan.registry)
    }

    func testLegacyProtectedFileStillNeedsPhraseButDoesNotInstallSharedSamsungAccess() throws {
        let file = try RoomTransfer.encrypt(fixture, code: "cable lunar velvet walnut")
        XCTAssertNil(try RoomTransfer.directPayload(from: file))
        XCTAssertThrowsError(try RoomTransfer.decrypt(file, code: "not a valid phrase"))
        let decoded = try RoomTransfer.decrypt(file, code: "cable lunar velvet walnut").deviceSetupOnly()
        XCTAssertTrue(decoded.samsungPairings.isEmpty); XCTAssertTrue(decoded.rooms.isEmpty)
        XCTAssertEqual(decoded.devices, fixture.devices)
    }

    func testMalformedDirectFilesCannotFallBackToPhraseOrHideInvalidEntries() throws {
        let file = try RoomTransfer.directFile(fixture)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: file) as? [String: Any])
        for mutation in ["version", "format", "payload"] {
            var bad = original
            bad[mutation] = mutation == "version" ? 2 : "invalid"
            XCTAssertThrowsError(try RoomTransfer.directPayload(from: JSONSerialization.data(withJSONObject: bad)))
        }
        var bad = original
        var payload = try XCTUnwrap(bad["payload"] as? [String: Any])
        payload["samsungPairings"] = [["deviceID": "unknown", "token": "invalid"]]
        bad["payload"] = payload
        XCTAssertThrowsError(try RoomTransfer.directPayload(from: JSONSerialization.data(withJSONObject: bad)))
        XCTAssertThrowsError(try RoomTransfer.directPayload(from: Data(repeating: 32, count: RoomTransfer.maximumFileBytes + 1)))
        XCTAssertThrowsError(try RoomTransfer.directPayload(from: Data((String(repeating: "[", count: 17) + String(repeating: "]", count: 17)).utf8)))
    }

    private var withRooms: RoomTransferPayload {
        var payload = fixture
        payload.version = 4; payload.roomAssignmentsIncluded = true
        return payload
    }

    func testRoomMappingsRoundTripThroughDirectAndProtectedFilesWithoutCredentials() throws {
        let direct = try XCTUnwrap(RoomTransfer.directPayload(from: RoomTransfer.directFile(withRooms)))
        let protected = try RoomTransfer.decrypt(RoomTransfer.encrypt(withRooms, code: "cable lunar velvet walnut"), code: "cable lunar velvet walnut").deviceSetupOnly()
        for decoded in [direct, protected] {
            XCTAssertEqual(decoded.rooms, fixture.rooms)
            XCTAssertEqual(decoded.rooms.first?.samsungID, fixture.devices[0].id)
            XCTAssertEqual(decoded.rooms.first?.appleID, fixture.devices[1].id)
            XCTAssertEqual(decoded.starredApps, fixture.starredApps)
            XCTAssertTrue(decoded.samsungPairings.isEmpty); XCTAssertTrue(decoded.applePairings.isEmpty)
        }
    }

    func testExplicitRoomImportFillsEmptyRoomAfterTVsWereAlreadyImportedAndIsIdempotent() throws {
        let empty = RoomProfile(id: "receiver-room", name: "Living Room")
        let existing = DeviceRegistry(devices: fixture.devices, rooms: [empty])
        let first = try RoomTransferPlan(payload: withRooms.deviceSetupOnly(), existing: existing)
        XCTAssertEqual(first.registry.rooms.count, 1)
        XCTAssertEqual(first.registry.rooms[0].id, empty.id)
        XCTAssertEqual(first.registry.rooms[0].samsungID, fixture.devices[0].id)
        XCTAssertEqual(first.registry.rooms[0].appleID, fixture.devices[1].id)
        XCTAssertEqual(first.updatedRoomCount, 1)
        let again = try RoomTransferPlan(payload: withRooms.deviceSetupOnly(), existing: first.registry)
        XCTAssertEqual(again.registry, first.registry)
        XCTAssertEqual(again.updatedRoomCount, 0); XCTAssertEqual(again.addedRoomCount, 0)
    }

    func testConfiguredRoomConflictAddsPreviewedCopyAndNeverReplacesLocalAssignments() throws {
        let original = RoomProfile(id: "living", name: "Living Room", appleID: fixture.devices[1].id)
        let existing = DeviceRegistry(devices: fixture.devices, rooms: [original])
        let plan = try RoomTransferPlan(payload: withRooms.deviceSetupOnly(), existing: existing)
        XCTAssertEqual(plan.registry.rooms[0], original)
        let copy = try XCTUnwrap(plan.roomResults.first)
        XCTAssertTrue(copy.isAdded); XCTAssertEqual(copy.room.name, "Living Room (shared)")
        XCTAssertEqual(copy.room.samsungID, fixture.devices[0].id)
        XCTAssertEqual(copy.room.appleID, fixture.devices[1].id)
        XCTAssertEqual(try RoomTransferPlan(payload: withRooms.deviceSetupOnly(), existing: plan.registry).registry, plan.registry)
    }

    func testRecipientCanExcludeRoomsOrOneTVWithoutDanglingReferences() throws {
        let none = try withRooms.selecting(deviceIDs: Set(fixture.devices.map(\.id)), roomIDs: [], includePairings: false).deviceSetupOnly()
        XCTAssertTrue(none.rooms.isEmpty)
        let partial = try withRooms.selecting(deviceIDs: [fixture.devices[1].id], roomIDs: ["living"], includePairings: false).deviceSetupOnly()
        XCTAssertNil(partial.rooms[0].samsungID); XCTAssertEqual(partial.rooms[0].appleID, fixture.devices[1].id)
        XCTAssertTrue(partial.samsungPairings.isEmpty)
        var invalid = withRooms; invalid.rooms[0].appleID = "unknown"
        XCTAssertThrowsError(try invalid.deviceSetupOnly())
    }

    func testNewRoomFlagCannotBeSmuggledIntoOldPayloadVersions() throws {
        var payload = withRooms; payload.version = 3
        XCTAssertThrowsError(try payload.validate())
        payload.version = 4; payload.roomAssignmentsIncluded = nil
        XCTAssertThrowsError(try payload.validate())
    }

    func testNativeSharingAdvertisesOnlyTheMatchingFileType() {
        let url = URL(fileURLWithPath: "/tmp/fixture.atvsetup")
        XCTAssertEqual(SetupShareFile(url: url, requiresPhrase: false).exportedContentTypes(), [.roomRemoteDirectSetup])
        XCTAssertEqual(SetupShareFile(url: url, requiresPhrase: true).exportedContentTypes(), [.roomRemoteSetup])
    }
}
