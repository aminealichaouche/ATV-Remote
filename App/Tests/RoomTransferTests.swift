import XCTest
@testable import RoomRemote

final class RoomTransferTests: XCTestCase {
    private let code = "cable lunar velvet walnut"
    private var fixture: RoomTransferPayload {
        RoomTransferPayload(devices: [RemoteDevice(id: "samsung-fixture", kind: .samsung, name: "Living TV", address: "192.168.1.20", port: 8002)], rooms: [RoomProfile(id: "living", name: "Living Room", samsungID: "samsung-fixture")])
    }

    func testSamsungWakeMACSharesInVersionTwoEnvelopeWithoutChangingPayloadOrPairingIdentity() throws {
        var payload = fixture
        payload.devices[0].wakeMACAddress = "02:11:22:33:44:66"
        payload.samsungPairings = [SamsungPairingTransfer(deviceID: payload.devices[0].id, token: "fake-shared-token", certificateSHA256: Data(repeating: 1, count: 32), clientName: SamsungProtocol.clientName(deviceID: payload.devices[0].id))]
        let file = try RoomTransfer.encrypt(payload, code: code)
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("02:11:22:33:44:66"))
        let decoded = try RoomTransfer.decrypt(file, code: code)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.devices, payload.devices)
        XCTAssertEqual(decoded.rooms, payload.rooms)
        XCTAssertEqual(decoded.samsungPairings, payload.samsungPairings)
        XCTAssertEqual(decoded.samsungPairings[0].deviceID, payload.devices[0].id)
    }

    func testLegacyVersionOnePayloadWithoutWakeMACStillImports() throws {
        let legacyJSON = try JSONEncoder().encode(fixture)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyJSON) as? [String: Any])
        let devices = try XCTUnwrap(object["devices"] as? [[String: Any]])
        XCTAssertNil(devices[0]["wakeMACAddress"])
        let decoded = try JSONDecoder().decode(RoomTransferPayload.self, from: legacyJSON)
        try decoded.validate()
        XCTAssertNil(decoded.devices[0].wakeMACAddress)
        let file = try RoomTransfer.encrypt(decoded, code: code)
        let oldSetup = try RoomTransfer.decrypt(file, code: code)
        let plan = try RoomTransferPlan(payload: oldSetup, existing: DeviceRegistry(devices: [], rooms: []))
        XCTAssertEqual(plan.registry.devices, fixture.devices)
        XCTAssertEqual(plan.registry.rooms, fixture.rooms)
        XCTAssertNil(plan.registry.devices[0].wakeMACAddress)
    }

    func testNewSharedSamsungKeepsWakeMACOnItsOwnSavedIdentity() throws {
        var payload = fixture
        payload.devices[0].wakeMACAddress = "02:11:22:33:44:66"
        let plan = try RoomTransferPlan(payload: payload, existing: DeviceRegistry(devices: [], rooms: []))
        XCTAssertEqual(plan.newDevices, payload.devices)
        XCTAssertEqual(plan.registry.devices[0].id, payload.devices[0].id)
        XCTAssertEqual(plan.registry.devices[0].wakeMACAddress, payload.devices[0].wakeMACAddress)
        XCTAssertEqual(plan.registry.rooms[0].samsungID, payload.devices[0].id)
        let repeated = try RoomTransferPlan(payload: payload, existing: plan.registry)
        XCTAssertEqual(repeated.registry, plan.registry)
        XCTAssertTrue(repeated.newDevices.isEmpty)
    }

    func testReusedSharedSamsungPreservesItsExistingWakeMACAndPairing() throws {
        for savedMAC in [nil, "02:11:22:33:44:88"] as [String?] {
            var saved = fixture.devices[0]
            saved.name = "My custom TV"
            saved.wakeMACAddress = savedMAC
            var payload = fixture
            payload.devices[0].wakeMACAddress = "02:11:22:33:44:66"
            payload.samsungPairings = [SamsungPairingTransfer(deviceID: saved.id, token: "fake-shared-token", certificateSHA256: Data(repeating: 1, count: 32), clientName: SamsungProtocol.clientName(deviceID: saved.id))]
            let existing = DeviceRegistry(devices: [saved], rooms: fixture.rooms)
            let plan = try RoomTransferPlan(payload: payload, existing: existing)
            XCTAssertEqual(plan.registry, existing)
            XCTAssertEqual(plan.registry.devices[0].wakeMACAddress, savedMAC)
            XCTAssertTrue(plan.newDevices.isEmpty)
            XCTAssertTrue(plan.samsungPairings.isEmpty)
            XCTAssertEqual(plan.reusedDeviceCount, 1)
        }
    }

    func testSharedWakeMACRejectsInvalidSamsungAndAnyAppleMetadataBeforeEncryption() {
        for invalidMAC in ["", "bad", "02:11:22:33:44:GG", "00:00:00:00:00:00", "01:11:22:33:44:66"] {
            var payload = fixture
            payload.devices[0].wakeMACAddress = invalidMAC
            XCTAssertThrowsError(try payload.validate(), invalidMAC)
            XCTAssertThrowsError(try RoomTransfer.encrypt(payload, code: code), invalidMAC)
        }
        let apple = RemoteDevice(id: "apple:fixture", kind: .appleTV, name: "Apple TV", address: "192.168.1.30", port: 49153,
            serviceName: "Fixture", serviceType: "_companion-link._tcp", serviceDomain: "local.", wakeMACAddress: "02:11:22:33:44:66")
        let payload = RoomTransferPayload(devices: [apple], rooms: [RoomProfile(id: "apple-room", name: "Apple Room", appleID: apple.id)])
        XCTAssertThrowsError(try payload.validate())
        XCTAssertThrowsError(try RoomTransfer.encrypt(payload, code: code))
    }

    func testEncryptedRoundTripHasNoPlainDeviceMetadata() throws {
        let file = try RoomTransfer.encrypt(fixture, code: code)
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("Living TV"))
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("192.168.1.20"))
        let decoded = try RoomTransfer.decrypt(file, code: code)
        XCTAssertEqual(decoded.devices, fixture.devices)
        XCTAssertEqual(decoded.rooms, fixture.rooms)
    }

    func testGeneratedCodesRoundTripAndAreDistinct() throws {
        var codes = Set<String>()
        for _ in 0..<12 {
            let generated = try RoomTransfer.makeCode()
            XCTAssertEqual(generated.split(separator: " ").count, 4)
            XCTAssertLessThanOrEqual(generated.count, 39)
            let file = try RoomTransfer.encrypt(fixture, code: generated)
            XCTAssertEqual(try RoomTransfer.decrypt(file, code: generated.uppercased().replacingOccurrences(of: " ", with: "-")).devices, fixture.devices)
            codes.insert(generated)
        }
        XCTAssertEqual(codes.count, 12)
    }

    func testWrongMalformedAndShortCodesReject() throws {
        let file = try RoomTransfer.encrypt(fixture, code: code)
        for wrong in ["cable lunar velvet cable", "cable lunar velvet", "notaword lunar velvet walnut", String(repeating: "a", count: 200), String(repeating: "0", count: 32)] {
            XCTAssertThrowsError(try RoomTransfer.decrypt(file, code: wrong))
        }
    }

    func testCiphertextSaltAndVersionTamperingReject() throws {
        let file = try RoomTransfer.encrypt(fixture, code: code)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: file) as? [String: Any])
        for field in ["salt", "sealed"] {
            var changed = original
            var bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(changed[field] as? String)))
            bytes[0] ^= 1
            changed[field] = bytes.base64EncodedString()
            XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: changed), code: code))
        }
        var changed = original; changed["version"] = 3
        XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: changed), code: code))
    }

    func testEmptyOversizedAndDeepFilesReject() {
        for file in [Data(), Data(repeating: 32, count: RoomTransfer.maximumFileBytes + 1), Data((String(repeating: "[", count: 100) + String(repeating: "]", count: 100)).utf8)] {
            XCTAssertThrowsError(try RoomTransfer.decrypt(file, code: code))
        }
    }

    func testMalformedAndUnsupportedPayloadsRejectBeforeEncryption() {
        var payload = fixture; payload.version = 4
        XCTAssertThrowsError(try RoomTransfer.encrypt(payload, code: code))
        payload = fixture; payload.devices.append(payload.devices[0])
        XCTAssertThrowsError(try payload.validate())
        payload = fixture; payload.rooms[0].appleID = payload.devices[0].id
        XCTAssertThrowsError(try payload.validate())
        payload = fixture; payload.devices[0].address = "8.8.8.8"
        XCTAssertThrowsError(try payload.validate())
        payload = fixture; payload.devices[0].port = 8001
        XCTAssertThrowsError(try payload.validate())
        payload = fixture; payload.rooms[0].samsungID = "missing"
        XCTAssertThrowsError(try payload.validate())
    }

    func testEntryLimitsAndControlCharactersReject() {
        var payload = fixture
        payload.rooms = (0..<65).map { RoomProfile(id: "\($0)", name: "Room \($0)") }
        XCTAssertThrowsError(try payload.validate())
        payload = fixture; payload.devices[0].name = "TV\nName"
        XCTAssertThrowsError(try payload.validate())
        payload = fixture; payload.devices[0].name = "T" + String(repeating: "\u{0301}", count: 1000)
        XCTAssertThrowsError(try payload.validate())
    }

    func testJSONStringBracesAreNotCountedAsNestedObjects() throws {
        var payload = fixture; payload.devices[0].name = "TV { [ \\ \" room"
        let file = try RoomTransfer.encrypt(payload, code: code)
        XCTAssertEqual(try RoomTransfer.decrypt(file, code: code).devices[0].name, payload.devices[0].name)
    }

    func testImportPreservesSavedIdentityNameAndPairing() throws {
        var original = fixture.devices[0]; original.name = "My custom name"
        var payload = fixture
        payload.samsungPairings = [SamsungPairingTransfer(deviceID: original.id, token: "fake-shared-token", certificateSHA256: Data(repeating: 1, count: 32), clientName: SamsungProtocol.clientName(deviceID: original.id))]
        let plan = try RoomTransferPlan(payload: payload, existing: DeviceRegistry(devices: [original], rooms: []))
        XCTAssertTrue(plan.newDevices.isEmpty)
        XCTAssertTrue(plan.samsungPairings.isEmpty)
        XCTAssertEqual(plan.registry.devices[0].name, original.name)
        XCTAssertEqual(plan.reusedDeviceCount, 1)
    }

    func testImportNeverMatchesDifferentTVIdentitiesByIPAddress() throws {
        var existing = fixture.devices[0]; existing.id = "different-tv-same-address"
        let plan = try RoomTransferPlan(payload: fixture, existing: DeviceRegistry(devices: [existing], rooms: []))
        XCTAssertEqual(plan.newDevices.map(\.id), [fixture.devices[0].id])
        XCTAssertEqual(plan.registry.rooms[0].samsungID, fixture.devices[0].id)
    }

    func testIdentityConflictRejectsWithoutChangingExistingRegistry() {
        var existing = fixture.devices[0]; existing.address = "192.168.1.99"
        let registry = DeviceRegistry(devices: [existing], rooms: [])
        XCTAssertThrowsError(try RoomTransferPlan(payload: fixture, existing: registry))
        XCTAssertEqual(registry.devices[0].address, "192.168.1.99")
    }

    func testRepeatedImportDoesNotDuplicateIdenticalRoomsAndDevices() throws {
        let first = try RoomTransferPlan(payload: fixture, existing: DeviceRegistry())
        let second = try RoomTransferPlan(payload: fixture, existing: first.registry)
        XCTAssertTrue(second.newDevices.isEmpty)
        XCTAssertEqual(second.addedRoomCount, 0)
        XCTAssertEqual(first.registry, second.registry)
    }

    func testConflictingRoomCopyAlsoRemainsIdempotent() throws {
        var other = fixture.devices[0]; other.id = "other-tv"; other.address = "192.168.1.30"
        let registry = DeviceRegistry(devices: [other], rooms: [RoomProfile(id: "living", name: "My room", samsungID: other.id)])
        let first = try RoomTransferPlan(payload: fixture, existing: registry)
        let second = try RoomTransferPlan(payload: fixture, existing: first.registry)
        XCTAssertEqual(first.registry.rooms.count, 2)
        XCTAssertEqual(first.registry.rooms[0].name, "My room")
        XCTAssertEqual(first.registry, second.registry)
        XCTAssertEqual(second.addedRoomCount, 0)
    }

    func testVersionTwoEnvelopeDeclaresFixedKDFAndFreshSalt() throws {
        let first = try RoomTransfer.encrypt(fixture, code: code)
        let second = try RoomTransfer.encrypt(fixture, code: code)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        let other = try XCTUnwrap(JSONSerialization.jsonObject(with: second) as? [String: Any])
        XCTAssertEqual(envelope["format"] as? String, "roomremote")
        XCTAssertEqual(envelope["version"] as? Int, 2)
        XCTAssertEqual(envelope["kdf"] as? String, "pbkdf2-sha256")
        XCTAssertEqual(envelope["iterations"] as? Int, 600_000)
        XCTAssertEqual(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(envelope["salt"] as? String))).count, 16)
        XCTAssertNotEqual(envelope["salt"] as? String, other["salt"] as? String)
        XCTAssertNotEqual(envelope["sealed"] as? String, other["sealed"] as? String)
        XCTAssertEqual(try RoomTransfer.decrypt(first, code: "  CABLE\tLUNAR-velvet\nwalnut  ").devices, fixture.devices)
    }

    func testIndependentLegacyVersionOneEnvelopeStillDecrypts() throws {
        // Independently generated with Python cryptography, the original v1 HKDF info,
        // 20 zero code bytes, salt 01...10, and nonce 01...0c; never made by current encrypt.
        let file = Data(#"{"format":"roomremote","version":1,"salt":"AQIDBAUGBwgJCgsMDQ4PEA==","sealed":"AQIDBAUGBwgJCgsM0PeCHs2cJ0Avpi+3BBJgD2w+XFX7Pbs9yHdsqfxeNuNNmKqxv4QlDOr0fLki+xR0PyoZWrc8V07RVkR9Es8wHg3549pcGI0sHZMQ2O6ACFyPdWPu4sbBixEfRPLhzzhTV2P1SuxPjQiOTM7d5/27y2bK/UoY3AiM6EtzDoeTrQD7LBqlVsLd+ODcqlqkcHCg8CNvgVySpuF4crKXOx72VGAcvecrqeqNaQgNgd7hl26kWoDlcNvQTSMl26aonal9A+k37tscAzOcNBIUHf2cehwWRStGolBhyajF0h77A6Q8Qp+w0Z1CAOOIEd00Y3gQ8sT/h9Lti4aPLV13HLUccA=="}"#.utf8)
        let payload = try RoomTransfer.decrypt(file, code: String(repeating: "0", count: 32))
        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(payload.devices, fixture.devices)
        XCTAssertEqual(payload.rooms, fixture.rooms)
        XCTAssertThrowsError(try RoomTransfer.decrypt(file, code: code))
        XCTAssertThrowsError(try RoomTransfer.decrypt(file, code: String(repeating: "1", count: 32)))
        XCTAssertThrowsError(try RoomTransfer.encrypt(fixture, code: String(repeating: "0", count: 32)))
    }

    func testVersionTwoRejectsMissingNullMalformedAndUntrustedKDFFactors() throws {
        let file = try RoomTransfer.encrypt(fixture, code: code)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: file) as? [String: Any])
        for field in ["kdf", "iterations"] {
            var absent = original
            absent.removeValue(forKey: field)
            XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: absent), code: code), field)
            var null = original
            null[field] = NSNull()
            XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: null), code: code), field)
        }
        for cost: Any in [0, -1, 599_999, 600_001, 2_147_483_647, "600000", true, 600_000.5] {
            var changed = original
            changed["iterations"] = cost
            XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: changed), code: code), "\(cost)")
        }
        for algorithm: Any in ["hkdf-sha256", "PBKDF2-SHA256", "pbkdf2-sha1", 600_000] {
            var changed = original
            changed["kdf"] = algorithm
            XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: changed), code: code), "\(algorithm)")
        }
    }

    func testEnvelopeDowngradeAndLegacyKDFConfusionReject() throws {
        let phraseFile = try RoomTransfer.encrypt(fixture, code: code)
        var downgraded = try XCTUnwrap(JSONSerialization.jsonObject(with: phraseFile) as? [String: Any])
        downgraded["version"] = 1
        XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: downgraded), code: String(repeating: "0", count: 32)))
        downgraded.removeValue(forKey: "kdf")
        downgraded.removeValue(forKey: "iterations")
        XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: downgraded), code: String(repeating: "0", count: 32)))
        let old = Data(#"{"format":"roomremote","version":1,"salt":"AQIDBAUGBwgJCgsMDQ4PEA==","sealed":"AQIDBAUGBwgJCgsM0PeCHs2cJ0Avpi+3BBJgD2w+XFX7Pbs9yHdsqfxeNuNNmKqxv4QlDOr0fLki+xR0PyoZWrc8V07RVkR9Es8wHg3549pcGI0sHZMQ2O6ACFyPdWPu4sbBixEfRPLhzzhTV2P1SuxPjQiOTM7d5/27y2bK/UoY3AiM6EtzDoeTrQD7LBqlVsLd+ODcqlqkcHCg8CNvgVySpuF4crKXOx72VGAcvecrqeqNaQgNgd7hl26kWoDlcNvQTSMl26aonal9A+k37tscAzOcNBIUHf2cehwWRStGolBhyajF0h77A6Q8Qp+w0Z1CAOOIEd00Y3gQ8sT/h9Lti4aPLV13HLUccA=="}"#.utf8)
        let legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        for field in ["kdf", "iterations"] {
            var changed = legacy
            changed[field] = NSNull()
            XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: changed), code: String(repeating: "0", count: 32)), field)
        }
        var upgraded = legacy
        upgraded["version"] = 2
        upgraded["kdf"] = "pbkdf2-sha256"
        upgraded["iterations"] = 600_000
        XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: upgraded), code: code))
    }

    func testMalformedEnvelopeSaltAndSealedBoundsReject() throws {
        let file = try RoomTransfer.encrypt(fixture, code: code)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: file) as? [String: Any])
        for salt in [Data(), Data(repeating: 1, count: 15), Data(repeating: 1, count: 17)] {
            var changed = original
            changed["salt"] = salt.base64EncodedString()
            XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: changed), code: code))
        }
        for sealed in [Data(), Data(repeating: 1, count: 27), Data(repeating: 1, count: RoomTransfer.maximumFileBytes / 2 + 29)] {
            var changed = original
            changed["sealed"] = sealed.base64EncodedString()
            XCTAssertThrowsError(try RoomTransfer.decrypt(JSONSerialization.data(withJSONObject: changed), code: code))
        }
    }
}
