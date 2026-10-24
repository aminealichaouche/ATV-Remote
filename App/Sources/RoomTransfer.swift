import Foundation
import CryptoKit
import Security
import CommonCrypto

struct SharedRemotePreferences: Codable, Sendable, Equatable {
    let layout: RemoteLayout
    let useTouchpad: Bool

    static func current() -> Self {
        Self(layout: RemoteLayout(rawValue: UserDefaults.standard.string(forKey: RemoteLayout.storageKey) ?? "") ?? RemoteLayout.defaultLayout,
             useTouchpad: UserDefaults.standard.bool(forKey: RemoteLayout.touchpadStorageKey))
    }

    func apply() {
        UserDefaults.standard.set(layout.rawValue, forKey: RemoteLayout.storageKey)
        UserDefaults.standard.set(useTouchpad, forKey: RemoteLayout.touchpadStorageKey)
    }
}

struct SharedUniversalStars: Codable, Sendable, Equatable {
    let enabled: Bool
    let appIDs: Set<String>
}

struct RoomTransferPayload: Codable, Sendable {
    var version = 1
    var devices: [RemoteDevice]
    var rooms: [RoomProfile]
    var applePairings: [ApplePairingTransfer] = []
    var samsungPairings: [SamsungPairingTransfer] = []
    var starredApps: [String: Set<String>]?
    var remotePreferences: SharedRemotePreferences?
    var universalStars: SharedUniversalStars?
    // Version 4 explicitly opts into room mappings. Earlier files keep their
    // established rooms-local behavior rather than silently applying old rooms.
    var roomAssignmentsIncluded: Bool?

    var sharedStarCount: Int {
        if let universalStars, universalStars.enabled { return universalStars.appIDs.count }
        return starredApps?.values.reduce(0) { $0 + $1.count } ?? 0
    }

    /// Validate the complete file before dropping secrets and legacy rooms.
    func deviceSetupOnly() throws -> Self {
        try validate()
        var setup = self
        if roomAssignmentsIncluded != true { setup.rooms = [] }
        // Each phone obtains its own TV authorization. Validate legacy secrets
        // above, but never install another phone's Samsung or Apple identity.
        setup.applePairings = []
        setup.samsungPairings = []
        guard !setup.devices.isEmpty || !setup.rooms.isEmpty || setup.remotePreferences != nil else {
            throw RoomTransfer.failure("This file contains only rooms. Share TVs or remote settings instead.")
        }
        try setup.validate()
        return setup
    }

    func validate() throws {
        guard (1...4).contains(version), (version >= 2 || (starredApps == nil && remotePreferences == nil)),
              (version >= 3 || universalStars == nil),
              (version >= 4 || roomAssignmentsIncluded == nil), (version != 4 || roomAssignmentsIncluded == true),
              devices.count <= 64, rooms.count <= 64,
              (!devices.isEmpty || !rooms.isEmpty || remotePreferences != nil), applePairings.count <= devices.count, samsungPairings.count <= devices.count,
              Set(devices.map(\.id)).count == devices.count, Set(rooms.map(\.id)).count == rooms.count else { throw RoomTransfer.failure("This setup has invalid or excessive entries.") }
        for device in devices {
            if let mac = device.wakeMACAddress {
                guard device.kind == .samsung else { throw RoomTransfer.failure("Only Samsung TVs can have a wake MAC address.") }
                _ = try SamsungWakeOnLAN.normalizedMAC(mac)
            }
            guard Self.validString(device.id, max: 160), Self.validString(device.name, max: 80),
                  Self.validString(device.address, max: 160), device.hardwareModel.map({ Self.validString($0, max: 160) }) ?? true else { throw RoomTransfer.failure("A TV entry is invalid.") }
            if device.kind == .samsung {
                _ = try SamsungProtocol.privateHost(device.address)
                guard device.port == 8002 else { throw RoomTransfer.failure("Samsung sharing requires the secure remote port.") }
            } else {
                guard let identity = device.serviceName, Self.validString(identity, max: 150),
                      device.id == "apple:" + identity.lowercased(), device.serviceType == "_companion-link._tcp",
                      device.serviceDomain == "local.", let port = device.port, port > 0 else { throw RoomTransfer.failure("This Apple TV has no valid discovery identity.") }
            }
        }
        var registry = DeviceRegistry(devices: devices, rooms: [])
        if let starredApps {
            guard starredApps.count <= devices.count else { throw RoomTransfer.failure("The starred apps have invalid TV references.") }
            try registry.replaceAppStars(starredApps)
        }
        if let universalStars {
            guard devices.contains(where: { $0.kind == .appleTV }), starredApps != nil else {
                throw RoomTransfer.failure("Shared stars require a selected Apple TV.")
            }
            try registry.replaceUniversalStars(universalStars.appIDs, enabled: universalStars.enabled)
        }
        for room in rooms {
            guard Self.validString(room.id, max: 160), Self.validString(room.name, max: 60) else { throw RoomTransfer.failure("A room entry is invalid.") }
            try registry.saveRoom(room)
        }
        guard Set(applePairings.map(\.deviceID)).count == applePairings.count,
              Set(samsungPairings.map(\.deviceID)).count == samsungPairings.count else { throw RoomTransfer.failure("Pairing entries are duplicated.") }
        for pairing in applePairings {
            guard let device = registry.device(pairing.deviceID, kind: .appleTV) else { throw RoomTransfer.failure("An Apple TV pairing has no matching TV.") }
            try ApplePairingTransfer.validate(pairing, for: device)
        }
        for pairing in samsungPairings {
            guard let device = registry.device(pairing.deviceID, kind: .samsung) else { throw RoomTransfer.failure("A Samsung pairing has no matching TV.") }
            try SamsungPairingTransfer.validate(pairing, for: device)
        }
    }

