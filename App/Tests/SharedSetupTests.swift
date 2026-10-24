import XCTest
@testable import RoomRemote

final class SharedSetupTests: XCTestCase {
    private let samsung = RemoteDevice(id: "samsung-living", kind: .samsung, name: "Living TV", address: "192.168.1.20", port: 8002, wakeMACAddress: "02:11:22:33:44:66")
    private func apple(_ name: String, address: String = "192.168.1.30") -> RemoteDevice {
        RemoteDevice(id: "apple:" + name.lowercased(), kind: .appleTV, name: name, address: address, port: 49153,
                     serviceName: name, serviceType: "_companion-link._tcp", serviceDomain: "local.")
    }
    private var payload: RoomTransferPayload {
        RoomTransferPayload(version: 2, devices: [samsung, apple("Living"), apple("Family", address: "192.168.1.31")],
            rooms: [RoomProfile(id: "living", name: "Living Room", samsungID: samsung.id, appleID: "apple:living")],
            starredApps: ["apple:living": ["com.example.Player", "com.example.Missing"], "apple:family": []],
            remotePreferences: SharedRemotePreferences(layout: .expandedAppleTVRemote, useTouchpad: true))
    }

    func testNetworkEditChangesBothValuesWithoutReplacingIdentityRoomsOrStars() throws {
        var registry = try RoomTransferPlan(payload: payload, existing: DeviceRegistry(rooms: [])).registry
        let rooms = registry.rooms, stars = registry.appleAppFavorites
        try registry.updateTVNetwork(address: " 192.168.1.40 ", macAddress: "02-11-22-33-44-88", for: samsung.id, name: "  Family Screen  ")
        XCTAssertEqual(registry.device(samsung.id, kind: .samsung)?.name, "Family Screen")
        XCTAssertEqual(registry.device(samsung.id, kind: .samsung)?.address, "192.168.1.40")
        XCTAssertEqual(registry.device(samsung.id, kind: .samsung)?.wakeMACAddress, "02:11:22:33:44:88")
        XCTAssertEqual(registry.rooms, rooms); XCTAssertEqual(registry.appleAppFavorites, stars)
        let target = try SamsungWakeTarget(device: XCTUnwrap(registry.device(samsung.id, kind: .samsung)))
        XCTAssertEqual(target.address, "192.168.1.40"); XCTAssertEqual(target.macAddress, "02:11:22:33:44:88")
    }

    func testInvalidNetworkEditsDoNotPartiallyChangeEitherValue() throws {
        let original = try RoomTransferPlan(payload: payload, existing: DeviceRegistry(rooms: [])).registry
        for (ip, mac) in [("8.8.8.8", "02:11:22:33:44:88"), ("192.168.1.40", "bad"), ("192.168.1.30", "02:11:22:33:44:88")] {
            var registry = original
            XCTAssertThrowsError(try registry.updateTVNetwork(address: ip, macAddress: mac, for: samsung.id, name: "Changed name"))
            XCTAssertEqual(registry, original)
        }
    }

    func testInvalidNameDoesNotSaveNetworkEditsAndExplicitMACClearPersists() throws {
        let original = try RoomTransferPlan(payload: payload, existing: DeviceRegistry(rooms: [])).registry
        for name in ["  ", String(repeating: "A", count: 81)] {
            var registry = original
            XCTAssertThrowsError(try registry.updateTVNetwork(address: "192.168.1.40", macAddress: nil, for: samsung.id, name: name))
            XCTAssertEqual(registry, original)
        }
        var registry = original
        try registry.updateTVNetwork(address: samsung.address, macAddress: nil, for: samsung.id, name: "Cleared MAC")
        let restored = try JSONDecoder().decode(DeviceRegistry.self, from: JSONEncoder().encode(registry))
        XCTAssertNil(restored.device(samsung.id, kind: .samsung)?.wakeMACAddress)
        XCTAssertEqual(restored.device(samsung.id, kind: .samsung)?.name, "Cleared MAC")
        XCTAssertEqual(restored.rooms, original.rooms)
    }

