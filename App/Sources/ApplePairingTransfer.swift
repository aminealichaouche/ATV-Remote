import Foundation
import CryptoKit
import SwiftATV

/// Secret owner-to-owner transfer payload. The enclosing export must be encrypted
/// and authenticated; this type is never written as an unencrypted share file.
/// Credentials intentionally preserve the TV's existing controller pairing slot.
struct ApplePairingTransfer: Codable, Hashable, Sendable {
    let version: Int
    let deviceID: String
    let companionServiceIdentity: String?
    let accessoryIdentifier: Data
    let accessoryPublicKey: Data
    let controllerPrivateKey: Data
    let controllerIdentifier: Data
    let clientIdentity: ClientIdentitySettings

    init(version: Int = 1, deviceID: String, companionServiceIdentity: String?,
         accessoryIdentifier: Data, accessoryPublicKey: Data,
         controllerPrivateKey: Data, controllerIdentifier: Data,
         clientIdentity: ClientIdentitySettings) {
        self.version = version
        self.deviceID = deviceID
        self.companionServiceIdentity = companionServiceIdentity
        self.accessoryIdentifier = accessoryIdentifier
        self.accessoryPublicKey = accessoryPublicKey
        self.controllerPrivateKey = controllerPrivateKey
        self.controllerIdentifier = controllerIdentifier
        self.clientIdentity = clientIdentity
    }

    private enum CodingKeys: String, CodingKey {
        case version, deviceID, companionServiceIdentity, accessoryIdentifier
        case accessoryPublicKey, controllerPrivateKey, controllerIdentifier, clientIdentity
    }

    private enum ControllerKeys: String, CodingKey, CaseIterable {
        case name, macAddress, model, deviceID, pairingIdentifier, rapportIdentifier
        case operatingSystemName, operatingSystemBuild, operatingSystemVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let controller = try container.nestedContainer(keyedBy: ControllerKeys.self, forKey: .clientIdentity)
        for key in ControllerKeys.allCases {
            guard controller.contains(key), try !controller.decodeNil(forKey: key) else {
                throw DecodingError.keyNotFound(key,
                    .init(codingPath: controller.codingPath,
                          debugDescription: "Apple TV transfer is missing required controller identity metadata."))
            }
        }
        version = try container.decode(Int.self, forKey: .version)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        companionServiceIdentity = try container.decodeIfPresent(String.self, forKey: .companionServiceIdentity)
        accessoryIdentifier = try container.decode(Data.self, forKey: .accessoryIdentifier)
        accessoryPublicKey = try container.decode(Data.self, forKey: .accessoryPublicKey)
        controllerPrivateKey = try container.decode(Data.self, forKey: .controllerPrivateKey)
        controllerIdentifier = try container.decode(Data.self, forKey: .controllerIdentifier)
        clientIdentity = try container.decode(ClientIdentitySettings.self, forKey: .clientIdentity)
    }

    struct ValidatedPairing: Sendable {
        let credentials: HAPCredentials
        let settings: ATVSettings
    }

    /// Pure validation: performs no Keychain, network, or app-state operations.
    static func validate(_ transfer: ApplePairingTransfer, for device: RemoteDevice) throws {
        _ = try transfer.validated(for: device)
    }

    func validated(for device: RemoteDevice) throws -> ValidatedPairing {
        guard version == 1, device.kind == .appleTV, deviceID == device.id,
              Self.validText(deviceID, maximumBytes: 512),
              companionServiceIdentity?.lowercased() == device.serviceName?.lowercased() else {
            throw RemoteFailure.message("This Apple TV pairing transfer does not match the saved TV or transfer version.")
        }
        if let companionServiceIdentity,
           !Self.validText(companionServiceIdentity, maximumBytes: 256) {
            throw RemoteFailure.message("The Apple TV transfer contains an invalid Companion identity.")
        }
        guard !accessoryIdentifier.isEmpty, accessoryIdentifier.count <= 256,
              accessoryPublicKey.count == 32, accessoryPublicKey.contains(where: { $0 != 0 }),
              controllerPrivateKey.count == 32,
              !controllerIdentifier.isEmpty, controllerIdentifier.count <= 128,
              let clientID = String(data: controllerIdentifier, encoding: .utf8),
              clientID == clientIdentity.pairingIdentifier,
              UUID(uuidString: clientID) != nil,
              controllerIdentifier != accessoryIdentifier else {
            throw RemoteFailure.message("The Apple TV transfer contains incomplete or inconsistent pairing keys.")
        }
        guard Self.validText(clientIdentity.name, maximumBytes: 80),
              Self.validText(clientIdentity.model, maximumBytes: 80),
              Self.validText(clientIdentity.operatingSystemName, maximumBytes: 64),
              Self.validText(clientIdentity.operatingSystemBuild, maximumBytes: 64),
              Self.validText(clientIdentity.operatingSystemVersion, maximumBytes: 64),
              Self.validHexIdentifier(clientIdentity.macAddress, bytes: 6, separator: ":"),
              Self.validHexIdentifier(clientIdentity.deviceID, bytes: 6, separator: ":"),
              Self.validHexIdentifier(clientIdentity.rapportIdentifier, bytes: 6, separator: nil),
              clientIdentity.rapportIdentifier.lowercased() != companionServiceIdentity?.lowercased() else {
            throw RemoteFailure.message("The Apple TV transfer contains invalid controller identity metadata.")
        }
        // Derive and validate locally using CryptoKit before accepting secret
        // material. The actual TV identity remains pinned and verified on connect.
        do {
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: controllerPrivateKey)
            guard privateKey.publicKey.rawRepresentation.count == 32 else {
                throw RemoteFailure.message("The Apple TV transfer contains invalid controller key material.")
            }
            _ = try Curve25519.Signing.PublicKey(rawRepresentation: accessoryPublicKey)
        } catch {
            throw RemoteFailure.message("The Apple TV transfer contains invalid signing keys.")
        }
        let credentials = HAPCredentials(ltpk: accessoryPublicKey, ltsk: controllerPrivateKey,
            atvIdentifier: accessoryIdentifier, clientIdentifier: controllerIdentifier)
        var settings = ATVSettings(clientIdentity: clientIdentity)
        settings.protocols.companion.identifier = companionServiceIdentity
        settings.setCredentials(credentials.serialize(), for: .companion)
        return ValidatedPairing(credentials: credentials, settings: settings)
    }

    private static func validText(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes &&
            !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func validHexIdentifier(_ value: String, bytes: Int, separator: Character?) -> Bool {
        let components: [Substring]
        if let separator {
            components = value.split(separator: separator, omittingEmptySubsequences: false)
            guard components.count == bytes, components.allSatisfy({ $0.utf8.count == 2 }) else { return false }
        } else {
            guard value.utf8.count == bytes * 2 else { return false }
            components = [Substring(value)]
        }
        return components.allSatisfy { text in
            text.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        }
    }
}
