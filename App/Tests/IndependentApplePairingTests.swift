import XCTest
import CryptoKit
import SwiftATV
@testable import RoomRemote

final class IndependentApplePairingTests: XCTestCase {
    private func legacyPayload(version: Int = 2) throws -> RoomTransferPayload {
        let apple = RemoteDevice(id: "apple:legacy-living", kind: .appleTV, name: "Living Apple TV", address: "192.168.1.30", port: 49153,
            serviceName: "legacy-living", serviceType: "_companion-link._tcp", serviceDomain: "local.")
        let samsung = RemoteDevice(id: "legacy-samsung", kind: .samsung, name: "Living TV", address: "192.168.1.20", port: 8002,
            wakeMACAddress: "02:11:22:33:44:66")
        let controllerID = "82468016-2381-4F51-AF45-BBD112334455"
        let identity = ClientIdentitySettings(name: "Synthetic sender", macAddress: "02:11:22:33:44:55", deviceID: "02:66:77:88:99:AA",
            pairingIdentifier: controllerID, rapportIdentifier: "0123456789ab", operatingSystemVersion: "27.0.0")
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x11, count: 32))
        let pairing = ApplePairingTransfer(deviceID: apple.id, companionServiceIdentity: apple.serviceName,
            accessoryIdentifier: Data("synthetic-accessory".utf8), accessoryPublicKey: key.publicKey.rawRepresentation,
            controllerPrivateKey: Data(repeating: 0x22, count: 32), controllerIdentifier: Data(controllerID.utf8), clientIdentity: identity)
        return RoomTransferPayload(version: version, devices: [apple, samsung],
            rooms: [RoomProfile(id: "legacy-room", name: "Living Room", samsungID: samsung.id, appleID: apple.id)],
            applePairings: [pairing], samsungPairings: [SamsungPairingTransfer(deviceID: samsung.id, token: "synthetic-only",
                certificateSHA256: Data(repeating: 1, count: 32), clientName: SamsungProtocol.clientName(deviceID: samsung.id))],
            starredApps: version == 2 ? [apple.id: ["com.example.Player", "com.example.Missing"]] : nil,
            remotePreferences: version == 2 ? SharedRemotePreferences(layout: .expandedAppleTVRemote, useTouchpad: true) : nil)
    }

    func testLegacyFilesKeepSetupAndSamsungAccessWithoutInstallingAppleIdentity() throws {
        for version in [1, 2] {
            let payload = try legacyPayload(version: version)
            let encrypted = try RoomTransfer.encrypt(payload, code: "cable lunar velvet walnut")
            let decoded = try RoomTransfer.decrypt(encrypted, code: "cable lunar velvet walnut")
            XCTAssertEqual(decoded.applePairings.count, 1, "Legacy data is decoded and validated before filtering")
            let plan = try RoomTransferPlan(payload: decoded, existing: DeviceRegistry(rooms: []))
            XCTAssertTrue(plan.applePairings.isEmpty, "Commit must reject copied controller identities even without UI selection")
            XCTAssertEqual(plan.samsungPairings, payload.samsungPairings)
            XCTAssertEqual(plan.registry.devices, payload.devices)
            XCTAssertEqual(plan.registry.rooms, payload.rooms)
            XCTAssertEqual(plan.registry.starredAppIDs(for: "apple:legacy-living"), payload.starredApps?["apple:legacy-living"] ?? [])
            XCTAssertEqual(decoded.remotePreferences, payload.remotePreferences)
        }
    }

    func testReviewAndSelectionAgreeThatAppleRequiresItsOwnPairing() throws {
        let payload = try legacyPayload()
        let review = try RoomTransferReview(payload: payload, existing: DeviceRegistry(rooms: []))
        XCTAssertFalse(try XCTUnwrap(review.devices.first { $0.device.kind == .appleTV }).hasSharedAccess)
        XCTAssertTrue(try XCTUnwrap(review.devices.first { $0.device.kind == .samsung }).hasSharedAccess)
        let selected = try payload.selecting(deviceIDs: review.selectableDeviceIDs, roomIDs: ["legacy-room"], includePairings: true)
        XCTAssertTrue(selected.applePairings.isEmpty)
        XCTAssertEqual(selected.samsungPairings, payload.samsungPairings)
        XCTAssertEqual(selected.rooms, payload.rooms)
        XCTAssertEqual(selected.starredApps, payload.starredApps)
        XCTAssertEqual(selected.remotePreferences, payload.remotePreferences)
        XCTAssertEqual(payload.applePairings.count, 1, "Preview does not mutate the source")
    }

    func testSamsungAccessCanStillBeDeclinedWithoutLosingRoomOrStars() throws {
        let payload = try legacyPayload()
        let selected = try payload.selecting(deviceIDs: Set(payload.devices.map(\.id)), roomIDs: ["legacy-room"], includePairings: false)
        XCTAssertTrue(selected.applePairings.isEmpty)
        XCTAssertTrue(selected.samsungPairings.isEmpty)
        XCTAssertEqual(selected.rooms, payload.rooms)
        XCTAssertEqual(selected.starredApps, payload.starredApps)
    }

    func testExistingTVsAreNotReplacedAndReceiveNoCopiedCredentials() throws {
        let payload = try legacyPayload()
        var existing = DeviceRegistry(devices: payload.devices, rooms: payload.rooms)
        existing.devices[0].name = "My Apple TV"
        existing.devices[0].address = "192.168.1.40"
        let plan = try RoomTransferPlan(payload: payload, existing: existing)
        XCTAssertTrue(plan.newDevices.isEmpty)
        XCTAssertTrue(plan.applePairings.isEmpty)
        XCTAssertTrue(plan.samsungPairings.isEmpty)
        XCTAssertEqual(plan.registry.devices, existing.devices)
        XCTAssertEqual(plan.registry.rooms, existing.rooms)
        XCTAssertEqual(plan.registry.starredAppIDs(for: "apple:legacy-living"), payload.starredApps?["apple:legacy-living"])
    }

    func testMalformedLegacyAppleSecretsCannotHideBehindIgnoredAccess() throws {
        var payload = try legacyPayload()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload.applePairings[0])) as? [String: Any])
        object["controllerPrivateKey"] = Data(repeating: 1, count: 3).base64EncodedString()
        payload.applePairings = [try JSONDecoder().decode(ApplePairingTransfer.self, from: JSONSerialization.data(withJSONObject: object))]
        XCTAssertThrowsError(try RoomTransferPlan(payload: payload, existing: DeviceRegistry()))
        XCTAssertThrowsError(try payload.selecting(deviceIDs: ["legacy-samsung"], roomIDs: [], includePairings: false))
        XCTAssertThrowsError(try RoomTransferReview(payload: payload, existing: DeviceRegistry()))
    }
}