    /// Always validate the complete unlocked file before filtering. Excluded
    /// entries cannot hide malformed credentials or dangling room references.
    func selecting(deviceIDs: Set<String>, roomIDs: Set<String>, includePairings: Bool,
                   includeStars: Bool = true, includeRemotePreferences: Bool = true) throws -> Self {
        try validate()
        var selected = self
        selected.devices = devices.filter { deviceIDs.contains($0.id) }
        let ids = Set(selected.devices.map(\.id))
        selected.rooms = rooms.filter { roomIDs.contains($0.id) }.map { source in
            var room = source
            if !ids.contains(room.samsungID ?? "") { room.samsungID = nil }
            if !ids.contains(room.appleID ?? "") { room.appleID = nil }
            return room
        }
        // Read and validate legacy files, but never install another phone's
        // Companion controller identity. Each iPhone must pair independently.
        selected.applePairings = []
        selected.samsungPairings = includePairings ? samsungPairings.filter { ids.contains($0.deviceID) } : []
        selected.starredApps = includeStars ? starredApps.map { $0.filter { ids.contains($0.key) } } : nil
        selected.universalStars = includeStars && selected.devices.contains(where: { $0.kind == .appleTV }) ? universalStars : nil
        selected.remotePreferences = includeRemotePreferences ? remotePreferences : nil
        guard !selected.devices.isEmpty || !selected.rooms.isEmpty || selected.remotePreferences != nil else {
            throw RoomTransfer.failure("Choose a TV or room group to import.")
        }
        try selected.validate()
        return selected
    }

