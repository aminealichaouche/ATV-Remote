import Foundation

enum DeviceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case samsung, appleTV
    var id: String { rawValue }
    var title: String { self == .samsung ? "Samsung TV" : "Apple TV" }
}

struct RemoteDevice: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var kind: DeviceKind
    var name: String
    var address: String
    var port: UInt16?
    var serviceName: String?
    var serviceType: String?
    var serviceDomain: String?
    var hardwareModel: String?
    var wakeMACAddress: String?

    var settingsDisplayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .appleTV,
              trimmed.range(of: "apple tv", options: .caseInsensitive) == nil,
              trimmed.range(of: "appletv", options: .caseInsensitive) == nil else { return name }
        return "\(trimmed) Apple TV"
    }
}

struct RoomProfile: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var samsungID: String?
    var appleID: String?
}

enum RemoteAction: String, CaseIterable, Sendable {
    case up, down, left, right, select, back, home, playPause
    case appSwitcher, controlCenter
    case volumeUp, volumeDown, mute, wake, sleep, powerOff, powerToggle, source
}

struct RemoteAppInfo: Identifiable, Hashable, Sendable {
    var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = id == "com.comcast.cim.x2" ? "Xfinity Stream" : name
    }
}

enum DeviceConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case awaitingApproval
    case awaitingPin
    case trustRequired(fingerprint: String)
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .awaitingApproval: "Allow access on the TV"
        case .awaitingPin: "Enter the code shown on the TV"
        case .trustRequired: "Confirm this TV"
        case .connected: "Connected"
        case .failed(let reason): reason
        }
    }
    var isConnected: Bool { self == .connected }
}

enum RemoteFailure: LocalizedError, Sendable {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { message } else { nil } }
}

protocol RemoteDriver: Actor {
    func connect(to device: RemoteDevice, onState: @escaping @Sendable (DeviceConnectionState) -> Void) async throws
    func disconnect() async
    func send(_ action: RemoteAction, toDeviceID: String) async throws
    func connectUsingSavedPairing(to device: RemoteDevice, onState: @escaping @Sendable (DeviceConnectionState) -> Void) async throws
    func connectionIsConnected(toDeviceID: String) -> Bool
    func verifyConnection(toDeviceID: String) async -> Bool
    func observeEstablishedConnection(toDeviceID: String, onState: @escaping @Sendable (DeviceConnectionState) -> Void) async -> Bool
}
