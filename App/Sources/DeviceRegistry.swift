import Foundation

/// A short-lived first setup can fill both slots of a room that started empty.
/// This is deliberately separate from saved room configuration and is not restored
/// after relaunch, selection changes, or an explicit room edit.
struct EmptyRoomSetup: Sendable {
    fileprivate var expectedRoom: RoomProfile?

    init() { expectedRoom = nil }
    mutating func reset() { expectedRoom = nil }
}

/// Resolve a saved room against the current temporary selection. Connection work
/// is needed only for changed device identities, even when the room itself changes.
struct RoomSelectionPlan: Sendable {
    let room: RoomProfile
    let samsungID: String?
    let appleID: String?
    let changesRoom: Bool
    let changesSamsung: Bool
    let changesApple: Bool
    let navigationTarget: DeviceKind

    var isNoOp: Bool { !changesRoom && !changesSamsung && !changesApple }
}

struct DeviceRegistry: Codable, Sendable, Equatable {
    var devices: [RemoteDevice] = []
    var rooms: [RoomProfile] = [RoomProfile(name: "Living Room")]
    var lastRoomID: String?
    private(set) var appleAppFavorites: [String: Set<String>] = [:]
    private(set) var universalStarsEnabled = true
    // nil means an older setup has not yet materialized its shared list.
    // An explicit empty set must survive relaunch without re-seeding old stars.
    private(set) var universalAppFavorites: Set<String>?

    private static let maximumStarredAppsPerTV = 256
    private static let maximumStarredApps = 1024

    private enum CodingKeys: String, CodingKey {
        case devices, rooms, lastRoomID, appleAppFavorites, universalStarsEnabled, universalAppFavorites
    }