    func testAppleIPChangePreservesDiscoveryIdentityAndStarsAndRejectsMAC() throws {
        var registry = try RoomTransferPlan(payload: payload, existing: DeviceRegistry(rooms: [])).registry
        try registry.updateTVNetwork(address: "192.168.1.32", macAddress: nil, for: "apple:living")
        XCTAssertEqual(registry.device("apple:living", kind: .appleTV)?.serviceName, "Living")
        XCTAssertEqual(registry.starredAppIDs(for: "apple:living"), payload.starredApps?["apple:living"])
        let saved = registry
        XCTAssertThrowsError(try registry.updateTVNetwork(address: "192.168.1.33", macAddress: "02:11:22:33:44:88", for: "apple:living"))
        XCTAssertEqual(registry, saved)
    }

    func testFullSetupEncryptionCopiesMACRoomsStarsAndRemoteAppearance() throws {
        let file = try RoomTransfer.encrypt(payload, code: "cable lunar velvet walnut")
        let decoded = try RoomTransfer.decrypt(file, code: "cable lunar velvet walnut")
        XCTAssertEqual(decoded.version, 2); XCTAssertEqual(decoded.starredApps, payload.starredApps)
        XCTAssertEqual(decoded.remotePreferences, payload.remotePreferences)
        let plan = try RoomTransferPlan(payload: decoded, existing: DeviceRegistry())
        XCTAssertEqual(plan.registry.rooms, payload.rooms, "Fresh unused Living Room is replaced, not renamed shared")
        XCTAssertEqual(plan.registry.devices, payload.devices)
        XCTAssertEqual(plan.registry.device(samsung.id, kind: .samsung)?.wakeMACAddress, samsung.wakeMACAddress)
        XCTAssertEqual(plan.registry.starredAppIDs(for: "apple:living"), ["com.example.Player", "com.example.Missing"])
        XCTAssertEqual(plan.copiedStarTVCount, 2); XCTAssertEqual(plan.copiedStarCount, 2)
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("com.example.Player"))
    }

    func testExactSharedStarsReplaceChosenExistingListAndCanClearIt() throws {
        var existing = DeviceRegistry(devices: payload.devices, rooms: payload.rooms)
        try existing.setAppStarred(true, appID: "com.example.Old", for: "apple:living")
        try existing.setAppStarred(true, appID: "com.example.Old", for: "apple:family")
        let selected = try payload.selecting(deviceIDs: ["apple:living"], roomIDs: [], includePairings: false)
        let result = try RoomTransferPlan(payload: selected, existing: existing).registry
        XCTAssertEqual(result.starredAppIDs(for: "apple:living"), payload.starredApps?["apple:living"])
        XCTAssertEqual(result.starredAppIDs(for: "apple:family"), ["com.example.Old"])
        let clear = try payload.selecting(deviceIDs: ["apple:family"], roomIDs: [], includePairings: false)
        XCTAssertTrue(try RoomTransferPlan(payload: clear, existing: existing).registry.starredAppIDs(for: "apple:family").isEmpty)
    }

    func testMissingAppsAreHiddenWhileImportedStarsRemainSaved() throws {
        let registry = try RoomTransferPlan(payload: payload, existing: DeviceRegistry()).registry
        let rows = AppLibrarySections(apps: [RemoteAppInfo(id: "com.example.Player", name: "Player")], starredIDs: registry.starredAppIDs(for: "apple:living"))
        XCTAssertEqual(rows.starred.map(\.id), ["com.example.Player"])
        XCTAssertTrue(registry.starredAppIDs(for: "apple:living").contains("com.example.Missing"))
    }

    func testReceiverCanDeclineStarsAndAppearanceIndependently() throws {
        let selected = try payload.selecting(deviceIDs: ["apple:living"], roomIDs: [], includePairings: false, includeStars: false, includeRemotePreferences: false)
        XCTAssertNil(selected.starredApps); XCTAssertNil(selected.remotePreferences)
        var existing = DeviceRegistry(devices: payload.devices, rooms: payload.rooms)
        try existing.setAppStarred(true, appID: "com.example.Old", for: "apple:living")
        XCTAssertEqual(try RoomTransferPlan(payload: selected, existing: existing).registry, existing)
    }

    func testUnknownWrongKindAndInvalidStarEntriesRejectEvenIfExcluded() throws {
        let variants: [[String: Set<String>]] = [["unknown": []], [samsung.id: ["com.example.Player"]], ["apple:living": ["bad app"]], ["apple:living": Set((0..<257).map { "com.example.App\($0)" })]]
        for stars in variants {
            var invalid = payload; invalid.starredApps = stars
            XCTAssertThrowsError(try invalid.selecting(deviceIDs: [samsung.id], roomIDs: [], includePairings: false, includeStars: false))
        }
    }

    func testGlobalStarLimitRejectsBeforeChangingExistingRegistry() throws {
        var large = payload
        large.devices = (0..<5).map { apple("TV\($0)", address: "192.168.1.\(40 + $0)") }; large.rooms = []
        large.starredApps = Dictionary(uniqueKeysWithValues: large.devices.map { ($0.id, Set((0..<256).map { "com.example.App\($0)" })) })
        XCTAssertThrowsError(try large.validate())
    }

    func testExactReplacementChecksFinalLimitAndIsAtomicOnInvalidInput() throws {
        let tvs = (0..<5).map { apple("TV\($0)", address: "192.168.1.\(40 + $0)") }
        var registry = DeviceRegistry(devices: tvs, rooms: [])
        let apps = Set((0..<256).map { "com.example.App\($0)" })
        for tv in tvs.dropFirst() { try registry.replaceAppStars(apps, for: tv.id) }
        try registry.replaceAppStars([tvs[0].id: apps, tvs[1].id: []])
        XCTAssertEqual(registry.starredAppIDs(for: tvs[0].id), apps)
        XCTAssertTrue(registry.starredAppIDs(for: tvs[1].id).isEmpty)
        let before = registry
        XCTAssertThrowsError(try registry.replaceAppStars([tvs[0].id: [], tvs[1].id: ["bad app"]]))
        XCTAssertEqual(registry, before)
    }

    func testLegacyPayloadDoesNotClearStarsOrImportPreferences() throws {
        var old = payload; old.version = 1; old.starredApps = nil; old.remotePreferences = nil
        let decoded = try JSONDecoder().decode(RoomTransferPayload.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.starredApps); XCTAssertNil(decoded.remotePreferences)
        var existing = DeviceRegistry(devices: payload.devices, rooms: payload.rooms)
        try existing.setAppStarred(true, appID: "com.example.Old", for: "apple:living")
        XCTAssertEqual(try RoomTransferPlan(payload: decoded, existing: existing).registry, existing)
        old.starredApps = ["apple:living": []]
        XCTAssertThrowsError(try old.validate(), "New fields cannot be smuggled into legacy version")
    }

    func testRemoteOnlySelectionIsAllowedWithoutManufacturingTVsOrRooms() throws {
        let selected = try payload.selecting(deviceIDs: [], roomIDs: [], includePairings: false, includeStars: false)
        XCTAssertTrue(selected.devices.isEmpty); XCTAssertTrue(selected.rooms.isEmpty)
        XCTAssertEqual(selected.remotePreferences, payload.remotePreferences)
        XCTAssertThrowsError(try selected.selecting(deviceIDs: [], roomIDs: [], includePairings: false, includeRemotePreferences: false))
    }

    func testRepeatedFullImportIsIdempotentAndConfiguredRoomsArePreserved() throws {
        let existing = DeviceRegistry(devices: [samsung], rooms: [RoomProfile(id: "living", name: "Living Room", samsungID: samsung.id)])
        let first = try RoomTransferPlan(payload: payload, existing: existing)
        XCTAssertEqual(first.registry.rooms.first { $0.id == "living" }, existing.rooms[0])
        XCTAssertEqual(first.roomResults[0].room.name, "Living Room (shared)")
        let second = try RoomTransferPlan(payload: payload, existing: first.registry)
        XCTAssertEqual(second.registry, first.registry)
    }
}