    static func validString(_ value: String, max: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= max && value.utf8.count <= max * 4 && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

struct RoomTransferPlan: Sendable {
    let registry: DeviceRegistry
    let newDevices: [RemoteDevice]
    let applePairings: [ApplePairingTransfer]
    let samsungPairings: [SamsungPairingTransfer]
    let reusedDeviceCount: Int
    let addedRoomCount: Int
    let updatedRoomCount: Int
    let roomResults: [RoomTransferRoomResult]
    let copiedStarTVCount: Int
    let copiedStarCount: Int

    init(payload: RoomTransferPayload, existing: DeviceRegistry) throws {
        try payload.validate()
        var result = existing
        var newDevices: [RemoteDevice] = []
        var mapping: [String: String] = [:]
        for incoming in payload.devices {
            if let saved = existing.devices.first(where: { $0.id == incoming.id }) {
                guard RoomTransferReview.matches(saved, incoming) else { throw RoomTransfer.failure("A TV identity conflicts with one already saved. Existing pairings were preserved.") }
                mapping[incoming.id] = saved.id
            } else {
                mapping[incoming.id] = incoming.id
                result.devices.append(incoming)
                newDevices.append(incoming)
            }
        }
        if let stars = payload.starredApps {
            var mappedStars: [String: Set<String>] = [:]
            for (id, apps) in stars {
                guard let mapped = mapping[id] else { throw RoomTransfer.failure("The starred apps have no selected Apple TV.") }
                mappedStars[mapped] = apps
            }
            try result.replaceAppStars(mappedStars)
            if payload.universalStars == nil, result.universalStarsEnabled, !stars.isEmpty {
                // Older senders only have TV lists. Copy their selected lists
                // into the active shared list, including an explicit empty list.
                try result.replaceUniversalStars(stars.values.reduce(into: Set<String>()) { $0.formUnion($1) }, enabled: true)
            }
        }
        if let universal = payload.universalStars {
            try result.replaceUniversalStars(universal.appIDs, enabled: universal.enabled)
        }
        // A fresh install's unused starter room is not a configured conflict.
        if payload.version >= 2, existing.devices.isEmpty, existing.rooms.count == 1,
           let starter = existing.rooms.first, starter.name == "Living Room",
           starter.samsungID == nil, starter.appleID == nil,
           (payload.roomAssignmentsIncluded == true ? !payload.rooms.isEmpty : payload.rooms.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(starter.name) == .orderedSame })) {
            result.rooms.removeAll { $0.id == starter.id }
        }
        var addedRooms = 0
        var updatedRooms = 0
        var roomResults: [RoomTransferRoomResult] = []
        for incoming in payload.rooms {
            var room = incoming
            room.name = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
            room.samsungID = incoming.samsungID.flatMap { mapping[$0] }
            room.appleID = incoming.appleID.flatMap { mapping[$0] }
            if let same = result.rooms.first(where: {
                ($0.id == room.id || $0.name.caseInsensitiveCompare(room.name) == .orderedSame) &&
                    $0.samsungID == room.samsungID && $0.appleID == room.appleID
            }) {
                roomResults.append(RoomTransferRoomResult(incomingID: incoming.id, room: same, isAdded: false))
                continue
            }
            if payload.roomAssignmentsIncluded == true,
               let empty = result.rooms.first(where: {
                   $0.name.caseInsensitiveCompare(room.name) == .orderedSame && $0.samsungID == nil && $0.appleID == nil
               }) {
                room.id = empty.id
                try result.saveRoom(room)
                updatedRooms += 1
                roomResults.append(RoomTransferRoomResult(incomingID: incoming.id, room: room, isAdded: false))
                continue
            }
            if result.rooms.contains(where: { $0.id == room.id }) {
                let identity = try JSONEncoder().encode([room.id, room.samsungID ?? "", room.appleID ?? ""])
                room.id = "shared-room:" + SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
                if let saved = result.rooms.first(where: { $0.id == room.id }) {
                    guard saved.samsungID == room.samsungID, saved.appleID == room.appleID else { throw RoomTransfer.failure("A shared room identity conflicts with a saved room.") }
                    roomResults.append(RoomTransferRoomResult(incomingID: incoming.id, room: saved, isAdded: false))
                    continue
                }
            }
            let base = String(room.name.prefix(45))
            var suffix = 1
            while result.rooms.contains(where: { $0.name.caseInsensitiveCompare(room.name) == .orderedSame }) {
                room.name = suffix == 1 ? "\(base) (shared)" : "\(base) (shared \(suffix))"
                suffix += 1
            }
            try result.saveRoom(room)
            addedRooms += 1
            roomResults.append(RoomTransferRoomResult(incomingID: incoming.id, room: room, isAdded: true))
        }
        let newIDs = Set(newDevices.map(\.id))
        self.registry = result
        self.newDevices = newDevices
        // Also enforce at the commit boundary if the caller bypasses selection.
        applePairings = []
        samsungPairings = payload.samsungPairings.filter { newIDs.contains($0.deviceID) }
        reusedDeviceCount = payload.devices.count - newDevices.count
        addedRoomCount = addedRooms
        updatedRoomCount = updatedRooms
        self.roomResults = roomResults
        copiedStarTVCount = payload.universalStars != nil ? payload.devices.filter { $0.kind == .appleTV }.count : payload.starredApps?.count ?? 0
        copiedStarCount = payload.sharedStarCount
    }
}

struct RoomTransferRoomResult: Sendable {
    let incomingID: String
    let room: RoomProfile
    let isAdded: Bool
}

struct RoomTransferDeviceReview: Identifiable, Sendable {
    let device: RemoteDevice
    let existing: RemoteDevice?
    let conflict: String?
    let hasSharedAccess: Bool
    var id: String { device.id }
}

/// Preview uses the same identity rules as commit; conflicts stay visible but
/// cannot be selected. IP/name similarity never substitutes another TV.
struct RoomTransferReview: Sendable {
    let devices: [RoomTransferDeviceReview]
    init(payload: RoomTransferPayload, existing: DeviceRegistry) throws {
        try payload.validate()
        let paired = Set(payload.samsungPairings.map(\.deviceID))
        devices = payload.devices.map { device in
            let saved = existing.devices.first { $0.id == device.id }
            let matches = saved.map { Self.matches($0, device) } ?? true
            return RoomTransferDeviceReview(device: device, existing: saved,
                conflict: matches ? nil : "Saved identity has a different TV address or type. Skipped.",
                hasSharedAccess: paired.contains(device.id))
        }
    }
    var selectableDeviceIDs: Set<String> { Set(devices.filter { $0.conflict == nil }.map(\.id)) }
    static func matches(_ saved: RemoteDevice, _ incoming: RemoteDevice) -> Bool {
        saved.kind == incoming.kind && (incoming.kind == .samsung
            ? saved.address == incoming.address
            : saved.serviceName?.lowercased() == incoming.serviceName?.lowercased())
    }
}

