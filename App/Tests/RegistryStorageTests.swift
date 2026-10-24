import XCTest
@testable import RoomRemote

final class RegistryStorageTests: XCTestCase {
    func testNewImportCannotOverwritePendingRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = RemoteDevice(id: "first", kind: .samsung, name: "First", address: "192.168.1.10", port: 8002)
        let second = RemoteDevice(id: "second", kind: .samsung, name: "Second", address: "192.168.1.11", port: 8002)
        try RegistryStorage.beginImport([first], in: directory)
        XCTAssertThrowsError(try RegistryStorage.beginImport([second], in: directory))
        let recovered = try RegistryStorage.recover(DeviceRegistry(), in: directory)
        XCTAssertEqual(recovered.devices, [first])
    }

    func testInterruptedImportRestoresOnlyUnassignedProfiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = DeviceRegistry()
        let device = RemoteDevice(id: "staged-tv", kind: .samsung, name: "Staged TV", address: "192.168.1.10", port: 8002)
        try RegistryStorage.save(registry, in: directory)
        try RegistryStorage.beginImport([device], in: directory)
        let recovered = try RegistryStorage.recover(try XCTUnwrap(RegistryStorage.load(in: directory)), in: directory)
        XCTAssertEqual(recovered.devices, [device])
        XCTAssertEqual(recovered.rooms, registry.rooms)
        XCTAssertNil(recovered.rooms[0].samsungID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("import-recovery.json").path))
    }

    func testRecoveryDoesNotReplaceExistingDeviceOrDuplicateCommittedImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = RemoteDevice(id: "same-id", kind: .samsung, name: "My existing TV", address: "192.168.1.10", port: 8002)
        let registry = DeviceRegistry(devices: [device])
        var incoming = device; incoming.name = "Imported label"
        try RegistryStorage.beginImport([incoming], in: directory)
        XCTAssertEqual(try RegistryStorage.recover(registry, in: directory), registry)
        XCTAssertEqual(try RegistryStorage.load(in: directory), registry)
    }
}
