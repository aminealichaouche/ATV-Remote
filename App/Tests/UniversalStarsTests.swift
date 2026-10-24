import XCTest
@testable import RoomRemote

final class UniversalStarsTests: XCTestCase {
    private func tv(_ name: String) -> RemoteDevice {
        RemoteDevice(id: "apple:" + name, kind: .appleTV, name: name, address: "192.168.1.30", port: 49153,
                     serviceName: name, serviceType: "_companion-link._tcp", serviceDomain: "local.")
    }
    private var setup: DeviceRegistry { DeviceRegistry(devices: [tv("living"), tv("family")], rooms: []) }
    private func reload(_ registry: DeviceRegistry) throws -> DeviceRegistry {
        try JSONDecoder().decode(DeviceRegistry.self, from: JSONEncoder().encode(registry))
    }

    func testDefaultSharedStarsApplyAcrossTVsButOnlyInstalledAppsBecomeRows() throws {
        var registry = setup
        XCTAssertTrue(registry.universalStarsEnabled)
        try registry.setEffectiveAppStarred(true, appID: "com.example.Player", for: "apple:living")
        try registry.setEffectiveAppStarred(true, appID: "com.example.Absent", for: "apple:family")
        XCTAssertEqual(registry.effectiveStarredAppIDs(for: "apple:living"), registry.effectiveStarredAppIDs(for: "apple:family"))
        let library = AppLibrarySections(apps: [RemoteAppInfo(id: "com.example.Player", name: "Player")], starredIDs: registry.effectiveStarredAppIDs(for: "apple:family"))
        XCTAssertEqual(library.starred.map(\.id), ["com.example.Player"])
        XCTAssertEqual(try reload(registry), registry)
    }

    func testLegacyListsSeedUnionWithoutOverwritingIndividualChoices() throws {
        var old = setup
        try old.setAppStarred(true, appID: "com.example.Living", for: "apple:living")
        try old.setAppStarred(true, appID: "com.example.Family", for: "apple:family")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "universalStarsEnabled"); json.removeValue(forKey: "universalAppFavorites")
        var migrated = try JSONDecoder().decode(DeviceRegistry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(migrated.universalStarsEnabled)
        XCTAssertEqual(migrated.effectiveStarredAppIDs(for: "apple:living"), ["com.example.Living", "com.example.Family"])
        migrated.setUniversalStarsEnabled(false)
        XCTAssertEqual(migrated.effectiveStarredAppIDs(for: "apple:living"), ["com.example.Living"])
        XCTAssertEqual(migrated.effectiveStarredAppIDs(for: "apple:family"), ["com.example.Family"])
    }

    func testModeAndSeparateListsSurviveRepeatedColdRelaunches() throws {
        var registry = setup
        try registry.setAppStarred(true, appID: "com.example.Local", for: "apple:living")
        try registry.setEffectiveAppStarred(true, appID: "com.example.Shared", for: "apple:family")
        let shared = registry.universalStarredAppIDs
        registry.setUniversalStarsEnabled(false)
        try registry.setEffectiveAppStarred(true, appID: "com.example.Family", for: "apple:family")
        registry = try reload(registry)
        XCTAssertFalse(registry.universalStarsEnabled)
        XCTAssertEqual(registry.effectiveStarredAppIDs(for: "apple:family"), ["com.example.Family"])
        registry.setUniversalStarsEnabled(true)
        registry = try reload(registry)
        XCTAssertTrue(registry.universalStarsEnabled)
        XCTAssertEqual(registry.effectiveStarredAppIDs(for: "apple:family"), shared)
    }

    func testRemovingLastSharedStarDoesNotResurrectLegacyStarAfterRelaunch() throws {
        var registry = setup
        try registry.setAppStarred(true, appID: "com.example.Player", for: "apple:living")
        try registry.setEffectiveAppStarred(false, appID: "com.example.Player", for: "apple:family")
        registry = try reload(registry)
        XCTAssertTrue(registry.universalStarredAppIDs.isEmpty)
        registry.setUniversalStarsEnabled(false); registry.setUniversalStarsEnabled(true)
        XCTAssertTrue(try reload(registry).universalStarredAppIDs.isEmpty)
        XCTAssertEqual(registry.starredAppIDs(for: "apple:living"), ["com.example.Player"])
    }