enum RoomTransfer {
    static let maximumFileBytes = 1_048_576
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)
    private static let legacyInfo = Data("Room Remote encrypted setup v1".utf8)
    private static let phraseInfo = Data("Room Remote encrypted setup v2;pbkdf2-sha256;iterations=600000".utf8)
    static let phraseKDF = "pbkdf2-sha256"
    static let phraseIterations = 600_000

    private struct Envelope: Codable {
        let format: String
        let version: Int
        let salt: Data
        let sealed: Data
        let kdf: String?
        let iterations: Int?

        enum CodingKeys: String, CodingKey { case format, version, salt, sealed, kdf, iterations }

        init(salt: Data, sealed: Data) {
            format = "roomremote"
            version = 2
            self.salt = salt
            self.sealed = sealed
            kdf = RoomTransfer.phraseKDF
            iterations = RoomTransfer.phraseIterations
        }

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            format = try fields.decode(String.self, forKey: .format)
            version = try fields.decode(Int.self, forKey: .version)
            guard format == "roomremote", version == 1 || version == 2 else {
                throw RoomTransfer.failure("This setup file is invalid or uses an unsupported version.")
            }
            if version == 1 {
                // A legacy envelope never declares a phrase KDF. Do not permit a downgrade.
                guard !fields.contains(.kdf), !fields.contains(.iterations) else {
                    throw RoomTransfer.failure("This setup file has inconsistent encryption settings.")
                }
                kdf = nil
                iterations = nil
            } else {
                kdf = try fields.decode(String.self, forKey: .kdf)
                iterations = try fields.decode(Int.self, forKey: .iterations)
                guard kdf == RoomTransfer.phraseKDF, iterations == RoomTransfer.phraseIterations else {
                    throw RoomTransfer.failure("This setup file uses unsupported encryption settings.")
                }
            }
            salt = try fields.decode(Data.self, forKey: .salt)
            sealed = try fields.decode(Data.self, forKey: .sealed)
        }
    }

    static func failure(_ message: String) -> RemoteFailure { .message(message) }

    static func makeCode() throws -> String { try TransferPhrase.generate() }

    private struct DirectEnvelope: Codable {
        let format: String
        let version: Int
        let payload: RoomTransferPayload
    }

    /// AirDrop protects transport. This file itself has no password and contains
    /// configuration only, never TV credentials. Do not treat its origin as trusted.
    static func directFile(_ payload: RoomTransferPayload) throws -> Data {
        let setup = try payload.deviceSetupOnly()
        let data = try JSONEncoder().encode(DirectEnvelope(format: "roomremote-direct", version: 1, payload: setup))
        guard data.count <= maximumFileBytes / 2 else { throw failure("Share fewer TVs at once.") }
        return data
    }

    /// nil means a recognized protected file still needs its phrase. Malformed
    /// direct files fail here rather than falling through to a password prompt.
    static func directPayload(from file: Data) throws -> RoomTransferPayload? {
        guard !file.isEmpty, file.count <= maximumFileBytes else { throw failure("This setup file is empty or too large.") }
        try boundJSON(file)
        struct Header: Decodable { let format: String }
        guard let header = try? JSONDecoder().decode(Header.self, from: file) else {
            throw failure("This setup file is invalid.")
        }
        if header.format == "roomremote" { return nil }
        guard header.format == "roomremote-direct" else { throw failure("This setup file uses an unsupported format.") }
        let envelope: DirectEnvelope
        do { envelope = try JSONDecoder().decode(DirectEnvelope.self, from: file) }
        catch { throw failure("This setup file is malformed.") }
        guard envelope.version == 1 else { throw failure("Update ATV Remote to open this setup file.") }
        return try envelope.payload.deviceSetupOnly()
    }

    private static func codeBytes(_ code: String) throws -> Data {
        guard code.utf8.count <= 96 else { throw failure("Use the transfer code from the sending iPhone.") }
        let raw = code.uppercased().utf8.filter { $0 != 45 && $0 != 32 && $0 != 10 && $0 != 13 }
        guard raw.count == 32 else { throw failure("Enter all eight groups of the transfer code.") }
        var output = Data(), bits: UInt32 = 0, count = 0
        for character in raw {
            guard let value = alphabet.firstIndex(of: character) else { throw failure("The transfer code contains an invalid character.") }
            bits = ((bits << 5) | UInt32(value)) & 0xFFFF
            count += 5
            if count >= 8 { count -= 8; output.append(UInt8((bits >> count) & 255)) }
        }
        return output
    }

    private static func legacyKey(code: String, salt: Data) throws -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: try codeBytes(code)), salt: salt, info: legacyInfo, outputByteCount: 32)
    }

    // Fixed cost and a domain-separated salt prevent attacker-selected work factors or schemes.
    static func phraseKeyData(code: String, salt: Data) throws -> Data {
        guard salt.count == 16 else { throw failure("This setup file has an invalid encryption salt.") }
        let password = Data(try TransferPhrase.normalized(code).utf8)
        let derivationSalt = phraseInfo + salt
        let outputLength = 32
        var output = Data(repeating: 0, count: outputLength)
        let status = password.withUnsafeBytes { passwordBytes in
            derivationSalt.withUnsafeBytes { saltBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress!, password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress!, derivationSalt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(phraseIterations),
                        outputBytes.bindMemory(to: UInt8.self).baseAddress!, outputLength)
                }
            }
        }
        guard status == kCCSuccess else { throw failure("The transfer phrase could not be secured. Try again.") }
        return output
    }

    static func encrypt(_ payload: RoomTransferPayload, code: String) throws -> Data {
        try payload.validate()
        let phrase = try TransferPhrase.normalized(code)
        let plain = try JSONEncoder().encode(payload)
        guard plain.count <= maximumFileBytes / 2 else { throw failure("Share fewer TVs at once.") }
        let salt = try randomBytes(count: 16)
        let key = SymmetricKey(data: try phraseKeyData(code: phrase, salt: salt))
        let sealed = try AES.GCM.seal(plain, using: key, authenticating: phraseInfo + salt)
        guard let combined = sealed.combined else { throw failure("The setup could not be encrypted.") }
        return try JSONEncoder().encode(Envelope(salt: salt, sealed: combined))
    }

    static func decrypt(_ file: Data, code: String) throws -> RoomTransferPayload {
        guard !file.isEmpty, file.count <= maximumFileBytes else { throw failure("This setup file is empty or too large.") }
        try boundJSON(file)
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: file) }
        catch { throw failure("This setup file is invalid or uses unsupported encryption settings.") }
        guard envelope.salt.count == 16,
              envelope.sealed.count >= 28, envelope.sealed.count <= maximumFileBytes / 2 + 28 else { throw failure("This setup file is invalid or uses an unsupported version.") }
        let derived: SymmetricKey
        let authenticated: Data
        if envelope.version == 1 {
            derived = try legacyKey(code: code, salt: envelope.salt)
            authenticated = legacyInfo + envelope.salt
        } else {
            derived = SymmetricKey(data: try phraseKeyData(code: code, salt: envelope.salt))
            authenticated = phraseInfo + envelope.salt
        }
        let plain: Data
        do { plain = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: derived, authenticating: authenticated) }
        catch { throw failure("The transfer phrase or code is incorrect, or the file was changed.") }
        let payload: RoomTransferPayload
        try boundJSON(plain)
        do { payload = try JSONDecoder().decode(RoomTransferPayload.self, from: plain) }
        catch { throw failure("The encrypted setup is malformed.") }
        try payload.validate()
        return payload
    }

    // Apply a nesting bound before handing either untrusted JSON layer to Foundation.
    private static func boundJSON(_ data: Data) throws {
        var depth = 0, inString = false, escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else if byte == 34 { inString = true }
            else if byte == 123 || byte == 91 {
                depth += 1
                if depth > 16 { throw failure("This setup file is nested too deeply.") }
            } else if byte == 125 || byte == 93 {
                depth -= 1
                if depth < 0 { throw failure("This setup file is malformed.") }
            }
        }
        guard depth == 0, !inString else { throw failure("This setup file is malformed.") }
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw failure("Secure random generation failed. Try again.") }
        return Data(bytes)
    }

    static func readFile(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw failure("Choose a local setup file.") }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var result: Result<Data, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
            result = Result {
                let values = try coordinated.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumFileBytes else { throw failure("Choose a setup file smaller than 1 MB.") }
                let handle = try FileHandle(forReadingFrom: coordinated)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
                guard !data.isEmpty, data.count <= maximumFileBytes else { throw failure("This setup file is empty or too large.") }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw failure("The setup file could not be opened.") }
        return try result.get()
    }
}
