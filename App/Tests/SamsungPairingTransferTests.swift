import XCTest
@testable import RoomRemote

final class SamsungPairingTransferTests: XCTestCase {
    private let device = RemoteDevice(id: "samsung-bedroom", kind: .samsung, name: "Bedroom", address: "192.168.1.42", port: 8002)

    private func record(deviceID: String = "samsung-bedroom", token: String = "123456789", certificate: Data = Data(repeating: 0xA5, count: 32), clientName: String? = nil) -> SamsungPairingTransfer {
        SamsungPairingTransfer(deviceID: deviceID, token: token, certificateSHA256: certificate,
            clientName: clientName ?? SamsungProtocol.clientName(deviceID: deviceID))
    }

    func testPairingRoundTripsWithStableIdentityAndClientName() throws {
        let pairing = record()
        let decoded = try JSONDecoder().decode(SamsungPairingTransfer.self, from: JSONEncoder().encode(pairing))
        XCTAssertEqual(decoded, pairing)
        XCTAssertNoThrow(try SamsungPairingTransferValidation.validate(decoded, for: device))
        var renamed = device
        renamed.name = "Different room name on another iPhone"
        renamed.address = "192.168.1.73"
        XCTAssertNoThrow(try SamsungPairingTransferValidation.validate(decoded, for: renamed))
    }

    func testPairingCannotBeAppliedToAnotherDeviceOrProtocol() {
        var other = device
        other.id = "samsung-living"
        XCTAssertThrowsError(try SamsungPairingTransferValidation.validate(record(), for: other))
        other = device
        other.kind = .appleTV
        XCTAssertThrowsError(try SamsungPairingTransferValidation.validate(record(), for: other))
        XCTAssertThrowsError(try SamsungPairingTransferValidation.validate(record(clientName: "Another client"), for: device))
    }

    func testImportedPairingNeverAllowsUnsafeEndpoints() {
        for address in ["example.com", "127.0.0.1", "8.8.8.8", "https://192.168.1.2", "192.168.1.2/path"] {
            var invalid = device
            invalid.address = address
            XCTAssertThrowsError(try SamsungPairingTransferValidation.validate(record(), for: invalid))
        }
        var invalid = device
        invalid.port = 8001
        XCTAssertThrowsError(try SamsungPairingTransferValidation.validate(record(), for: invalid))
        invalid = device
        invalid.id = "bad\nid"
        XCTAssertThrowsError(try SamsungPairingTransferValidation.validateDevice(invalid))
    }

    func testMalformedTokenOrCertificateFailsBeforeStorage() {
        for token in ["", "123\n456", String(repeating: "x", count: 2_049)] {
            XCTAssertThrowsError(try SamsungPairingTransferValidation.validate(record(token: token), for: device))
        }
        for size in [0, 31, 33] {
            XCTAssertThrowsError(try SamsungPairingTransferValidation.validate(record(certificate: Data(repeating: 0xA5, count: size)), for: device))
        }
    }

    func testImportAcceptsOnlyEmptyStorageOrAnExactExistingRecord() {
        let pairing = record()
        let token = Data(pairing.token.utf8)
        let certificate = pairing.certificateSHA256
        XCTAssertEqual(SamsungPairingTransferValidation.storageDecision(pairing, existingToken: nil, existingCertificate: nil), .insert)
        // The driver's no-op result is false: callers must exclude this pre-existing
        // record from rollback even when the TV is absent from the local device list.
        XCTAssertEqual(SamsungPairingTransferValidation.storageDecision(pairing, existingToken: token, existingCertificate: certificate), .alreadyPresent)
        XCTAssertEqual(SamsungPairingTransferValidation.storageDecision(pairing, existingToken: token, existingCertificate: nil), .conflict)
        XCTAssertEqual(SamsungPairingTransferValidation.storageDecision(pairing, existingToken: nil, existingCertificate: certificate), .conflict)
        XCTAssertEqual(SamsungPairingTransferValidation.storageDecision(pairing, existingToken: Data("newer-token".utf8), existingCertificate: certificate), .conflict)
        XCTAssertEqual(SamsungPairingTransferValidation.storageDecision(pairing, existingToken: token, existingCertificate: Data(repeating: 0x5A, count: 32)), .conflict)
    }
}