    var universalStarredAppIDs: Set<String> {
        universalAppFavorites ?? appleAppFavorites.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    func effectiveStarredAppIDs(for deviceID: String) -> Set<String> {
        guard device(deviceID, kind: .appleTV) != nil else { return [] }
        return universalStarsEnabled ? universalStarredAppIDs : starredAppIDs(for: deviceID)
    }

    mutating func setUniversalStarsEnabled(_ enabled: Bool) {
        if universalAppFavorites == nil { universalAppFavorites = universalStarredAppIDs }
        universalStarsEnabled = enabled
    }

    mutating func replaceUniversalStars(_ apps: Set<String>, enabled: Bool) throws {
        guard apps.count <= Self.maximumStarredApps, apps.allSatisfy(Self.isValidAppID) else {
            throw RemoteFailure.message("The shared stars contain invalid or excessive apps.")
        }
        universalAppFavorites = apps
        universalStarsEnabled = enabled
    }

    @discardableResult
    mutating func setEffectiveAppStarred(_ starred: Bool, appID: String, for deviceID: String) throws -> Bool {
        try requireAppleTV(deviceID)
        guard universalStarsEnabled else { return try setAppStarred(starred, appID: appID, for: deviceID) }
        guard Self.isValidAppID(appID) else { throw RemoteFailure.message("Choose a valid Apple TV app.") }
        var apps = universalStarredAppIDs
        let changed = starred ? apps.insert(appID).inserted : apps.remove(appID) != nil
        guard changed else { return false }
        try replaceUniversalStars(apps, enabled: true)
        return true
    }

    /// Stars belong to saved Apple TV identities, independently of room names,
    /// temporary selection, app names, and the current installed-app inventory.
    func starredAppIDs(for deviceID: String) -> Set<String> {
        guard device(deviceID, kind: .appleTV) != nil else { return [] }
        return appleAppFavorites[deviceID] ?? []
    }

    @discardableResult
    mutating func setAppStarred(_ starred: Bool, appID: String, for deviceID: String) throws -> Bool {
        try requireAppleTV(deviceID)
        guard Self.isValidAppID(appID) else { throw RemoteFailure.message("Choose a valid Apple TV app.") }
        var favorites = starredAppIDs(for: deviceID)
        if starred {
            guard !favorites.contains(appID) else { return false }
            favorites.insert(appID)
            try checkFavoriteLimits(favorites, for: deviceID)
        } else {
            guard favorites.remove(appID) != nil else { return false }
        }
        if favorites.isEmpty { appleAppFavorites.removeValue(forKey: deviceID) }
        else { appleAppFavorites[deviceID] = favorites }
        return true
    }

    /// Keep the target's existing stars and all source bundle IDs. The app list
    /// displays their intersection with installed apps, so an absent app stays
    /// hidden until it is installed without losing its imported preference.
    @discardableResult
    mutating func importAppStars(from sourceDeviceID: String, to targetDeviceID: String) throws -> Int {
        try requireAppleTV(sourceDeviceID)
        try requireAppleTV(targetDeviceID)
        guard sourceDeviceID != targetDeviceID else {
            throw RemoteFailure.message("Choose a different Apple TV to import stars.")
        }
        let existing = starredAppIDs(for: targetDeviceID)
        let merged = existing.union(starredAppIDs(for: sourceDeviceID))
        let added = merged.count - existing.count
        guard added > 0 else { return 0 }
        try checkFavoriteLimits(merged, for: targetDeviceID)
        appleAppFavorites[targetDeviceID] = merged
        return added
    }

    /// A reviewed setup import can copy an exact list, including no stars.
    mutating func replaceAppStars(_ appIDs: Set<String>, for deviceID: String) throws {
        try requireAppleTV(deviceID)
        guard appIDs.allSatisfy(Self.isValidAppID) else { throw RemoteFailure.message("The shared starred apps contain an invalid app ID.") }
        try checkFavoriteLimits(appIDs, for: deviceID)
        if appIDs.isEmpty { appleAppFavorites.removeValue(forKey: deviceID) }
        else { appleAppFavorites[deviceID] = appIDs }
    }

    mutating func replaceAppStars(_ lists: [String: Set<String>]) throws {
        var candidate = self
        // Free every replaced list before checking the final global limit.
        // Dictionary order must not reject a valid move between full TV lists.
        for id in lists.keys {
            try candidate.requireAppleTV(id)
            candidate.appleAppFavorites.removeValue(forKey: id)
        }
        for (id, apps) in lists { try candidate.replaceAppStars(apps, for: id) }
        self = candidate
    }

    /// Edit the endpoint on the same saved identity. Validate both values before
    /// changing either, so room references, stars and Keychain keys stay intact.
    mutating func updateTVNetwork(address: String, macAddress: String?, for deviceID: String, name: String? = nil) throws {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { throw RemoteFailure.message("This TV is no longer saved.") }
        let host = try SamsungProtocol.privateHost(address)
        guard !devices.contains(where: { $0.id != deviceID && $0.address == host }) else {
            throw RemoteFailure.message("Another saved TV uses this IP address. Check the address on your TV.")
        }
        let mac: String?
        if devices[index].kind == .samsung {
            mac = try macAddress.map(SamsungWakeOnLAN.normalizedMAC)
        } else {
            guard macAddress == nil else { throw RemoteFailure.message("Apple TV does not use a saved wake MAC.") }
            mac = nil
        }
        let updatedName = (name ?? devices[index].name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updatedName.isEmpty, updatedName.count <= 80 else {
            throw RemoteFailure.message("Enter a TV name of 1–80 characters.")
        }
        devices[index].name = updatedName
        devices[index].address = host
        devices[index].wakeMACAddress = mac
    }

    private func requireAppleTV(_ deviceID: String) throws {
        guard device(deviceID, kind: .appleTV) != nil else {
            throw RemoteFailure.message("Choose a saved Apple TV.")
        }
    }

    private func checkFavoriteLimits(_ favorites: Set<String>, for deviceID: String) throws {
        guard favorites.count <= Self.maximumStarredAppsPerTV else {
            throw RemoteFailure.message("This Apple TV has too many starred apps.")
        }
        let otherCount = appleAppFavorites.reduce(0) { $0 + ($1.key == deviceID ? 0 : $1.value.count) }
        guard otherCount + favorites.count <= Self.maximumStarredApps else {
            throw RemoteFailure.message("Your saved setup has too many starred apps.")
        }
    }

    private static func isValidAppID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 512 else { return false }
        return id.utf8.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) ||
            (48...57).contains(byte) || byte == 45 || byte == 46 || byte == 95
        }
    }

    func device(_ id: String?, kind: DeviceKind) -> RemoteDevice? {
        guard let id else { return nil }
        return devices.first { $0.id == id && $0.kind == kind }
    }

    /// A wake address belongs to one saved Samsung identity. Updating it must
    /// not move room assignments or replace the identity used for pairing keys.
    @discardableResult
    mutating func setSamsungWakeMAC(_ raw: String?, for deviceID: String) throws -> Bool {
        guard let index = devices.firstIndex(where: { $0.id == deviceID && $0.kind == .samsung }) else {
            throw RemoteFailure.message("Choose a saved Samsung TV.")
        }
        let normalized: String?
        if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized = try SamsungWakeOnLAN.normalizedMAC(raw)
        } else { normalized = nil }
        guard devices[index].wakeMACAddress != normalized else { return false }
        devices[index].wakeMACAddress = normalized
        return true
    }

    private func incomingWakeMAC(for device: RemoteDevice) throws -> String? {
        guard let raw = device.wakeMACAddress else { return nil }
        guard device.kind == .samsung else {
            throw RemoteFailure.message("Only Samsung TVs can have a wake MAC address.")
        }
        return try SamsungWakeOnLAN.normalizedMAC(raw)
    }

    func selectionPlan(for roomID: String, currentRoomID: String, samsungID: String?, appleID: String?, navigationTarget: DeviceKind) -> RoomSelectionPlan? {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return nil }
        let savedSamsungID = device(room.samsungID, kind: .samsung)?.id
        let savedAppleID = device(room.appleID, kind: .appleTV)?.id
        let target: DeviceKind
        if navigationTarget == .samsung, savedSamsungID == nil, savedAppleID != nil { target = .appleTV }
        else if navigationTarget == .appleTV, savedAppleID == nil, savedSamsungID != nil { target = .samsung }
        else { target = navigationTarget }
        return RoomSelectionPlan(
            room: room, samsungID: savedSamsungID, appleID: savedAppleID,
            changesRoom: roomID != currentRoomID,
            changesSamsung: savedSamsungID != samsungID, changesApple: savedAppleID != appleID,
            navigationTarget: target
        )
    }

    /// Register a pairing target independently from room assignments. A newly
    /// added TV may fill its own empty slot only during an empty room's first setup.
    @discardableResult
    mutating func addForPairing(_ device: RemoteDevice, roomID: String, initialSetup: inout EmptyRoomSetup) throws -> Bool {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            initialSetup.reset()
            guard devices[index].kind == device.kind else {
                throw RemoteFailure.message("This TV identity belongs to a different device type.")
            }
            var refreshed = device
            refreshed.name = devices[index].name
            if device.kind == .appleTV, device.wakeMACAddress != nil {
                throw RemoteFailure.message("Only Samsung TVs can have a wake MAC address.")
            }
            if let savedMAC = devices[index].wakeMACAddress { refreshed.wakeMACAddress = savedMAC }
            else { refreshed.wakeMACAddress = try incomingWakeMAC(for: device) }
            devices[index] = refreshed
            return false
        }

        var registered = device
        registered.wakeMACAddress = try incomingWakeMAC(for: device)
        devices.append(registered)
        guard let index = rooms.firstIndex(where: { $0.id == roomID }) else {
            initialSetup.reset()
            return false
        }
        var room = rooms[index]
        if let expected = initialSetup.expectedRoom {
            guard room == expected else {
                initialSetup.reset()
                return false
            }
        } else {
            guard room.samsungID == nil, room.appleID == nil else { return false }
        }

        switch device.kind {
        case .samsung:
            guard room.samsungID == nil else { initialSetup.reset(); return false }
            room.samsungID = device.id
        case .appleTV:
            guard room.appleID == nil else { initialSetup.reset(); return false }
            room.appleID = device.id
        }
        rooms[index] = room
        if room.samsungID != nil, room.appleID != nil { initialSetup.reset() }
        else { initialSetup.expectedRoom = room }
        return true
    }

    /// Move one saved Apple TV to its post-reset identity. The name, room
    /// assignments and stars follow it; every other saved TV is unchanged.
    mutating func replaceAppleIdentity(_ oldID: String, with replacement: RemoteDevice) throws {
        guard let index = devices.firstIndex(where: { $0.id == oldID && $0.kind == .appleTV }) else {
            throw RemoteFailure.message("Choose a saved Apple TV.")
        }
        guard replacement.kind == .appleTV, replacement.wakeMACAddress == nil,
              !devices.contains(where: { $0.id == replacement.id }) else {
            throw RemoteFailure.message("This Apple TV is already saved. Remove the old entry instead.")
        }
        var updated = replacement
        updated.name = devices[index].name
        devices[index] = updated
        if let stars = appleAppFavorites.removeValue(forKey: oldID) { appleAppFavorites[updated.id] = stars }
        for room in rooms.indices where rooms[room].appleID == oldID { rooms[room].appleID = updated.id }
    }

    mutating func removeDevice(_ id: String) {
        devices.removeAll { $0.id == id }
        appleAppFavorites.removeValue(forKey: id)
        for index in rooms.indices {
            if rooms[index].samsungID == id { rooms[index].samsungID = nil }
            if rooms[index].appleID == id { rooms[index].appleID = nil }
        }
    }

    mutating func saveRoom(_ room: RoomProfile) throws {
        let name = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { throw RemoteFailure.message("Use a room name between 1 and 60 characters.") }
        guard room.samsungID == nil || device(room.samsungID, kind: .samsung) != nil,
              room.appleID == nil || device(room.appleID, kind: .appleTV) != nil else {
            throw RemoteFailure.message("Choose saved devices of the correct type for this room.")
        }
        var valid = room
        valid.name = name
        if let index = rooms.firstIndex(where: { $0.id == room.id }) { rooms[index] = valid }
        else { rooms.append(valid) }
    }
}