    func testInvalidEditsAreAtomicAndUniversalCapacityAcceptsMigratedUnion() throws {
        var registry = setup
        let before = registry
        XCTAssertThrowsError(try registry.setEffectiveAppStarred(true, appID: "bad id", for: "apple:living"))
        XCTAssertThrowsError(try registry.setEffectiveAppStarred(true, appID: "com.example.App", for: "missing"))
        XCTAssertThrowsError(try registry.replaceUniversalStars(Set((0..<1025).map { "com.example.App\($0)" }), enabled: false))
        XCTAssertEqual(registry, before)
        try registry.replaceUniversalStars(Set((0..<1024).map { "com.example.App\($0)" }), enabled: true)
        XCTAssertEqual(try reload(registry).universalStarredAppIDs.count, 1024)
    }

    func testUniversalTransferRoundTripReviewAndDecliningStarsPreserveReceiver() throws {
        var sender = setup
        try sender.setEffectiveAppStarred(true, appID: "com.example.Shared", for: "apple:living")
        var payload = RoomTransferPayload(version: 3, devices: sender.devices, rooms: [],
            starredApps: ["apple:living": [], "apple:family": []],
            universalStars: SharedUniversalStars(enabled: true, appIDs: sender.universalStarredAppIDs))
        let file = try RoomTransfer.encrypt(payload, code: "cable lunar velvet walnut")
        payload = try RoomTransfer.decrypt(file, code: "cable lunar velvet walnut")
        XCTAssertEqual(payload.sharedStarCount, 1)
        var receiver = setup
        receiver.setUniversalStarsEnabled(false)
        let selected = try payload.selecting(deviceIDs: ["apple:family"], roomIDs: [], includePairings: false)
        let plan = try RoomTransferPlan(payload: selected, existing: receiver)
        XCTAssertTrue(plan.registry.universalStarsEnabled)
        XCTAssertEqual(plan.registry.effectiveStarredAppIDs(for: "apple:living"), ["com.example.Shared"])
        XCTAssertEqual(plan.copiedStarCount, 1)
        let declined = try payload.selecting(deviceIDs: ["apple:family"], roomIDs: [], includePairings: false, includeStars: false)
        XCTAssertNil(declined.universalStars)
        XCTAssertEqual(try RoomTransferPlan(payload: declined, existing: receiver).registry, receiver)
        let samsungOnly = RemoteDevice(id: "samsung", kind: .samsung, name: "TV", address: "192.168.1.20", port: 8002)
        payload.devices.append(samsungOnly)
        XCTAssertNil(try payload.selecting(deviceIDs: [samsungOnly.id], roomIDs: [], includePairings: false).universalStars)
    }

    func testTransferPreservesDisabledModeAndHiddenSharedListAndRejectsBadSchema() throws {
        var payload = RoomTransferPayload(version: 3, devices: setup.devices, rooms: [],
            starredApps: ["apple:living": ["com.example.Local"]],
            universalStars: SharedUniversalStars(enabled: false, appIDs: ["com.example.Shared"]))
        let imported = try RoomTransferPlan(payload: payload, existing: setup).registry
        XCTAssertFalse(imported.universalStarsEnabled)
        XCTAssertEqual(imported.effectiveStarredAppIDs(for: "apple:living"), ["com.example.Local"])
        XCTAssertEqual(imported.universalStarredAppIDs, ["com.example.Shared"])
        payload.version = 2; XCTAssertThrowsError(try payload.validate())
        payload.version = 3; payload.universalStars = SharedUniversalStars(enabled: true, appIDs: ["bad app"])
        XCTAssertThrowsError(try payload.selecting(deviceIDs: [], roomIDs: [], includePairings: false, includeStars: false))
    }

    func testSharedOnlyListStillCountsAsCopiedStarsForSelectedAppleTVs() throws {
        let payload = RoomTransferPayload(version: 3, devices: setup.devices, rooms: [], starredApps: [:],
            universalStars: SharedUniversalStars(enabled: true, appIDs: ["com.example.Shared"]))
        let plan = try RoomTransferPlan(payload: payload, existing: setup)
        XCTAssertEqual(plan.copiedStarTVCount, 2)
        XCTAssertEqual(plan.copiedStarCount, 1)
        XCTAssertEqual(plan.registry.effectiveStarredAppIDs(for: "apple:family"), ["com.example.Shared"])
    }
}
