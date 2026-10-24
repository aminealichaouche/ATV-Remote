import Foundation
import CryptoKit
import SwiftATV
import XCTest
@testable import RoomRemote

final class ApplePairingTransferTests: XCTestCase {
    private let controllerID = "82468016-2381-4F51-AF45-BBD112334455"
    private var device: RemoteDevice {
        RemoteDevice(id: "apple:tv-identity", kind: .appleTV, name: "Living Room",
            address: "192.168.1.10", port: 49153, serviceName: "TV-identity")
    }

    private func fixture() throws -> ApplePairingTransfer {
        // Synthetic keys only; these values do not belong to any real device.
        let accessory = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x11, count: 32))
        let identity = ClientIdentitySettings(name: "Room Remote", macAddress: "02:11:22:33:44:55",
            deviceID: "02:66:77:88:99:AA", pairingIdentifier: controllerID,
            rapportIdentifier: "0123456789ab", operatingSystemVersion: "27.0.0")
        return ApplePairingTransfer(deviceID: device.id, companionServiceIdentity: device.serviceName,
            accessoryIdentifier: Data("accessory-test-id".utf8),
            accessoryPublicKey: accessory.publicKey.rawRepresentation,
            controllerPrivateKey: Data(repeating: 0x22, count: 32),
            controllerIdentifier: Data(controllerID.utf8), clientIdentity: identity)
    }

    private func mutated(_ change: (inout [String: Any]) -> Void) throws -> ApplePairingTransfer {
        let data = try JSONEncoder().encode(fixture())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(ApplePairingTransfer.self,
            from: JSONSerialization.data(withJSONObject: object))
    }

    func testRoundTripPreservesExactTVKeysAndControllerPairingSlot() throws {
        let original = try fixture()
        let copied = try JSONDecoder().decode(ApplePairingTransfer.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(copied, original)
        let validated = try copied.validated(for: device)
        XCTAssertEqual(validated.credentials.ltpk, original.accessoryPublicKey)
        XCTAssertEqual(validated.credentials.ltsk, original.controllerPrivateKey)
        XCTAssertEqual(validated.credentials.atvIdentifier, original.accessoryIdentifier)
        XCTAssertEqual(validated.credentials.clientIdentifier, original.controllerIdentifier)
        XCTAssertEqual(validated.settings.clientIdentity, original.clientIdentity)
        XCTAssertEqual(validated.settings.protocols.companion.identifier, device.serviceName)
        XCTAssertNil(validated.settings.credentials(for: .airPlay))
        XCTAssertNil(validated.settings.credentials(for: .mrp))
    }

    func testOriginalDeviceBindingRejectsAnotherTVAndWrongKind() throws {
        let payload = try fixture()
        var other = device
        other.id = "apple:other-tv"
        XCTAssertThrowsError(try payload.validated(for: other))
        other = device
        other.kind = .samsung
        XCTAssertThrowsError(try payload.validated(for: other))
    }

    func testServiceBindingRejectsChangedOrMissingAdvertisedIdentity() throws {
        let changed = try mutated { $0["companionServiceIdentity"] = "other-tv" }
        XCTAssertThrowsError(try changed.validated(for: device))
        let missing = try mutated { $0.removeValue(forKey: "companionServiceIdentity") }
        XCTAssertThrowsError(try missing.validated(for: device))
    }

    func testUnknownSchemaVersionIsRejected() throws {
        let payload = try mutated { $0["version"] = 2 }
        XCTAssertThrowsError(try payload.validated(for: device))
    }

    func testMissingRequiredIdentityCannotTriggerRandomLibraryDefaults() throws {
        let fields = ["name", "macAddress", "model", "deviceID", "pairingIdentifier",
            "rapportIdentifier", "operatingSystemName", "operatingSystemBuild", "operatingSystemVersion"]
        for field in fields {
            XCTAssertThrowsError(try mutated {
                var identity = $0["clientIdentity"] as! [String: Any]
                identity.removeValue(forKey: field)
                $0["clientIdentity"] = identity
            }, "Missing \(field) must fail instead of constructing defaults")
        }
    }

    func testControllerIdentifierMustMatchCopiedIdentityAndRemainUTF8() throws {
        let mismatched = try mutated { $0["controllerIdentifier"] = Data(UUID().uuidString.utf8).base64EncodedString() }
        XCTAssertThrowsError(try mismatched.validated(for: device))
        let binary = try mutated { $0["controllerIdentifier"] = Data([0xFF, 0xFE]).base64EncodedString() }
        XCTAssertThrowsError(try binary.validated(for: device))
    }

    func testInvalidKeyLengthsAndEmptyPublicKeyAreRejected() throws {
        for field in ["accessoryPublicKey", "controllerPrivateKey"] {
            let payload = try mutated { $0[field] = Data(repeating: 1, count: 31).base64EncodedString() }
            XCTAssertThrowsError(try payload.validated(for: device))
        }
        let zeros = try mutated { $0["accessoryPublicKey"] = Data(count: 32).base64EncodedString() }
        XCTAssertThrowsError(try zeros.validated(for: device))
    }

    func testControllerCannotClaimTheAccessoryIdentity() throws {
        let payload = try mutated { $0["accessoryIdentifier"] = Data(controllerID.utf8).base64EncodedString() }
        XCTAssertThrowsError(try payload.validated(for: device))
    }

    func testControlCharactersAndExcessiveControllerMetadataAreRejected() throws {
        for name in ["Room\nRemote", String(repeating: "x", count: 81)] {
            let payload = try mutated {
                var identity = $0["clientIdentity"] as! [String: Any]
                identity["name"] = name
                $0["clientIdentity"] = identity
            }
            XCTAssertThrowsError(try payload.validated(for: device))
        }
    }

    func testMalformedRapportOrMACIdentifierIsRejected() throws {
        for field in ["rapportIdentifier", "macAddress", "deviceID"] {
            let payload = try mutated {
                var identity = $0["clientIdentity"] as! [String: Any]
                identity[field] = "malformed"
                $0["clientIdentity"] = identity
            }
            XCTAssertThrowsError(try payload.validated(for: device))
        }
    }
}