extension DeviceRegistry {
    /// Older registries did not store stars. Keep their original required fields
    /// and add an empty preference collection without changing saved identities.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        devices = try values.decode([RemoteDevice].self, forKey: .devices)
        rooms = try values.decode([RoomProfile].self, forKey: .rooms)
        lastRoomID = try values.decodeIfPresent(String.self, forKey: .lastRoomID)
        let saved = try values.decodeIfPresent([String: Set<String>].self, forKey: .appleAppFavorites) ?? [:]
        appleAppFavorites = [:]
        for (deviceID, appIDs) in saved where device(deviceID, kind: .appleTV) != nil {
            let valid = Set(appIDs.filter(Self.isValidAppID))
            guard !valid.isEmpty else { continue }
            try checkFavoriteLimits(valid, for: deviceID)
            appleAppFavorites[deviceID] = valid
        }
        universalStarsEnabled = try values.decodeIfPresent(Bool.self, forKey: .universalStarsEnabled) ?? true
        if let apps = try values.decodeIfPresent(Set<String>.self, forKey: .universalAppFavorites) {
            try replaceUniversalStars(apps, enabled: universalStarsEnabled)
        } else {
            universalAppFavorites = nil
        }
    }
}

struct SelectionEpoch: Sendable {
    private(set) var value: UInt64 = 0
    mutating func advance() -> UInt64 { value &+= 1; return value }
    func accepts(_ captured: UInt64) -> Bool { value == captured }
}
