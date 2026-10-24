import XCTest
@testable import RoomRemote

final class SetupUsabilityTests: XCTestCase {
    private var tv: RemoteDevice {
        RemoteDevice(id: "apple:living", kind: .appleTV, name: "Living", address: "192.168.1.30", port: 49153,
            serviceName: "living", serviceType: "_companion-link._tcp", serviceDomain: "local.")
    }

    func testXfinityUsesExactBundleIDRatherThanRenamingOtherStreamApps() {
        XCTAssertEqual(RemoteAppInfo(id: "com.comcast.cim.x2", name: "Stream").name, "Xfinity Stream")
        XCTAssertEqual(RemoteAppInfo(id: "com.example.Stream", name: "Stream").name, "Stream")
    }

    func testSearchFiltersAllSectionsWithoutLosingStarsOrInventingMissingApps() {
        let apps = [RemoteAppInfo(id: "com.comcast.cim.x2", name: "Stream"),
                    RemoteAppInfo(id: "com.example.Stream", name: "Stream"),
                    RemoteAppInfo(id: "com.apple.TVMusic", name: "Music")]
        let stars: Set<String> = ["com.comcast.cim.x2", "com.example.Missing"]
        let filtered = AppLibrarySections(apps: apps, starredIDs: stars, search: "  XFINITY  ")
        XCTAssertEqual(filtered.starred.map(\.id), ["com.comcast.cim.x2"])
        XCTAssertTrue(filtered.downloaded.isEmpty); XCTAssertTrue(filtered.included.isEmpty)
        XCTAssertEqual(AppLibrarySections(apps: apps, starredIDs: stars, search: "stream").downloaded.map(\.id), ["com.example.Stream"])
        XCTAssertEqual(AppLibrarySections(apps: apps, starredIDs: stars, search: "music").included.map(\.id), ["com.apple.TVMusic"])
        XCTAssertTrue(AppLibrarySections(apps: apps, starredIDs: stars, search: "missing").starred.isEmpty)
    }

    func testSavedEndpointFallbackRequiresExplicitPermissionAndStillPrefersBonjour() throws {
        XCTAssertThrowsError(try AppleTVDriver.matchingEndpoint(for: tv, in: []))
        XCTAssertEqual(try AppleTVDriver.matchingEndpoint(for: tv, in: [], allowSavedEndpoint: true), tv)
        var moved = tv; moved.address = "192.168.1.50"; moved.port = 50000
        XCTAssertEqual(try AppleTVDriver.matchingEndpoint(for: tv, in: [moved], allowSavedEndpoint: true), moved)
        XCTAssertThrowsError(try AppleTVDriver.matchingEndpoint(for: tv, in: [moved, moved], allowSavedEndpoint: true))
    }

    func testRoomlessImportKeepsReceiverRoomsAndTransfersExactStarsAfterEncryption() throws {
        let source = RoomTransferPayload(version: 2, devices: [tv], rooms: [RoomProfile(id: "sender", name: "Sender Room", appleID: tv.id)],
            starredApps: [tv.id: ["com.comcast.cim.x2", "com.example.Missing"]],
            remotePreferences: SharedRemotePreferences(layout: .expandedAppleTVRemote, useTouchpad: true))
        let encrypted = try RoomTransfer.encrypt(source, code: "cable lunar velvet walnut")
        let decoded = try RoomTransfer.decrypt(encrypted, code: "cable lunar velvet walnut").deviceSetupOnly()
        XCTAssertTrue(decoded.rooms.isEmpty)
        let receiver = DeviceRegistry(devices: [tv], rooms: [RoomProfile(id: "receiver", name: "Receiver Room", appleID: tv.id)])
        let plan = try RoomTransferPlan(payload: decoded, existing: receiver)
        XCTAssertEqual(plan.registry.rooms, receiver.rooms)
        XCTAssertEqual(plan.registry.starredAppIDs(for: tv.id), source.starredApps?[tv.id])
        XCTAssertEqual(decoded.remotePreferences, source.remotePreferences)
        XCTAssertEqual(source.rooms.count, 1)
    }

    func testDroppedLegacyRoomsAreValidatedAndRoomsOnlyFilesGiveAnActionableError() throws {
        let roomOnly = RoomTransferPayload(devices: [], rooms: [RoomProfile(name: "Old room")])
        XCTAssertThrowsError(try roomOnly.deviceSetupOnly()) { XCTAssertTrue($0.localizedDescription.contains("only rooms")) }
        let malformed = RoomTransferPayload(devices: [tv], rooms: [RoomProfile(name: "Invalid", appleID: "unknown")])
        XCTAssertThrowsError(try malformed.deviceSetupOnly())
    }

    func testDeletingEveryRoomCanPersistWithoutLosingTVsAndStars() throws {
        var registry = DeviceRegistry(devices: [tv], rooms: [])
        try registry.setAppStarred(true, appID: "com.comcast.cim.x2", for: tv.id)
        let decoded = try JSONDecoder().decode(DeviceRegistry.self, from: JSONEncoder().encode(registry))
        XCTAssertTrue(decoded.rooms.isEmpty)
        XCTAssertEqual(decoded.devices, [tv])
        XCTAssertEqual(decoded.starredAppIDs(for: tv.id), ["com.comcast.cim.x2"])
    }
}
