import XCTest
@testable import RoomRemote

final class DeviceRegistryTests: XCTestCase {
    private func pairingDevice(_ kind: DeviceKind, id: String) -> RemoteDevice {
        RemoteDevice(id: id, kind: kind, name: id, address: "192.168.1.10")
    }

    func testLegacyDeviceWithoutWakeMACDecodesWithoutChangingSavedIdentity() throws {
        let oldDevice = Data(#"{"id":"samsung:living","kind":"samsung","name":"Living TV","address":"192.168.1.10","port":8002}"#.utf8)
        let decoded = try JSONDecoder().decode(RemoteDevice.self, from: oldDevice)
        XCTAssertEqual(decoded.id, "samsung:living")
        XCTAssertEqual(decoded.kind, .samsung)
        XCTAssertEqual(decoded.name, "Living TV")
        XCTAssertEqual(decoded.address, "192.168.1.10")
        XCTAssertEqual(decoded.port, 8002)
        XCTAssertNil(decoded.wakeMACAddress)
        let room = RoomProfile(id: "living", name: "Living Room", samsungID: decoded.id)
        let registry = DeviceRegistry(devices: [decoded], rooms: [room], lastRoomID: room.id)
        let reloaded = try JSONDecoder().decode(DeviceRegistry.self, from: JSONEncoder().encode(registry))
        XCTAssertEqual(reloaded, registry)
        XCTAssertEqual(reloaded.rooms[0].samsungID, decoded.id)
    }

    func testWakeMACIsCanonicalIndependentPerTVAndPreservesRoomsAndStars() throws {
        let first = pairingDevice(.samsung, id: "samsung:first")
        let second = pairingDevice(.samsung, id: "samsung:second")
        let apple = pairingDevice(.appleTV, id: "apple:living")
        let room = RoomProfile(id: "living", name: "Living Room", samsungID: first.id, appleID: apple.id)
        var registry = DeviceRegistry(devices: [first, second, apple], rooms: [room], lastRoomID: room.id)
        try registry.setAppStarred(true, appID: "com.example.Player", for: apple.id)
        let favorites = registry.appleAppFavorites
        XCTAssertTrue(try registry.setSamsungWakeMAC(" aa:bb:cc:dd:ee:02 ", for: first.id))
        XCTAssertTrue(try registry.setSamsungWakeMAC("02-11-22-33-44-66", for: second.id))
        XCTAssertFalse(try registry.setSamsungWakeMAC("AABB.CCDD.EE02", for: first.id))
        XCTAssertEqual(registry.device(first.id, kind: .samsung)?.wakeMACAddress, "AA:BB:CC:DD:EE:02")
        XCTAssertEqual(registry.device(second.id, kind: .samsung)?.wakeMACAddress, "02:11:22:33:44:66")
        XCTAssertNil(registry.device(apple.id, kind: .appleTV)?.wakeMACAddress)
        XCTAssertEqual(registry.devices.map(\.id), [first.id, second.id, apple.id])
        XCTAssertEqual(registry.rooms, [room])
        XCTAssertEqual(registry.lastRoomID, room.id)
        XCTAssertEqual(registry.appleAppFavorites, favorites)
    }

    func testWakeMACRejectsUnknownAppleAndInvalidValuesWithoutMutation() throws {
        let samsung = pairingDevice(.samsung, id: "samsung:living")
        let apple = pairingDevice(.appleTV, id: "apple:living")
        var registry = DeviceRegistry(devices: [samsung, apple])
        try registry.setSamsungWakeMAC("02:11:22:33:44:66", for: samsung.id)
        let before = registry
        for invalidID in ["missing", apple.id] {
            for raw in [nil, "", "02:11:22:33:44:66"] as [String?] {
                XCTAssertThrowsError(try registry.setSamsungWakeMAC(raw, for: invalidID))
                XCTAssertEqual(registry, before)
            }
        }
        for invalidMAC in ["bad", "02:11:22:33:44", "02:11:22:33:44:GG", "02:11:22:\n33:44:66", "00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "01:11:22:33:44:66"] {
            XCTAssertThrowsError(try registry.setSamsungWakeMAC(invalidMAC, for: samsung.id), invalidMAC)
            XCTAssertEqual(registry, before)
        }
    }

    func testNilOrBlankWakeMACClearsOnlyTheChosenSamsung() throws {
        let first = pairingDevice(.samsung, id: "samsung:first")
        let second = pairingDevice(.samsung, id: "samsung:second")
        var registry = DeviceRegistry(devices: [first, second])
        try registry.setSamsungWakeMAC("02:11:22:33:44:66", for: first.id)
        try registry.setSamsungWakeMAC("02:11:22:33:44:88", for: second.id)
        XCTAssertTrue(try registry.setSamsungWakeMAC(nil, for: first.id))
        XCTAssertFalse(try registry.setSamsungWakeMAC(" \n\t ", for: first.id))
        XCTAssertNil(registry.device(first.id, kind: .samsung)?.wakeMACAddress)
        XCTAssertEqual(registry.device(second.id, kind: .samsung)?.wakeMACAddress, "02:11:22:33:44:88")
        try registry.setSamsungWakeMAC("02:11:22:33:44:66", for: first.id)
        XCTAssertTrue(try registry.setSamsungWakeMAC(" \n\t ", for: first.id))
        XCTAssertNil(registry.device(first.id, kind: .samsung)?.wakeMACAddress)
    }

    func testPairingRefreshPreservesSavedWakeMACNameRoomAndAppleStars() throws {
        var saved = pairingDevice(.samsung, id: "samsung:living")
        saved.name = "My Living TV"
        saved.wakeMACAddress = "02:11:22:33:44:66"
        let apple = pairingDevice(.appleTV, id: "apple:living")
        let room = RoomProfile(id: "living", name: "Living Room", samsungID: saved.id, appleID: apple.id)
        for incomingMAC in [nil, "02:11:22:33:44:88", "not-a-mac"] as [String?] {
            var registry = DeviceRegistry(devices: [saved, apple], rooms: [room], lastRoomID: room.id)
            try registry.setAppStarred(true, appID: "com.example.Player", for: apple.id)
            var renamed = room
            renamed.name = "Living Room TV"
            try registry.saveRoom(renamed)
            var refreshed = saved
            refreshed.name = "Discovered label"
            refreshed.address = "192.168.1.90"
            refreshed.wakeMACAddress = incomingMAC
            var setup = EmptyRoomSetup()
            XCTAssertFalse(try registry.addForPairing(refreshed, roomID: room.id, initialSetup: &setup))
            let actual = try XCTUnwrap(registry.device(saved.id, kind: .samsung))
            XCTAssertEqual(actual.id, saved.id)
            XCTAssertEqual(actual.name, saved.name)
            XCTAssertEqual(actual.address, refreshed.address)
            XCTAssertEqual(actual.wakeMACAddress, saved.wakeMACAddress)
            XCTAssertEqual(registry.rooms, [renamed])
            XCTAssertEqual(registry.lastRoomID, room.id)
            XCTAssertEqual(registry.starredAppIDs(for: apple.id), ["com.example.Player"])
        }
    }

    func testPairingRefreshCanAdoptValidIncomingWakeMACOnlyWhenNoneWasSaved() throws {
        let saved = pairingDevice(.samsung, id: "samsung:living")
        let room = RoomProfile(id: "empty", name: "Empty Room")
        var registry = DeviceRegistry(devices: [saved], rooms: [room])
        var refreshed = saved
        refreshed.name = "Discovered label"
        refreshed.wakeMACAddress = "021122334466"
        var setup = EmptyRoomSetup()
        XCTAssertFalse(try registry.addForPairing(refreshed, roomID: room.id, initialSetup: &setup))
        XCTAssertEqual(registry.device(saved.id, kind: .samsung)?.wakeMACAddress, "02:11:22:33:44:66")
        XCTAssertEqual(registry.device(saved.id, kind: .samsung)?.name, saved.name)
        XCTAssertEqual(registry.rooms, [room])
    }

    func testInvalidPairingWakeMetadataDoesNotAddOrRefreshDevicesOrRooms() throws {
        let saved = pairingDevice(.samsung, id: "samsung:saved")
        let room = RoomProfile(id: "empty", name: "Empty Room")
        var registry = DeviceRegistry(devices: [saved], rooms: [room])
        let before = registry
        var incoming = saved
        incoming.name = "Replacement label"
        incoming.wakeMACAddress = "invalid"
        var setup = EmptyRoomSetup()
        XCTAssertThrowsError(try registry.addForPairing(incoming, roomID: room.id, initialSetup: &setup))
        XCTAssertEqual(registry, before)
        incoming.id = "samsung:new"
        XCTAssertThrowsError(try registry.addForPairing(incoming, roomID: room.id, initialSetup: &setup))
        XCTAssertEqual(registry, before)
        incoming = pairingDevice(.appleTV, id: "apple:new")
        incoming.wakeMACAddress = "02:11:22:33:44:66"
        XCTAssertThrowsError(try registry.addForPairing(incoming, roomID: room.id, initialSetup: &setup))
        XCTAssertEqual(registry, before)
    }

    func testNewSamsungPairingStoresCanonicalWakeMACAndFillsInitialRoom() throws {
        let room = RoomProfile(id: "empty", name: "Empty Room")
        var registry = DeviceRegistry(rooms: [room])
        var incoming = pairingDevice(.samsung, id: "samsung:new")
        incoming.wakeMACAddress = "02-11-22-33-44-66"
        var setup = EmptyRoomSetup()
        XCTAssertTrue(try registry.addForPairing(incoming, roomID: room.id, initialSetup: &setup))
        XCTAssertEqual(registry.device(incoming.id, kind: .samsung)?.wakeMACAddress, "02:11:22:33:44:66")
        XCTAssertEqual(registry.rooms[0].samsungID, incoming.id)
    }

    func testRegistryStorageAndInterruptedImportRecoveryPreserveWakeMetadata() throws {
        var saved = pairingDevice(.samsung, id: "samsung:living")
        saved.port = 8002
        saved.wakeMACAddress = "02:11:22:33:44:66"
        let room = RoomProfile(id: "living", name: "Living Room", samsungID: saved.id)
        let registry = DeviceRegistry(devices: [saved], rooms: [room], lastRoomID: room.id)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try RegistryStorage.save(registry, in: directory)
        let reloaded = try XCTUnwrap(RegistryStorage.load(in: directory))
        XCTAssertEqual(reloaded, registry)
        var duplicate = saved
        duplicate.wakeMACAddress = "02:11:22:33:44:88"
        var imported = saved
        imported.id = "samsung:recovered"
        imported.address = "192.168.1.20"
        imported.wakeMACAddress = "02:11:22:33:44:AA"
        try RegistryStorage.beginImport([duplicate, imported], in: directory)
        let recovered = try RegistryStorage.recover(reloaded, in: directory)
        XCTAssertEqual(recovered.device(saved.id, kind: .samsung)?.wakeMACAddress, saved.wakeMACAddress)
        XCTAssertEqual(recovered.device(imported.id, kind: .samsung)?.wakeMACAddress, imported.wakeMACAddress)
        XCTAssertEqual(recovered.rooms, registry.rooms)
        XCTAssertEqual(recovered.lastRoomID, registry.lastRoomID)
        XCTAssertEqual(try RegistryStorage.load(in: directory), recovered)
    }

    func testRegistryWithoutFavoritesMigratesWithoutChangingSavedSetup() throws {
        let apple = pairingDevice(.appleTV, id: "apple:living")
        let room = RoomProfile(id: "living", name: "Living Room", appleID: apple.id)
        let existing = DeviceRegistry(devices: [apple], rooms: [room], lastRoomID: room.id)
        var oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(existing)) as? [String: Any])
        oldJSON.removeValue(forKey: "appleAppFavorites")
        let migrated = try JSONDecoder().decode(DeviceRegistry.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        XCTAssertEqual(migrated, existing)
        XCTAssertTrue(migrated.starredAppIDs(for: apple.id).isEmpty)

        oldJSON["appleAppFavorites"] = NSNull()
        let nullFavorites = try JSONDecoder().decode(DeviceRegistry.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        XCTAssertEqual(nullFavorites, existing)
    }

    func testFavoriteMigrationDoesNotAcceptMissingOriginalRequiredFields() throws {
        for missingKey in ["devices", "rooms"] {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(DeviceRegistry())) as? [String: Any])
            json.removeValue(forKey: missingKey)
            let data = try JSONSerialization.data(withJSONObject: json)
            XCTAssertThrowsError(try JSONDecoder().decode(DeviceRegistry.self, from: data))
        }
    }

    func testStarsPersistByTVIdentityAndExactBundleIDInsteadOfDisplayName() throws {
        var living = pairingDevice(.appleTV, id: "apple:living")
        var bedroom = pairingDevice(.appleTV, id: "apple:bedroom")
        living.name = "Apple TV"
        bedroom.name = living.name
        var registry = DeviceRegistry(devices: [living, bedroom])
        XCTAssertTrue(try registry.setAppStarred(true, appID: "com.example.Player", for: living.id))
        XCTAssertFalse(try registry.setAppStarred(true, appID: "com.example.Player", for: living.id))
        XCTAssertEqual(registry.starredAppIDs(for: living.id), ["com.example.Player"])
        XCTAssertFalse(registry.starredAppIDs(for: living.id).contains("com.example.player"))
        XCTAssertTrue(registry.starredAppIDs(for: bedroom.id).isEmpty)
        registry.devices[0].name = "Renamed Living Room"
        registry.devices[0].address = "192.168.1.50"
        let restored = try JSONDecoder().decode(DeviceRegistry.self, from: JSONEncoder().encode(registry))
        XCTAssertEqual(restored, registry)
        XCTAssertEqual(restored.starredAppIDs(for: living.id), ["com.example.Player"])
        XCTAssertTrue(restored.starredAppIDs(for: bedroom.id).isEmpty)
        XCTAssertTrue(try registry.setAppStarred(false, appID: "com.example.Player", for: living.id))
        XCTAssertFalse(try registry.setAppStarred(false, appID: "com.example.Player", for: living.id))
        XCTAssertTrue(registry.appleAppFavorites.isEmpty)
    }

    func testImportStarsMergesTargetKeepsSourceAndRetainsUninstalledBundleIDs() throws {
        let source = pairingDevice(.appleTV, id: "apple:source")
        let target = pairingDevice(.appleTV, id: "apple:target")
        var registry = DeviceRegistry(devices: [source, target])
        for appID in ["com.example.Shared", "com.example.NotInstalledOnTarget"] {
            try registry.setAppStarred(true, appID: appID, for: source.id)
        }
        for appID in ["com.example.Shared", "com.example.TargetOnly"] {
            try registry.setAppStarred(true, appID: appID, for: target.id)
        }
        let sourceBefore = registry.starredAppIDs(for: source.id)
        XCTAssertEqual(try registry.importAppStars(from: source.id, to: target.id), 1)
        XCTAssertEqual(registry.starredAppIDs(for: source.id), sourceBefore)
        XCTAssertEqual(registry.starredAppIDs(for: target.id), ["com.example.Shared", "com.example.TargetOnly", "com.example.NotInstalledOnTarget"])
        XCTAssertEqual(try registry.importAppStars(from: source.id, to: target.id), 0)

        // Missing inventory entries never erase the preference; the renderer can
        // hide them now and reveal the same stored star after a later install.
        let reloaded = try JSONDecoder().decode(DeviceRegistry.self, from: JSONEncoder().encode(registry))
        XCTAssertTrue(reloaded.starredAppIDs(for: target.id).contains("com.example.NotInstalledOnTarget"))
        XCTAssertTrue(try registry.setAppStarred(false, appID: "com.example.Shared", for: target.id))
        XCTAssertTrue(registry.starredAppIDs(for: source.id).contains("com.example.Shared"))
    }

    func testImportingEmptyStarsLeavesTargetUnchanged() throws {
        let source = pairingDevice(.appleTV, id: "apple:source")
        let target = pairingDevice(.appleTV, id: "apple:target")
        var registry = DeviceRegistry(devices: [source, target])
        try registry.setAppStarred(true, appID: "com.example.Player", for: target.id)
        let before = registry
        XCTAssertEqual(try registry.importAppStars(from: source.id, to: target.id), 0)
        XCTAssertEqual(registry, before)
    }

    func testFavoritesRejectUnknownSamsungAndSelfImportWithoutMutation() throws {
        let apple = pairingDevice(.appleTV, id: "apple:living")
        let samsung = pairingDevice(.samsung, id: "samsung:living")
        var registry = DeviceRegistry(devices: [apple, samsung])
        try registry.setAppStarred(true, appID: "com.example.Player", for: apple.id)
        let before = registry
        for invalidID in ["missing", samsung.id] {
            XCTAssertTrue(registry.starredAppIDs(for: invalidID).isEmpty)
            XCTAssertThrowsError(try registry.setAppStarred(true, appID: "com.example.Player", for: invalidID))
            XCTAssertThrowsError(try registry.importAppStars(from: invalidID, to: apple.id))
            XCTAssertThrowsError(try registry.importAppStars(from: apple.id, to: invalidID))
            XCTAssertEqual(registry, before)
        }
        XCTAssertThrowsError(try registry.importAppStars(from: apple.id, to: apple.id))
        XCTAssertEqual(registry, before)
    }

    func testFavoritesRejectMalformedOrOversizedAppIDsWithoutMutation() throws {
        let apple = pairingDevice(.appleTV, id: "apple:living")
        var registry = DeviceRegistry(devices: [apple])
        let before = registry
        for invalidID in ["", " com.example.App", "com.example.App ", "com.example.\nApp", "com.example.App/route", "com.example.💙", String(repeating: "a", count: 513)] {
            XCTAssertThrowsError(try registry.setAppStarred(true, appID: invalidID, for: apple.id), invalidID)
            XCTAssertEqual(registry, before)
        }
        XCTAssertTrue(try registry.setAppStarred(true, appID: "Com.example.App_2-tv", for: apple.id))
    }

    func testFavoritesLimitRejectsSingleStarAndOversizedImportAtomically() throws {
        let source = pairingDevice(.appleTV, id: "apple:source")
        let target = pairingDevice(.appleTV, id: "apple:target")
        var registry = DeviceRegistry(devices: [source, target])
        for index in 0..<256 {
            try registry.setAppStarred(true, appID: "com.example.Target\(index)", for: target.id)
        }
        try registry.setAppStarred(true, appID: "com.example.SourceOnly", for: source.id)
        let before = registry
        XCTAssertThrowsError(try registry.setAppStarred(true, appID: "com.example.Excess", for: target.id))
        XCTAssertThrowsError(try registry.importAppStars(from: source.id, to: target.id))
        XCTAssertEqual(registry, before)
    }

    func testFavoritesTotalLimitKeepsRegistryWithinStorageBounds() throws {
        let apples = (0..<5).map { pairingDevice(.appleTV, id: "apple:\($0)") }
        var registry = DeviceRegistry(devices: apples)
        for apple in apples.prefix(4) {
            for index in 0..<256 {
                try registry.setAppStarred(true, appID: "com.example.App\(index)", for: apple.id)
            }
        }
        let before = registry
        XCTAssertThrowsError(try registry.setAppStarred(true, appID: "com.example.Excess", for: apples[4].id))
        XCTAssertEqual(registry, before)
        XCTAssertTrue(try registry.setAppStarred(false, appID: "com.example.App0", for: apples[0].id))
        XCTAssertTrue(try registry.setAppStarred(true, appID: "com.example.Replacement", for: apples[4].id))
    }

    func testRemovingTVClearsOnlyItsStarsAndAllItsRoomReferences() throws {
        let first = pairingDevice(.appleTV, id: "apple:first")
        let other = pairingDevice(.appleTV, id: "apple:other")
        var registry = DeviceRegistry(devices: [first, other], rooms: [
            RoomProfile(name: "A", appleID: first.id), RoomProfile(name: "B", appleID: first.id), RoomProfile(name: "C", appleID: other.id)
        ])
        try registry.setAppStarred(true, appID: "com.example.First", for: first.id)
        try registry.setAppStarred(true, appID: "com.example.Other", for: other.id)
        registry.removeDevice(first.id)
        XCTAssertNil(registry.appleAppFavorites[first.id])
        XCTAssertTrue(registry.starredAppIDs(for: first.id).isEmpty)
        XCTAssertEqual(registry.starredAppIDs(for: other.id), ["com.example.Other"])
        XCTAssertTrue(registry.rooms.prefix(2).allSatisfy { $0.appleID == nil })
        XCTAssertEqual(registry.rooms[2].appleID, other.id)
    }

    func testFavoriteDecodePrunesOrphanWrongKindAndInvalidIDs() throws {
        let apple = pairingDevice(.appleTV, id: "apple:living")
        let samsung = pairingDevice(.samsung, id: "samsung:living")
        let registry = DeviceRegistry(devices: [apple, samsung])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(registry)) as? [String: Any])
        json["appleAppFavorites"] = [
            apple.id: ["com.example.Player", "com.example.Player", "", "com.example.App\n"],
            samsung.id: ["com.example.Player"], "deleted-apple": ["com.example.Player"]
        ]
        let decoded = try JSONDecoder().decode(DeviceRegistry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.appleAppFavorites, [apple.id: ["com.example.Player"]])
        XCTAssertEqual(decoded.devices, registry.devices)
        XCTAssertEqual(decoded.rooms, registry.rooms)
    }

    func testRoomChangesPairingRefreshStorageAndRecoveryPreserveStars() throws {
        let apple = pairingDevice(.appleTV, id: "apple:living")
        let room = RoomProfile(id: "living", name: "Living Room", appleID: apple.id)
        var registry = DeviceRegistry(devices: [apple], rooms: [room], lastRoomID: room.id)
        try registry.setAppStarred(true, appID: "com.example.Player", for: apple.id)
        var renamed = room
        renamed.name = "Living Room TV"
        try registry.saveRoom(renamed)
        var refreshed = apple
        refreshed.address = "192.168.1.90"
        var setup = EmptyRoomSetup()
        XCTAssertFalse(try registry.addForPairing(refreshed, roomID: room.id, initialSetup: &setup))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try RegistryStorage.save(registry, in: directory)
        let reloaded = try XCTUnwrap(RegistryStorage.load(in: directory))
        XCTAssertEqual(reloaded, registry)
        let imported = RemoteDevice(id: "apple:recovered", kind: .appleTV, name: "Recovered Apple TV", address: "192.168.1.20", port: 49153,
            serviceName: "recovered", serviceType: "_companion-link._tcp", serviceDomain: "local.")
        try RegistryStorage.beginImport([imported], in: directory)
        let recovered = try RegistryStorage.recover(reloaded, in: directory)
        XCTAssertEqual(recovered.starredAppIDs(for: apple.id), ["com.example.Player"])
        XCTAssertTrue(recovered.starredAppIDs(for: imported.id).isEmpty)
        XCTAssertEqual(recovered.rooms, registry.rooms)
        XCTAssertEqual(recovered.lastRoomID, registry.lastRoomID)
    }

    func testReselectingCurrentRoomPairNeedsNoConnectionChangesAndKeepsSamsungNavigation() throws {
        let samsung = pairingDevice(.samsung, id: "samsung")
        let apple = pairingDevice(.appleTV, id: "apple")
        let living = RoomProfile(id: "living", name: "Living Room", samsungID: samsung.id, appleID: apple.id)
        let registry = DeviceRegistry(devices: [samsung, apple], rooms: [living])
        let plan = try XCTUnwrap(registry.selectionPlan(for: living.id, currentRoomID: living.id,
            samsungID: samsung.id, appleID: apple.id, navigationTarget: .samsung))
        XCTAssertTrue(plan.isNoOp)
        XCTAssertFalse(plan.changesSamsung)
        XCTAssertFalse(plan.changesApple)
        XCTAssertEqual(plan.navigationTarget, .samsung)
    }

    func testReselectingCurrentRoomRestoresTemporaryPairWithoutChangingUnchangedTV() throws {
        let samsung = pairingDevice(.samsung, id: "living-samsung")
        let apple = pairingDevice(.appleTV, id: "living-apple")
        let familyApple = pairingDevice(.appleTV, id: "family-apple")
        let living = RoomProfile(id: "living", name: "Living Room", samsungID: samsung.id, appleID: apple.id)
        let registry = DeviceRegistry(devices: [samsung, apple, familyApple], rooms: [living])
        let plan = try XCTUnwrap(registry.selectionPlan(for: living.id, currentRoomID: living.id,
            samsungID: samsung.id, appleID: familyApple.id, navigationTarget: .samsung))
        XCTAssertFalse(plan.isNoOp)
        XCTAssertFalse(plan.changesRoom)
        XCTAssertFalse(plan.changesSamsung)
        XCTAssertTrue(plan.changesApple)
        XCTAssertEqual(plan.appleID, apple.id)
        XCTAssertEqual(plan.navigationTarget, .samsung)
        XCTAssertEqual(registry.rooms, [living])
    }

    func testChangingRoomsSharingBothTVsDoesNotChangeEitherConnection() throws {
        let samsung = pairingDevice(.samsung, id: "shared-samsung")
        let apple = pairingDevice(.appleTV, id: "shared-apple")
        let living = RoomProfile(id: "living", name: "Living Room", samsungID: samsung.id, appleID: apple.id)
        let family = RoomProfile(id: "family", name: "Family Room", samsungID: samsung.id, appleID: apple.id)
        let registry = DeviceRegistry(devices: [samsung, apple], rooms: [living, family])
        let plan = try XCTUnwrap(registry.selectionPlan(for: family.id, currentRoomID: living.id,
            samsungID: samsung.id, appleID: apple.id, navigationTarget: .samsung))
        XCTAssertFalse(plan.isNoOp)
        XCTAssertTrue(plan.changesRoom)
        XCTAssertFalse(plan.changesSamsung)
        XCTAssertFalse(plan.changesApple)
        XCTAssertEqual(plan.room, family)
        XCTAssertEqual(plan.navigationTarget, .samsung)
    }

    func testChangingRoomsSharingOneTVChangesOnlyOtherConnection() throws {
        let samsung = pairingDevice(.samsung, id: "shared-samsung")
        let livingApple = pairingDevice(.appleTV, id: "living-apple")
        let familyApple = pairingDevice(.appleTV, id: "family-apple")
        let living = RoomProfile(id: "living", name: "Living Room", samsungID: samsung.id, appleID: livingApple.id)
        let family = RoomProfile(id: "family", name: "Family Room", samsungID: samsung.id, appleID: familyApple.id)
        let registry = DeviceRegistry(devices: [samsung, livingApple, familyApple], rooms: [living, family])
        let plan = try XCTUnwrap(registry.selectionPlan(for: family.id, currentRoomID: living.id,
            samsungID: samsung.id, appleID: livingApple.id, navigationTarget: .appleTV))
        XCTAssertTrue(plan.changesRoom)
        XCTAssertFalse(plan.changesSamsung)
        XCTAssertTrue(plan.changesApple)
        XCTAssertEqual(plan.appleID, familyApple.id)
        XCTAssertEqual(plan.navigationTarget, .appleTV)
    }

    func testRoomSelectionChangesNavigationOnlyWhenCurrentTargetIsMissing() throws {
        let samsung = pairingDevice(.samsung, id: "samsung")
        let apple = pairingDevice(.appleTV, id: "apple")
        let samsungRoom = RoomProfile(id: "samsung-room", name: "Samsung", samsungID: samsung.id)
        let appleRoom = RoomProfile(id: "apple-room", name: "Apple", appleID: apple.id)
        let emptyRoom = RoomProfile(id: "empty-room", name: "Empty")
        let registry = DeviceRegistry(devices: [samsung, apple], rooms: [samsungRoom, appleRoom, emptyRoom])
        let samsungPlan = try XCTUnwrap(registry.selectionPlan(for: samsungRoom.id, currentRoomID: "other",
            samsungID: nil, appleID: apple.id, navigationTarget: .appleTV))
        XCTAssertEqual(samsungPlan.navigationTarget, .samsung)
        let applePlan = try XCTUnwrap(registry.selectionPlan(for: appleRoom.id, currentRoomID: "other",
            samsungID: samsung.id, appleID: nil, navigationTarget: .samsung))
        XCTAssertEqual(applePlan.navigationTarget, .appleTV)
        let emptyPlan = try XCTUnwrap(registry.selectionPlan(for: emptyRoom.id, currentRoomID: "other",
            samsungID: samsung.id, appleID: nil, navigationTarget: .samsung))
        XCTAssertEqual(emptyPlan.navigationTarget, .samsung)
    }

    func testRoomSelectionDoesNotRouteMissingOrWrongKindSavedIDs() throws {
        let samsung = pairingDevice(.samsung, id: "samsung")
        let room = RoomProfile(id: "corrupt", name: "Imported", samsungID: "missing", appleID: samsung.id)
        let registry = DeviceRegistry(devices: [samsung], rooms: [room])
        let plan = try XCTUnwrap(registry.selectionPlan(for: room.id, currentRoomID: "other",
            samsungID: samsung.id, appleID: nil, navigationTarget: .samsung))
        XCTAssertNil(plan.samsungID)
        XCTAssertNil(plan.appleID)
        XCTAssertTrue(plan.changesSamsung)
        XCTAssertFalse(plan.changesApple)
        XCTAssertNil(registry.selectionPlan(for: "deleted", currentRoomID: room.id,
            samsungID: nil, appleID: nil, navigationTarget: .samsung))
    }

    func testAddingFamilyRoomTVsPreservesPopulatedLivingRoom() throws {
        let livingSamsung = pairingDevice(.samsung, id: "living-samsung")
        let livingApple = pairingDevice(.appleTV, id: "living-apple")
        let living = RoomProfile(id: "living", name: "Living Room", samsungID: livingSamsung.id, appleID: livingApple.id)
        let family = RoomProfile(id: "family", name: "Family Room")
        var registry = DeviceRegistry(devices: [livingSamsung, livingApple], rooms: [living, family])
        var setup = EmptyRoomSetup()
        XCTAssertFalse(try registry.addForPairing(pairingDevice(.samsung, id: "family-samsung"), roomID: living.id, initialSetup: &setup))
        XCTAssertFalse(try registry.addForPairing(pairingDevice(.appleTV, id: "family-apple"), roomID: living.id, initialSetup: &setup))
        XCTAssertEqual(registry.rooms, [living, family])
        XCTAssertEqual(registry.devices.count, 4)
    }

    func testExistingPartialRoomsDoNotAutomaticallyAcquireMissingDevices() throws {
        for savedKind in DeviceKind.allCases {
            let saved = pairingDevice(savedKind, id: "saved")
            let room = RoomProfile(id: "partial", name: "Partial", samsungID: savedKind == .samsung ? saved.id : nil, appleID: savedKind == .appleTV ? saved.id : nil)
            var registry = DeviceRegistry(devices: [saved], rooms: [room])
            var setup = EmptyRoomSetup()
            for kind in DeviceKind.allCases {
                XCTAssertFalse(try registry.addForPairing(pairingDevice(kind, id: "new-\(kind.rawValue)"), roomID: room.id, initialSetup: &setup))
            }
            XCTAssertEqual(registry.rooms, [room])
        }
    }

    func testEmptyFirstSetupFillsSamsungAndAppleSlotsInEitherOrder() throws {
        for firstKind in DeviceKind.allCases {
            let room = RoomProfile(id: "empty", name: "New Room")
            var registry = DeviceRegistry(rooms: [room])
            var setup = EmptyRoomSetup()
            let secondKind: DeviceKind = firstKind == .samsung ? .appleTV : .samsung
            for kind in [firstKind, secondKind] {
                XCTAssertTrue(try registry.addForPairing(pairingDevice(kind, id: kind.rawValue), roomID: room.id, initialSetup: &setup))
            }
            XCTAssertEqual(registry.rooms[0].samsungID, DeviceKind.samsung.rawValue)
            XCTAssertEqual(registry.rooms[0].appleID, DeviceKind.appleTV.rawValue)
            XCTAssertEqual(registry.devices.count, 2)
        }
    }

    func testAddingSecondTVOfSameTypeEndsFirstSetupWithoutReplacingFirstTV() throws {
        for firstKind in DeviceKind.allCases {
            let room = RoomProfile(id: "empty", name: "New Room")
            var registry = DeviceRegistry(rooms: [room])
            var setup = EmptyRoomSetup()
            XCTAssertTrue(try registry.addForPairing(pairingDevice(firstKind, id: "first"), roomID: room.id, initialSetup: &setup))
            let firstAssignment = registry.rooms[0]
            XCTAssertFalse(try registry.addForPairing(pairingDevice(firstKind, id: "another"), roomID: room.id, initialSetup: &setup))
            let otherKind: DeviceKind = firstKind == .samsung ? .appleTV : .samsung
            XCTAssertFalse(try registry.addForPairing(pairingDevice(otherKind, id: "other-room"), roomID: room.id, initialSetup: &setup))
            XCTAssertEqual(registry.rooms[0], firstAssignment)
            XCTAssertEqual(registry.devices.count, 3)
        }
    }

    func testExistingDeviceRefreshPreservesNameAndDoesNotFillEmptyRoom() throws {
        let saved = pairingDevice(.appleTV, id: "apple:living")
        var refreshed = saved
        refreshed.name = "Bonjour name"
        refreshed.address = "192.168.1.99"
        refreshed.port = 50505
        let room = RoomProfile(id: "empty", name: "New Room")
        var registry = DeviceRegistry(devices: [saved], rooms: [room])
        var setup = EmptyRoomSetup()
        XCTAssertFalse(try registry.addForPairing(refreshed, roomID: room.id, initialSetup: &setup))
        XCTAssertEqual(registry.rooms, [room])
        XCTAssertEqual(registry.devices.count, 1)
        XCTAssertEqual(registry.devices[0].name, saved.name)
        XCTAssertEqual(registry.devices[0].address, refreshed.address)
        XCTAssertEqual(registry.devices[0].port, refreshed.port)
    }

    func testDuplicateDeviceEndsInitialSetupBeforeAnotherTypeIsAdded() throws {
        let room = RoomProfile(id: "empty", name: "New Room")
        let samsung = pairingDevice(.samsung, id: "first")
        var registry = DeviceRegistry(rooms: [room])
        var setup = EmptyRoomSetup()
        XCTAssertTrue(try registry.addForPairing(samsung, roomID: room.id, initialSetup: &setup))
        let assignment = registry.rooms[0]
        XCTAssertFalse(try registry.addForPairing(samsung, roomID: room.id, initialSetup: &setup))
        XCTAssertFalse(try registry.addForPairing(pairingDevice(.appleTV, id: "next"), roomID: room.id, initialSetup: &setup))
        XCTAssertEqual(registry.rooms, [assignment])
        XCTAssertEqual(registry.devices.count, 2)
    }

    func testDuplicateIdentityCannotChangeDeviceTypeOrSavedRoom() throws {
        let saved = pairingDevice(.samsung, id: "saved")
        let room = RoomProfile(id: "living", name: "Living Room", samsungID: saved.id)
        var registry = DeviceRegistry(devices: [saved], rooms: [room])
        let original = registry
        var setup = EmptyRoomSetup()
        XCTAssertThrowsError(try registry.addForPairing(pairingDevice(.appleTV, id: saved.id), roomID: room.id, initialSetup: &setup))
        XCTAssertEqual(registry, original)
    }

    func testMissingRoomRegistersDeviceWithoutChangingAnyAssignments() throws {
        let room = RoomProfile(id: "existing", name: "Existing")
        var registry = DeviceRegistry(rooms: [room])
        var setup = EmptyRoomSetup()
        let samsung = pairingDevice(.samsung, id: "new")
        XCTAssertFalse(try registry.addForPairing(samsung, roomID: "deleted-room", initialSetup: &setup))
        XCTAssertEqual(registry.devices, [samsung])
        XCTAssertEqual(registry.rooms, [room])
    }

    func testEditedRoomSnapshotStopsInitialAutomaticAssignment() throws {
        let room = RoomProfile(id: "empty", name: "New Room")
        var registry = DeviceRegistry(rooms: [room])
        var setup = EmptyRoomSetup()
        XCTAssertTrue(try registry.addForPairing(pairingDevice(.samsung, id: "first"), roomID: room.id, initialSetup: &setup))
        var edited = registry.rooms[0]
        edited.name = "My explicit edit"
        try registry.saveRoom(edited)
        XCTAssertFalse(try registry.addForPairing(pairingDevice(.appleTV, id: "next"), roomID: room.id, initialSetup: &setup))
        XCTAssertEqual(registry.rooms, [edited])
    }

    func testResetAndReloadDoNotTreatSavedPartialRoomAsInitialSetup() throws {
        let room = RoomProfile(id: "empty", name: "New Room")
        var registry = DeviceRegistry(rooms: [room])
        var setup = EmptyRoomSetup()
        XCTAssertTrue(try registry.addForPairing(pairingDevice(.samsung, id: "first"), roomID: room.id, initialSetup: &setup))
        let savedRoom = registry.rooms[0]
        setup.reset()
        registry = try JSONDecoder().decode(DeviceRegistry.self, from: JSONEncoder().encode(registry))
        XCTAssertFalse(try registry.addForPairing(pairingDevice(.appleTV, id: "next"), roomID: room.id, initialSetup: &setup))
        XCTAssertEqual(registry.rooms, [savedRoom])
    }

    func testExplicitRoomSaveCanReplaceAssignmentsAfterPairingNewDevices() throws {
        let living = pairingDevice(.samsung, id: "living")
        let family = pairingDevice(.samsung, id: "family")
        let room = RoomProfile(id: "living-room", name: "Living Room", samsungID: living.id)
        var registry = DeviceRegistry(devices: [living], rooms: [room])
        var setup = EmptyRoomSetup()
        XCTAssertFalse(try registry.addForPairing(family, roomID: room.id, initialSetup: &setup))
        var replacement = room
        replacement.samsungID = family.id
        try registry.saveRoom(replacement)
        XCTAssertEqual(registry.rooms, [replacement])
    }

    func testRoomsResolveIDsInsteadOfDuplicateNames() throws {
        let living = RemoteDevice(kind: .samsung, name: "Samsung", address: "192.168.1.10")
        let bedroom = RemoteDevice(kind: .samsung, name: "Samsung", address: "192.168.1.11")
        var registry = DeviceRegistry(devices: [living, bedroom], rooms: [])
        let room = RoomProfile(name: "Bedroom", samsungID: bedroom.id)
        try registry.saveRoom(room)
        XCTAssertEqual(registry.device(registry.rooms[0].samsungID, kind: .samsung)?.address, bedroom.address)
    }
    func testRoomCannotRouteSamsungControlsToAppleID() throws {
        let apple = RemoteDevice(kind: .appleTV, name: "Apple TV", address: "192.168.1.12")
        var registry = DeviceRegistry(devices: [apple], rooms: [])
        XCTAssertThrowsError(try registry.saveRoom(RoomProfile(name: "Room", samsungID: apple.id)))
        XCTAssertTrue(registry.rooms.isEmpty)
    }
    func testRemovingDeviceClearsAllSavedAssignments() {
        let samsung = RemoteDevice(kind: .samsung, name: "TV", address: "192.168.1.10")
        var registry = DeviceRegistry(devices: [samsung], rooms: [RoomProfile(name: "A", samsungID: samsung.id), RoomProfile(name: "B", samsungID: samsung.id)])
        registry.removeDevice(samsung.id)
        XCTAssertTrue(registry.devices.isEmpty)
        XCTAssertTrue(registry.rooms.allSatisfy { $0.samsungID == nil })
    }
    func testSingleDeviceRoomsAndTemporaryCopyDoNotMutateDefaults() throws {
        let apple = RemoteDevice(kind: .appleTV, name: "Apple TV", address: "192.168.1.12")
        var registry = DeviceRegistry(devices: [apple], rooms: [])
        try registry.saveRoom(RoomProfile(name: "Office", appleID: apple.id))
        var temporary = registry.rooms[0]
        temporary.appleID = nil
        XCTAssertEqual(registry.rooms[0].appleID, apple.id)
        XCTAssertNil(registry.rooms[0].samsungID)
    }
    func testEpochRejectsCallbacksAndCommandsAfterSelectionChange() {
        var epoch = SelectionEpoch()
        let previous = epoch.advance()
        XCTAssertTrue(epoch.accepts(previous))
        _ = epoch.advance()
        XCTAssertFalse(epoch.accepts(previous))
    }

    func testAppleEndpointFollowsSameIdentityAfterDHCPChange() throws {
        let saved = RemoteDevice(id: "apple:living", kind: .appleTV, name: "My room", address: "192.168.1.10", port: 49153, serviceName: "Living")
        let moved = RemoteDevice(id: saved.id, kind: .appleTV, name: "Bonjour label", address: "192.168.1.40", port: 50505, serviceName: "living")
        let resolved = try AppleTVDriver.matchingEndpoint(for: saved, in: [moved])
        XCTAssertEqual(resolved.address, moved.address)
        XCTAssertEqual(resolved.port, moved.port)
        XCTAssertEqual(resolved.name, saved.name)
        XCTAssertEqual(resolved.id, saved.id)
    }

    func testAppleEndpointNeverFallsBackToDifferentOrAmbiguousTV() {
        let saved = RemoteDevice(id: "apple:living", kind: .appleTV, name: "Living", address: "192.168.1.10", port: 49153, serviceName: "Living")
        var other = saved
        other.id = "apple:bedroom"
        XCTAssertThrowsError(try AppleTVDriver.matchingEndpoint(for: saved, in: [other]))
        XCTAssertThrowsError(try AppleTVDriver.matchingEndpoint(for: saved, in: []))
        XCTAssertThrowsError(try AppleTVDriver.matchingEndpoint(for: saved, in: [saved, saved]))
        other = saved
        other.serviceName = "bedroom"
        XCTAssertThrowsError(try AppleTVDriver.matchingEndpoint(for: saved, in: [other]))
    }

    func testRePairAdoptsResetAppleTVOnlyAtSameAddressWhenUnsaved() {
        let saved = RemoteDevice(id: "apple:living", kind: .appleTV, name: "Living", address: "192.168.1.10", port: 49153, serviceName: "Living")
        let reset = RemoteDevice(id: "apple:new-identity", kind: .appleTV, name: "Apple TV", address: saved.address, port: 49154, serviceName: "new-identity")
        let replacement = AppleTVDriver.resetReplacement(for: saved, in: [reset], savedIDs: [saved.id])
        XCTAssertEqual(replacement?.id, reset.id)
        XCTAssertEqual(replacement?.port, reset.port)
        XCTAssertEqual(replacement?.name, saved.name)
        // The same identity still advertising is not a reset.
        XCTAssertNil(AppleTVDriver.resetReplacement(for: saved, in: [saved, reset], savedIDs: [saved.id]))
        // Another saved Apple TV that now holds this address is never taken over.
        XCTAssertNil(AppleTVDriver.resetReplacement(for: saved, in: [reset], savedIDs: [saved.id, reset.id]))
        var elsewhere = reset
        elsewhere.address = "192.168.1.11"
        XCTAssertNil(AppleTVDriver.resetReplacement(for: saved, in: [elsewhere], savedIDs: [saved.id]))
        var second = reset
        second.id = "apple:second"
        XCTAssertNil(AppleTVDriver.resetReplacement(for: saved, in: [reset, second], savedIDs: [saved.id]))
        var manual = saved
        manual.serviceName = nil
        XCTAssertNil(AppleTVDriver.resetReplacement(for: manual, in: [reset], savedIDs: [saved.id]))
    }

    func testReplacingAppleIdentityKeepsNameRoomsAndStars() throws {
        let samsung = pairingDevice(.samsung, id: "samsung:living")
        let old = RemoteDevice(id: "apple:living", kind: .appleTV, name: "Living", address: "192.168.1.10", port: 49153, serviceName: "Living")
        let other = RemoteDevice(id: "apple:bedroom", kind: .appleTV, name: "Bedroom", address: "192.168.1.11", port: 49153, serviceName: "Bedroom")
        let reset = RemoteDevice(id: "apple:new-identity", kind: .appleTV, name: "Apple TV", address: old.address, port: 49154, serviceName: "new-identity")
        let living = RoomProfile(id: "living", name: "Living Room", samsungID: samsung.id, appleID: old.id)
        let bedroom = RoomProfile(id: "bedroom", name: "Bedroom", appleID: other.id)
        var registry = DeviceRegistry(devices: [samsung, old, other], rooms: [living, bedroom], lastRoomID: living.id)
        try registry.setAppStarred(true, appID: "com.example.Player", for: old.id)
        try registry.setAppStarred(true, appID: "com.example.Other", for: other.id)

        try registry.replaceAppleIdentity(old.id, with: reset)

        XCTAssertNil(registry.device(old.id, kind: .appleTV))
        XCTAssertEqual(registry.device(reset.id, kind: .appleTV)?.name, "Living")
        XCTAssertEqual(registry.device(reset.id, kind: .appleTV)?.port, 49154)
        XCTAssertEqual(registry.devices.map(\.id), [samsung.id, reset.id, other.id])
        XCTAssertEqual(registry.rooms[0].appleID, reset.id)
        XCTAssertEqual(registry.rooms[0].samsungID, samsung.id)
        XCTAssertEqual(registry.rooms[1], bedroom)
        XCTAssertEqual(registry.starredAppIDs(for: reset.id), ["com.example.Player"])
        XCTAssertEqual(registry.starredAppIDs(for: other.id), ["com.example.Other"])
        XCTAssertThrowsError(try registry.replaceAppleIdentity(reset.id, with: other))
        XCTAssertThrowsError(try registry.replaceAppleIdentity(samsung.id, with: RemoteDevice(id: "apple:x", kind: .appleTV, name: "X", address: "192.168.1.12")))
    }
}
