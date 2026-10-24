import Foundation

/// Atomic nonsecret files. The recovery file contains only TV profiles, never pairing keys.
enum RegistryStorage {
    static func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RoomRemote", isDirectory: true)
    }

    static func load(in directory: URL) throws -> DeviceRegistry? {
        let url = directory.appendingPathComponent("registry.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(DeviceRegistry.self, from: boundedRead(url))
    }

    static func save(_ registry: DeviceRegistry, in directory: URL) throws {
        try write(JSONEncoder().encode(registry), to: directory.appendingPathComponent("registry.json"))
    }

    static func beginImport(_ devices: [RemoteDevice], in directory: URL) throws {
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("import-recovery.json").path) else {
            throw RoomTransfer.failure("Recover the interrupted import before starting another transfer. Unlock your iPhone and reopen the app.")
        }
        try RoomTransferPayload(devices: devices, rooms: [RoomProfile(name: "Recovery")]).validate()
        try write(JSONEncoder().encode(devices), to: directory.appendingPathComponent("import-recovery.json"))
    }

    static func recover(_ registry: DeviceRegistry, in directory: URL) throws -> DeviceRegistry {
        let url = directory.appendingPathComponent("import-recovery.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return registry }
        let devices = try JSONDecoder().decode([RemoteDevice].self, from: boundedRead(url))
        try RoomTransferPayload(devices: devices, rooms: [RoomProfile(name: "Recovery")]).validate()
        var recovered = registry
        for device in devices where !recovered.devices.contains(where: { $0.id == device.id }) {
            recovered.devices.append(device)
        }
        // No new room assignments or active selection: interrupted imports are
        // visible for Connect/Re-pair/Remove, without automatic TV connections.
        try save(recovered, in: directory)
        try finishImport(in: directory)
        return recovered
    }

    static func finishImport(in directory: URL) throws {
        let url = directory.appendingPathComponent("import-recovery.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private static func write(_ data: Data, to url: URL) throws {
        guard data.count <= RoomTransfer.maximumFileBytes else { throw RoomTransfer.failure("The saved setup is too large.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func boundedRead(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: RoomTransfer.maximumFileBytes + 1) ?? Data()
        guard data.count <= RoomTransfer.maximumFileBytes else { throw RoomTransfer.failure("The saved setup is too large.") }
        return data
    }
}
