import Foundation

/// Only include this material in an authenticated, encrypted transfer the user approved.
/// This is a typed Samsung record; it never identifies arbitrary Keychain accounts.
struct SamsungPairingTransfer: Codable, Equatable, Sendable {
    let deviceID: String
    let token: String
    let certificateSHA256: Data
    let clientName: String

    static func validate(_ transfer: SamsungPairingTransfer, for device: RemoteDevice) throws {
        try SamsungPairingTransferValidation.validate(transfer, for: device)
    }
}

enum SamsungPairingTransferValidation {
    enum StorageDecision: Equatable { case insert, alreadyPresent, conflict }

    static func validateDevice(_ device: RemoteDevice) throws {
        guard device.kind == .samsung,
              !device.id.isEmpty, device.id.utf8.count <= 256,
              !device.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              device.address.utf8.count <= 128,
              device.port == nil || device.port == 8002 else {
            throw RemoteFailure.message("The shared Samsung TV record is invalid.")
        }
        _ = try SamsungProtocol.privateHost(device.address)
    }

    static func validate(_ transfer: SamsungPairingTransfer, for device: RemoteDevice) throws {
        try validateDevice(device)
        guard transfer.deviceID == device.id,
              SamsungProtocol.validToken(transfer.token),
              transfer.certificateSHA256.count == 32,
              transfer.clientName == SamsungProtocol.clientName(deviceID: device.id) else {
            throw RemoteFailure.message("The shared Samsung pairing does not match this TV or contains invalid data.")
        }
    }

    static func storageDecision(_ transfer: SamsungPairingTransfer, existingToken: Data?, existingCertificate: Data?) -> StorageDecision {
        if existingToken == nil, existingCertificate == nil { return .insert }
        if existingToken == Data(transfer.token.utf8), existingCertificate == transfer.certificateSHA256 { return .alreadyPresent }
        return .conflict
    }
}
