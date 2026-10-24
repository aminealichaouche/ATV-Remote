import SwiftUI

enum AppSheet: Identifiable {
    case settings, devices, rooms, keyboard, apps, power, transfer, shortcuts
    case pin(String)
    case trust(String, String)
    var id: String {
        switch self {
        case .settings: "settings"
        case .devices: "devices"
        case .rooms: "rooms"
        case .keyboard: "keyboard"
        case .apps: "apps"
        case .power: "power"
        case .transfer: "transfer"
        case .shortcuts: "shortcuts"
        case .pin(let id): "pin.\(id)"
        case .trust(let id, _): "trust.\(id)"
        }
    }
}

enum RestartShortcutPhase: Equatable {
    case idle, loadingApps, preparing, closing, completed, failed

    var isInProgress: Bool { self == .loadingApps || self == .preparing || self == .closing }
}

/// Owns a command until it finishes or its target is cancelled. Completion from an
/// older request cannot release a newer request's slot, and each driver has its own slot.
struct CommandRequests: Sendable {
    private var current: [DeviceKind: UUID] = [:]

    mutating func begin(for kind: DeviceKind) -> UUID? {
        guard current[kind] == nil else { return nil }
        let request = UUID()
        current[kind] = request
        return request
    }
    func accepts(_ request: UUID, for kind: DeviceKind) -> Bool { current[kind] == request }
    @discardableResult mutating func finish(_ request: UUID, for kind: DeviceKind) -> Bool {
        guard accepts(request, for: kind) else { return false }
        current.removeValue(forKey: kind)
        return true
    }
    mutating func cancel(for kind: DeviceKind) { current.removeValue(forKey: kind) }
}

@MainActor
final class RemoteStore: ObservableObject {
    @Published private(set) var registry: DeviceRegistry
    @Published private(set) var selectedRoomID: String
    @Published private(set) var samsungID: String?
    @Published private(set) var appleID: String?
    @Published var navigationTarget: DeviceKind = .appleTV
    @Published private(set) var states: [String: DeviceConnectionState] = [:]
    @Published var sheet: AppSheet? {
        didSet { if sheet != nil { cancelAutoRoomSearch() } }
    }
    @Published var alertMessage: String?
    @Published private(set) var feedback = "Choose and pair your TVs to get started."
    @Published private(set) var discoveredAppleTVs: [RemoteDevice] = []
    @Published private(set) var isDiscovering = false
    @Published private(set) var installedApps: [RemoteAppInfo] = []
    @Published private(set) var appsLoaded = false
    @Published private(set) var appsError: String?
    @Published private(set) var appsLaunchingID: String?
    @Published private(set) var appsPresentationID: UUID?
    @Published private(set) var keyboardReady = false
    @Published private(set) var toolsLoading = false
    @Published private(set) var incomingTransfer: Data?
    @Published private(set) var shortcutPhase: RestartShortcutPhase = .idle
    @Published private(set) var shortcutError: String?
    @Published private(set) var shortcutTarget: RemoteAppInfo?
    @Published private(set) var restartAppChoices: [RemoteAppInfo] = []
    @Published private(set) var restartChoiceError: String?
    @Published private(set) var showRestartAppChoice = false
    @Published private(set) var shortcutsPresentationID: UUID?
    @Published private(set) var samsungWakeDeviceID: String?
    @Published private(set) var samsungWakeMessage: String?
    @Published private(set) var samsungWakeError: String?
    @Published private(set) var automaticRoomEnabled = false
    @Published private(set) var autoRoomSearching = false
    @Published private(set) var autoResolvedRoomID: String?

    private let vault: KeychainVault
    private var apple: AppleTVDriver
    private var samsung: SamsungDriver
    // Only visited TVs acquire actors; room selection does not own their lifetime.
    private var retainedDrivers: [String: any RemoteDriver] = [:]
    private var sessionObservations: [String: UUID] = [:]
    private let samsungWakeSender = SamsungWakeSender()
    private var epochs: [DeviceKind: SelectionEpoch] = [.appleTV: SelectionEpoch(), .samsung: SelectionEpoch()]
    private var connectionObservationTokens: [DeviceKind: UUID] = [.appleTV: UUID(), .samsung: UUID()]
    private var connectionTasks: [DeviceKind: Task<Void, Never>] = [:]
    private var commandTasks: [DeviceKind: Task<Void, Never>] = [:]
    private var commandRequests = CommandRequests()
    private var connectionIntent = ConnectionIntent()
    private var discoveryTask: Task<Void, Never>?
    private var discoveryRequest = UUID()
    private var toolsRequest = UUID()
    private var appsLaunchRequest = UUID()
    private var appsLoadTask: Task<Void, Never>?
    private var appsLaunchTask: Task<Void, Never>?
    private var appsDeviceID: String?
    private var shortcutRequest: UUID?
    private var restartChoiceDeviceID: String?
    private var restartChoiceEpoch: UInt64?
    private var shortcutEpoch: UInt64?
    private var transferBusy = false
    private var transferReadRequest = UUID()
    private var queuedTransferURL: URL?
    private var initialRoomSetup = EmptyRoomSetup()
    private let persistenceKey = "RoomRemote.registry.v1"
    @Published private var active = false
    private var statusTask: Task<Void, Never>?
    private var statusRequest = UUID()
    private var lastConnectionAttempt: [DeviceKind: ContinuousClock.Instant] = [:]
    private var powerStatusTasks: [DeviceKind: Task<Void, Never>] = [:]
    private var powerStatusRequests: [DeviceKind: UUID] = [:]
    private var wakeMessageTask: Task<Void, Never>?
    private var wakeMessageRequest: UUID?
    private var wakeCleanupTask: Task<Void, Never>?
    private var autoRoomTask: Task<Void, Never>?
    private var autoRoomRequest = UUID()
    private var lastAutoAttempt: ContinuousClock.Instant?
    #if DEBUG
    private var uiHomeActions: [String] = []
    private var uiObservedAppleConnected = true
    private var uiLostSessionIDs: Set<String> = []
    private var uiLoseLivingOnReturn = false
    private var uiSessionConnectCounts: [String: Int] = [:]
    private var usesSyntheticConnections: Bool {
        ["--ui-testing-home", "--ui-testing-shortcut-success", "--ui-testing-status-refresh", "--ui-testing-apps", "--ui-testing-room-sessions"].contains { CommandLine.arguments.contains($0) }
    }
    var uiSessionLog: String {
        retainedDrivers.keys.sorted().map { id in
            "\(id)=\(ObjectIdentifier(retainedDrivers[id]!));\(uiSessionConnectCounts[id] ?? 0);\(states[id]?.title ?? "Not connected")"
        }.joined(separator: "|")
    }
    @Published private(set) var uiWakeTargetDescription: String?
    @Published private(set) var uiRetryCounts = "0,0"
    @Published private(set) var uiNavigationRequests = ""
    private var uiAppleRetryCount = 0
    private var uiSamsungRetryCount = 0
    private var uiWakeSendCount = 0
    #endif

    init() {
        let vault = KeychainVault()
        self.vault = vault
        apple = AppleTVDriver(vault: vault)
        samsung = SamsungDriver(vault: vault)
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing-reset") {
            UserDefaults.standard.removeObject(forKey: persistenceKey)
            UserDefaults.standard.removeObject(forKey: RemoteLayout.storageKey)
            UserDefaults.standard.removeObject(forKey: RemoteLayout.touchpadStorageKey)
            UserDefaults.standard.removeObject(forKey: AutoRoomPolicy.preferenceKey)
            UserDefaults.standard.removeObject(forKey: "transferRequiresPhrase")
            UserDefaults.standard.removeObject(forKey: "transferIncludeRooms")
            if let directory = try? RegistryStorage.directory() { try? FileManager.default.removeItem(at: directory) }
        }
        #endif
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing-saved-auto") {
            UserDefaults.standard.set(true, forKey: AutoRoomPolicy.preferenceKey)
        }
        #endif
        let saved = UserDefaults.standard.data(forKey: persistenceKey)
        let directory = try? RegistryStorage.directory()
        let fileRegistry = directory.flatMap { try? RegistryStorage.load(in: $0) }
        var registry = fileRegistry ?? saved.flatMap { try? JSONDecoder().decode(DeviceRegistry.self, from: $0) } ?? DeviceRegistry()
        var recoveredImport = false
        if let directory, let recovered = try? RegistryStorage.recover(registry, in: directory) {
            recoveredImport = recovered.devices.count > registry.devices.count
            registry = recovered
        }
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing-connections") || CommandLine.arguments.contains("--ui-testing-home") || CommandLine.arguments.contains("--ui-testing-shortcut-success") || CommandLine.arguments.contains("--ui-testing-status-refresh") || CommandLine.arguments.contains("--ui-testing-retry") {
            // Synthetic endpoints only. Auto-connect is held below; the Samsung
            // loopback endpoint is rejected before any socket or Keychain use.
            registry.devices = [
                RemoteDevice(id: "ui-apple-status", kind: .appleTV, name: "Living Room", address: "127.0.0.1"),
                RemoteDevice(id: "ui-samsung-status", kind: .samsung, name: "Living Room TV", address: "127.0.0.1")
            ]
            registry.rooms = [RoomProfile(id: "ui-status-room", name: "Living Room", samsungID: "ui-samsung-status", appleID: "ui-apple-status")]
            registry.lastRoomID = "ui-status-room"
        }
        #endif
        // Freeze the legacy union before any TV removal or per-TV import.
        registry.setUniversalStarsEnabled(registry.universalStarsEnabled)
        self.registry = registry
        let room = registry.rooms.first { $0.id == registry.lastRoomID } ?? registry.rooms.first ?? RoomProfile(id: "no-room", name: "No room")
        selectedRoomID = room.id
        samsungID = registry.device(room.samsungID, kind: .samsung)?.id
        appleID = registry.device(room.appleID, kind: .appleTV)?.id
        if recoveredImport { feedback = "An interrupted import was recovered. Unassigned TVs are in Your TVs; use Connect, Re-pair, or Remove." }
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing-connections") {
            connectionIntent.disconnect("ui-apple-status")
            connectionIntent.disconnect("ui-samsung-status")
            states["ui-apple-status"] = .connecting
            states["ui-samsung-status"] = .awaitingApproval
        }
        if CommandLine.arguments.contains("--ui-testing-home") || CommandLine.arguments.contains("--ui-testing-shortcut-success") || CommandLine.arguments.contains("--ui-testing-status-refresh") {
            // Established-state fixtures are protected by the automatic-connect
            // policy; no manual-disconnect intent is fabricated for these TVs.
            states["ui-apple-status"] = .connected
            states["ui-samsung-status"] = .connected
        }
        if CommandLine.arguments.contains("--ui-testing-transfer-review") {
            let local = RemoteDevice(id: "review-existing", kind: .samsung, name: "My Living TV", address: "192.168.1.20", port: 8002)
            let newcomer = RemoteDevice(id: "review-new", kind: .samsung, name: "Family TV", address: "192.168.1.21", port: 8002)
            self.registry = DeviceRegistry(devices: [local], rooms: [RoomProfile(id: "review-living", name: "Living Room", samsungID: local.id)])
            selectedRoomID = "review-living"; samsungID = local.id; appleID = nil
            connectionIntent.disconnect(local.id)
            var sharedLocal = local; sharedLocal.name = "Sender Living TV"
            let fixture = RoomTransferPayload(devices: [sharedLocal, newcomer], rooms: [
                RoomProfile(id: "review-living", name: "Living Room", samsungID: newcomer.id),
                RoomProfile(id: "review-family", name: "Family Room", samsungID: newcomer.id)
            ], samsungPairings: [SamsungPairingTransfer(deviceID: newcomer.id, token: "synthetic-review-only", certificateSHA256: Data(repeating: 1, count: 32), clientName: SamsungProtocol.clientName(deviceID: newcomer.id))])
            incomingTransfer = try? RoomTransfer.encrypt(fixture, code: "cable lunar velvet walnut")
        }
        if CommandLine.arguments.contains("--ui-testing-transfer-appearance") {
            let tv = RemoteDevice(id: "apple:shared-living", kind: .appleTV, name: "Living Apple TV", address: "192.168.1.30", port: 49153,
                                  serviceName: "shared-living", serviceType: "_companion-link._tcp", serviceDomain: "local.")
            self.registry = DeviceRegistry(devices: [tv], rooms: [RoomProfile(id: "appearance-room", name: "Living Room", appleID: tv.id)])
            try? self.registry.setAppStarred(true, appID: "com.example.Old", for: tv.id)
            selectedRoomID = "appearance-room"; appleID = tv.id; samsungID = nil
            connectionIntent.disconnect(tv.id)
            let fixture = RoomTransferPayload(version: 2, devices: [tv], rooms: self.registry.rooms,
                starredApps: [tv.id: ["com.example.Player", "com.example.Missing"]],
                remotePreferences: SharedRemotePreferences(layout: .expandedAppleTVRemote, useTouchpad: true))
            incomingTransfer = try? RoomTransfer.encrypt(fixture, code: "cable lunar velvet walnut")
        }
        if CommandLine.arguments.contains("--ui-testing-apps") {
            let first = RemoteDevice(id: "apple:ui-apps-living", kind: .appleTV, name: "Living Apple TV", address: "192.168.1.30", port: 49153,
                serviceName: "ui-apps-living", serviceType: "_companion-link._tcp", serviceDomain: "local.")
            let second = RemoteDevice(id: "apple:ui-apps-family", kind: .appleTV, name: "Family Apple TV", address: "192.168.1.31", port: 49153,
                serviceName: "ui-apps-family", serviceType: "_companion-link._tcp", serviceDomain: "local.")
            self.registry.devices = [first, second]
            let receiving = CommandLine.arguments.contains("--ui-testing-import-last-export")
            let selected = CommandLine.arguments.contains("--ui-testing-apps-family") ? second : first
            self.registry.rooms = [RoomProfile(id: "ui-apps-room", name: receiving ? "Receiver Room" : "Living Room", appleID: selected.id)]
            selectedRoomID = "ui-apps-room"; appleID = selected.id; samsungID = nil
            if CommandLine.arguments.contains("--ui-testing-transfer-rooms"), !receiving {
                let living = RemoteDevice(id: "ui-share-living-samsung", kind: .samsung, name: "Living Samsung", address: "192.168.1.40", port: 8002)
                let family = RemoteDevice(id: "ui-share-family-samsung", kind: .samsung, name: "Family Samsung", address: "192.168.1.41", port: 8002)
                self.registry.devices += [living, family]
                self.registry.rooms = [RoomProfile(id: "ui-apps-room", name: "Living Room", samsungID: living.id, appleID: first.id),
                                       RoomProfile(id: "ui-share-family", name: "Family Room", samsungID: family.id, appleID: second.id)]
                samsungID = living.id
            }
            for device in self.registry.devices { connectionIntent.disconnect(device.id); states[device.id] = .connected }
            if receiving { incomingTransfer = UserDefaults.standard.data(forKey: "ui.syntheticExport") }
        }
        if CommandLine.arguments.contains("--ui-testing-room-sessions") {
            let livingApple = RemoteDevice(id: "ui-living-apple", kind: .appleTV, name: "Living Room", address: "127.0.0.1")
            let livingSamsung = RemoteDevice(id: "ui-living-samsung", kind: .samsung, name: "Living Room TV", address: "127.0.0.1")
            let familyApple = RemoteDevice(id: "ui-family-apple", kind: .appleTV, name: "Family Room", address: "127.0.0.1")
            let familySamsung = RemoteDevice(id: "ui-family-samsung", kind: .samsung, name: "Family Room TV", address: "127.0.0.1")
            self.registry = DeviceRegistry(devices: [livingApple, livingSamsung, familyApple, familySamsung], rooms: [
                RoomProfile(id: "ui-living", name: "Living Room", samsungID: livingSamsung.id, appleID: livingApple.id),
                RoomProfile(id: "ui-family", name: "Family Room", samsungID: familySamsung.id, appleID: familyApple.id)
            ])
            selectedRoomID = "ui-living"; appleID = livingApple.id; samsungID = livingSamsung.id
            for kind in [DeviceKind.appleTV, .samsung] {
                let device = selected(kind)!
                states[device.id] = .connected
                retainedDrivers[device.id] = driver(kind)
                sessionObservations[device.id] = UUID()
                uiSessionConnectCounts[device.id] = 1
            }
        }
        if CommandLine.arguments.contains("--ui-testing-wake-save") {
            let first = RemoteDevice(id: "ui-wake-tv", kind: .samsung, name: "Living Room TV", address: "192.168.1.50", port: 8002)
            let second = RemoteDevice(id: "ui-wake-other", kind: .samsung, name: "Family Room TV", address: "192.168.1.60", port: 8002, wakeMACAddress: "02:AA:BB:CC:DD:EE")
            self.registry = DeviceRegistry(devices: [first, second], rooms: [
                RoomProfile(id: "ui-wake-room", name: "Living Room", samsungID: first.id),
                RoomProfile(id: "ui-wake-family", name: "Family Room", samsungID: second.id)
            ])
            selectedRoomID = "ui-wake-room"; samsungID = first.id; appleID = nil
            connectionIntent.disconnect(first.id); connectionIntent.disconnect(second.id)
        }
        if CommandLine.arguments.contains("--ui-testing-wake-save-relaunch") {
            for device in self.registry.devices { connectionIntent.disconnect(device.id) }
        }
        if CommandLine.arguments.contains("--ui-testing-transfer") {
            let tv = RemoteDevice(id: "transfer-test-tv", kind: .samsung, name: "Shared Bedroom TV", address: "192.168.1.50", port: 8002)
            let fixture = RoomTransferPayload(devices: [tv], rooms: [RoomProfile(id: "transfer-test-room", name: "Shared Bedroom", samsungID: tv.id)])
            incomingTransfer = try? RoomTransfer.encrypt(fixture, code: "cable lunar velvet walnut")
        } else if CommandLine.arguments.contains("--ui-testing-transfer-legacy") {
            // Synthetic, independently encrypted v1 setup; contains no pairing credentials.
            let fixture = #"{"format":"roomremote","version":1,"salt":"AQIDBAUGBwgJCgsMDQ4PEA==","sealed":"AQIDBAUGBwgJCgsM0PeCHs2cJ0Avpi+3BBJgD2w+XFX7Pbs9yHdsqfxeNuNNmKqxv4QlDOr0fLki+xR0PyoZWrc8V07RVkR9Es8wHg3549pcGI0sHZMQ2O6ACFyPdWPu4sbBixEfRPLhzzhTV2P1SuxPjQiOTM7d5/27y2bK/UoY3AiM6EtzDoeTrQD7LBqlVsLd+ODcqlqkcHCg8CNvgVySpuF4crKXOx72VGAcvecrqeqNaQgNgd7hl26kWoDlcNvQTSMl26aonal9A+k37tscAzOcNBIUHf2cehwWRStGolBhyajF0h77A6Q8Qp+w0Z1CAOOIEd00Y3gQ8sT/h9Lti4aPLV13HLUccA=="}"#
            incomingTransfer = Data(fixture.utf8)
        }
        #endif
        automaticRoomEnabled = AutoRoomPolicy.isAvailable && UserDefaults.standard.bool(forKey: AutoRoomPolicy.preferenceKey)
        if !AutoRoomPolicy.isAvailable {
            UserDefaults.standard.removeObject(forKey: AutoRoomPolicy.preferenceKey)
        }
    }

    var devices: [RemoteDevice] { registry.devices }
    var rooms: [RoomProfile] { registry.rooms }
    var currentRoom: RoomProfile { rooms.first { $0.id == selectedRoomID } ?? rooms.first ?? RoomProfile(id: "no-room", name: "No room") }
    var isCustomPair: Bool { currentRoom.samsungID != samsungID || currentRoom.appleID != appleID }
    var roomMenuSelection: RoomMenuSelection { automaticRoomEnabled ? .automatic : .room(selectedRoomID) }
    var roomMenuTitle: String {
        guard automaticRoomEnabled else { return currentRoom.name }
        if autoResolvedRoomID != nil { return "Auto · \(currentRoom.name)" }
        return autoRoomSearching ? "Auto · Searching…" : "Auto · Offline"
    }

    func selectRoomMenuItem(_ item: RoomMenuSelection) {
        switch item {
        case .automatic:
            guard AutoRoomPolicy.isAvailable else { return }
            automaticRoomEnabled = true
            UserDefaults.standard.set(true, forKey: AutoRoomPolicy.preferenceKey)
            beginAutoRoomSelection(force: true)
        case .room(let id): selectRoom(id)
        }
    }

    private func leaveAutomaticRoom() {
        cancelAutoRoomSearch()
        automaticRoomEnabled = false
        autoResolvedRoomID = nil
        UserDefaults.standard.set(false, forKey: AutoRoomPolicy.preferenceKey)
    }

    func selected(_ kind: DeviceKind) -> RemoteDevice? {
        registry.device(kind == .samsung ? samsungID : appleID, kind: kind)
    }
    func state(_ kind: DeviceKind) -> DeviceConnectionState {
        selected(kind).flatMap { states[$0.id] } ?? .disconnected
    }
    func name(_ kind: DeviceKind) -> String { selected(kind)?.name ?? "No \(kind.title) selected" }

    func selectNavigationTarget(_ kind: DeviceKind) {
        guard navigationTarget != kind else { return }
        navigationTarget = kind
        // Switching tabs is an explicit request to use this remote. Preserve
        // healthy and pending sessions; release only this TV's disconnect hold.
        guard active, let device = selected(kind),
              ConnectionIntent().allowsAutomaticConnection(to: device.id, state: state(kind)) else { return }
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing-retry") { uiNavigationRequests += kind.title + ";" }
        #endif
        connectionIntent.requestConnection(to: device.id)
        connectAutomatically(kind)
    }

    func selectRoom(_ id: String) {
        guard rooms.contains(where: { $0.id == id }) else { return }
        leaveAutomaticRoom()
        applyRoom(id)
    }

    private func applyRoom(_ id: String) {
        guard let plan = registry.selectionPlan(for: id, currentRoomID: selectedRoomID,
            samsungID: samsungID, appleID: appleID, navigationTarget: navigationTarget), !plan.isNoOp else { return }
        initialRoomSetup.reset()
        selectedRoomID = id
        registry.lastRoomID = id
        if plan.changesSamsung { applySelection(plan.samsungID, kind: .samsung) }
        if plan.changesApple { applySelection(plan.appleID, kind: .appleTV) }
        navigationTarget = plan.navigationTarget
        persist()
    }

    func setSelection(_ id: String?, kind: DeviceKind, preservingInitialRoomSetup: Bool = false) {
        leaveAutomaticRoom()
        applySelection(id, kind: kind, preservingInitialRoomSetup: preservingInitialRoomSetup)
    }

    private func applySelection(_ id: String?, kind: DeviceKind, preservingInitialRoomSetup: Bool = false,
                                connectAfterSelection: Bool = true) {
        guard id == nil || registry.device(id, kind: kind) != nil else { return }
        // Re-selecting a dropdown item is not a connection retry. Keep in-flight
        // gestures, tools, setup and the driver's healthy session intact.
        guard id != (kind == .samsung ? samsungID : appleID) else { return }
        if !preservingInitialRoomSetup { initialRoomSetup.reset() }
        let old = selected(kind)
        let oldDriver = driver(kind)
        let retainOld = old.map { states[$0.id]?.isConnected == true } ?? false
        if let old, retainOld { retainedDrivers[old.id] = oldDriver }
        _ = epochs[kind]!.advance()
        let previous = connectionTasks[kind]
        previous?.cancel()
        cancelCommands(for: kind)
        if kind == .appleTV {
            closeApps()
            installedApps = []
            appsError = nil
            appsLaunchingID = nil
            appsLaunchRequest = UUID()
            keyboardReady = false
            toolsRequest = UUID()
            toolsLoading = false
        }
        if let old, !retainOld {
            states[old.id] = .disconnected
            sessionObservations.removeValue(forKey: old.id)
            retainedDrivers.removeValue(forKey: old.id)
        }
        if kind == .samsung {
            samsungID = id
            samsung = id.flatMap { retainedDrivers[$0] as? SamsungDriver } ?? SamsungDriver(vault: vault)
        } else {
            appleID = id
            apple = id.flatMap { retainedDrivers[$0] as? AppleTVDriver } ?? AppleTVDriver(vault: vault)
        }
        if let id { retainedDrivers[id] = driver(kind) }
        let epoch = epochs[kind]!.value
        connectionTasks[kind] = Task { [weak self] in
            if let previous { await previous.value }
            if !retainOld { await oldDriver.disconnect() }
            guard let self else { return }
            guard self.epochs[kind]!.accepts(epoch), !Task.isCancelled, self.active, id != nil, connectAfterSelection else { return }
            self.connectAutomatically(kind)
        }
        feedback = id == nil ? "No \(kind.title) selected." : "Selected \(name(kind))."
    }

    func connect(_ kind: DeviceKind) {
        guard active, let device = selected(kind) else { return }
        cancelAutoRoomSearch()
        connectionIntent.requestConnection(to: device.id)
        startConnection(kind, to: device)
    }

    private func connectAutomatically(_ kind: DeviceKind) {
        guard active, let device = selected(kind),
              connectionIntent.allowsAutomaticConnection(to: device.id, state: state(kind)) else { return }
        startConnection(kind, to: device, savedPairingOnly: automaticRoomEnabled)
    }

    private func startConnection(_ kind: DeviceKind, to device: RemoteDevice, savedPairingOnly: Bool = false) {
        lastConnectionAttempt[kind] = .now
        if kind == .appleTV { closeApps() }
        _ = epochs[kind]!.advance()
        let epoch = epochs[kind]!.value
        let observation = UUID()
        connectionObservationTokens[kind] = observation
        sessionObservations[device.id] = observation
        let previous = connectionTasks[kind]
        previous?.cancel()
        cancelCommands(for: kind)
        states[device.id] = .connecting
        let driver = driver(kind)
        retainedDrivers[device.id] = driver
        connectionTasks[kind] = Task { [weak self] in
            if let previous { await previous.value }
            guard let self, self.epochs[kind]!.accepts(epoch), self.active,
                  self.selected(kind)?.id == device.id, !Task.isCancelled else { return }
            #if DEBUG
            if CommandLine.arguments.contains("--ui-testing-room-sessions") {
                self.uiSessionConnectCounts[device.id, default: 0] += 1
                self.uiLostSessionIDs.remove(device.id)
                self.connectionStateHandler(kind, device: device, epoch: epoch, observation: observation)(.connected)
                return
            }
            if CommandLine.arguments.contains("--ui-testing-retry") {
                if kind == .appleTV { self.uiAppleRetryCount += 1 } else { self.uiSamsungRetryCount += 1 }
                self.uiRetryCounts = "\(self.uiAppleRetryCount),\(self.uiSamsungRetryCount)"
                self.states[device.id] = .failed("Synthetic offline TV")
                return
            }
            #endif
            await driver.disconnect()
            guard self.epochs[kind]!.accepts(epoch), self.active,
                  self.selected(kind)?.id == device.id, !Task.isCancelled else { return }
            do {
                let handler = self.connectionStateHandler(kind, device: device, epoch: epoch, observation: observation)
                if savedPairingOnly { try await driver.connectUsingSavedPairing(to: device, onState: handler) }
                else { try await driver.connect(to: device, onState: handler) }
            } catch {
                guard self.epochs[kind]!.accepts(epoch), !Task.isCancelled else { return }
                self.states[device.id] = .failed(error.localizedDescription)
                if kind == .appleTV, self.shortcutPhase.isInProgress {
                    self.cancelShortcutWork()
                    self.shortcutError = error.localizedDescription
                    self.shortcutPhase = .failed
                }
                self.feedback = error.localizedDescription
            }
        }
    }

    private func connectionStateHandler(_ kind: DeviceKind, device: RemoteDevice,
                                        epoch: UInt64, observation: UUID) -> @Sendable (DeviceConnectionState) -> Void {
        { [weak self] state in
            Task { @MainActor in
                guard let self, self.registry.device(device.id, kind: kind) != nil,
                      self.sessionObservations[device.id] == observation else { return }
                self.states[device.id] = state
                // An unselected room keeps receiving transport events, but may
                // not open setup sheets or interrupt controls in the active room.
                guard self.selected(kind)?.id == device.id else { return }
                if kind == .appleTV, !state.isConnected, self.shortcutPhase.isInProgress {
                    self.cancelShortcutWork()
                    self.shortcutError = state.title
                    self.shortcutPhase = .failed
                }
                if self.active, state == .awaitingPin, self.sheet == nil { self.sheet = .pin(device.id) }
                if self.active, case .trustRequired(let fingerprint) = state, self.sheet == nil { self.sheet = .trust(device.id, fingerprint) }
                if state == .connected { self.feedback = "Connected to \(device.name)." }
                if case .failed(let reason) = state { self.feedback = reason }
            }
        }
    }

    func send(_ action: RemoteAction, to kind: DeviceKind? = nil) {
        let target = kind ?? navigationTarget
        guard active, let device = selected(target), state(target).isConnected else {
            feedback = "Connect the selected \(target.title) first."
            return
        }
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing-home") {
            uiHomeActions.append(action.rawValue)
            feedback = uiHomeActions.joined(separator: ",")
            return
        }
        #endif
        guard let request = commandRequests.begin(for: target) else { return }
        let epoch = epochs[target]!.value
        let driver = driver(target)
        commandTasks[target] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.commandRequests.finish(request, for: target) {
                    self.commandTasks.removeValue(forKey: target)
                }
            }
            guard self.commandRequests.accepts(request, for: target), self.active,
                  self.epochs[target]!.accepts(epoch), self.selected(target)?.id == device.id,
                  !Task.isCancelled else { return }
            self.schedulePowerStatusRefresh(action, to: target, device: device, epoch: epoch, driver: driver)
            let delivery = await RemoteCommandDelivery.perform(action, to: target) {
                try await driver.send(action, toDeviceID: device.id)
            }
            guard self.commandRequests.accepts(request, for: target), self.active,
                  self.epochs[target]!.accepts(epoch), self.selected(target)?.id == device.id,
                  !Task.isCancelled else { return }
            if delivery.refreshAppleTVConnection {
                // One fresh session for future presses; connect never replays
                // this action. It invalidates this request and old callbacks.
                self.alertMessage = RemoteCommandDelivery.recoveryMessage
                self.connect(.appleTV)
                self.feedback = RemoteCommandDelivery.recoveryMessage
            } else if let error = delivery.error {
                self.feedback = error.localizedDescription
                self.alertMessage = error.localizedDescription
            } else {
                self.feedback = "Sent to \(device.name)."
            }
        }
    }

    var homeButtonBinding: HomeButtonBinding? {
        guard active, let device = selected(navigationTarget), state(navigationTarget).isConnected else { return nil }
        return HomeButtonBinding(kind: navigationTarget, deviceID: device.id, epoch: epochs[navigationTarget]!.value)
    }

    func sendHomeGesture(_ gesture: HomeButtonBinding.Gesture, binding: HomeButtonBinding) {
        guard homeButtonBinding == binding, let action = binding.action(for: gesture) else { return }
        send(action, to: binding.kind)
    }

    @discardableResult
    func wakeSamsung(expectedDeviceID: String? = nil) -> UUID? {
        guard active, samsungWakeDeviceID == nil, let device = selected(.samsung) else { return nil }
        guard expectedDeviceID == nil || expectedDeviceID == device.id else { return nil }
        clearWakeConfirmation()
        let target: SamsungWakeTarget
        do { target = try SamsungWakeTarget(device: device) }
        catch {
            samsungWakeError = error.localizedDescription
            return nil
        }
        guard let request = commandRequests.begin(for: .samsung) else {
            samsungWakeError = "Wait for the current Samsung action, then try again."
            return nil
        }
        let epoch = epochs[.samsung]!.value
        samsungWakeDeviceID = device.id
        samsungWakeError = nil
        let cleanup = wakeCleanupTask
        commandTasks[.samsung] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.commandRequests.finish(request, for: .samsung) {
                    self.commandTasks.removeValue(forKey: .samsung)
                    self.samsungWakeDeviceID = nil
                }
            }
            // Cancellation completes the old sender's gate/continuation before
            // a freshly saved MAC can start its next datagram on this actor.
            if let cleanup { await cleanup.value }
            guard self.wakeIsCurrent(request, target: target, epoch: epoch), !Task.isCancelled else { return }
            self.wakeCleanupTask = nil
            do {
                #if DEBUG
                if CommandLine.arguments.contains("--ui-testing-wake-save") || CommandLine.arguments.contains("--ui-testing-wake-save-relaunch") {
                    // Observe the real target and packet; never open a socket.
                    self.uiWakeSendCount += 1
                    self.uiWakeTargetDescription = "\(self.uiWakeSendCount) · \(target.deviceID) · \(target.address) · \(target.macAddress) · \(target.packetData.count) bytes"
                } else {
                    try await self.samsungWakeSender.send(to: target)
                }
                #else
                try await self.samsungWakeSender.send(to: target)
                #endif
                guard self.wakeIsCurrent(request, target: target, epoch: epoch), !Task.isCancelled else { return }
                let message = "Wake request sent to \(device.name)."
                self.showWakeConfirmation(message)
            } catch {
                guard self.wakeIsCurrent(request, target: target, epoch: epoch), !Task.isCancelled else { return }
                self.samsungWakeError = error.localizedDescription
            }
        }
        return request
    }

    private func showWakeConfirmation(_ message: String) {
        clearWakeConfirmation()
        let request = UUID()
        wakeMessageRequest = request
        samsungWakeMessage = message
        feedback = message
        wakeMessageTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, !Task.isCancelled, self.wakeMessageRequest == request else { return }
            self.clearWakeConfirmation()
        }
    }

    private func clearWakeConfirmation() {
        wakeMessageTask?.cancel()
        wakeMessageTask = nil
        wakeMessageRequest = nil
        if let message = samsungWakeMessage, feedback == message { feedback = "" }
        samsungWakeMessage = nil
    }

    func cancelSamsungWake(request: UUID) {
        guard samsungWakeDeviceID != nil, commandRequests.accepts(request, for: .samsung) else { return }
        cancelCommands(for: .samsung)
    }

    private func wakeIsCurrent(_ request: UUID, target: SamsungWakeTarget, epoch: UInt64) -> Bool {
        active && commandRequests.accepts(request, for: .samsung) && epochs[.samsung]!.accepts(epoch) &&
            selected(.samsung).map { target.matches($0) } == true
    }

    func setSamsungWakeMAC(_ raw: String?, for deviceID: String) throws {
        var updated = registry
        _ = try updated.setSamsungWakeMAC(raw, for: deviceID)
        // Save also repairs persistence and releases stale wake ownership when
        // the user resaves the same canonical address.
        try saveRegistryPreferences(updated)
        if samsungWakeDeviceID == deviceID { cancelCommands(for: .samsung) }
        if samsungID == deviceID { clearWakeConfirmation(); samsungWakeError = nil }
    }

    func updateTVNetwork(address: String, macAddress: String?, for deviceID: String, name: String? = nil) throws {
        guard let original = devices.first(where: { $0.id == deviceID }) else { throw RemoteFailure.message("This TV is no longer saved.") }
        var updated = registry
        try updated.updateTVNetwork(address: address, macAddress: macAddress, for: deviceID, name: name)
        try saveRegistryPreferences(updated)
        cancelAutoRoomSearch()
        if samsungWakeDeviceID == deviceID { cancelCommands(for: .samsung) }
        if samsungID == deviceID { clearWakeConfirmation(); samsungWakeError = nil }
        // The old socket must not send commands to the previous IP after Save.
        // Reconnect uses the same pairing identity and certificate checks.
        if selected(original.kind)?.id == deviceID,
           updated.devices.first(where: { $0.id == deviceID })?.address != original.address {
            stopConnection(original.kind)
            connectAutomatically(original.kind)
        } else if updated.devices.first(where: { $0.id == deviceID })?.address != original.address {
            sessionObservations.removeValue(forKey: deviceID)
            states[deviceID] = .disconnected
            if let old = retainedDrivers.removeValue(forKey: deviceID) { Task { await old.disconnect() } }
        }
    }

    func submitPIN(_ pin: String, deviceID: String) async throws {
        guard selected(.appleTV)?.id == deviceID, state(.appleTV) == .awaitingPin else { throw RemoteFailure.message("This pairing request is no longer active.") }
        let epoch = epochs[.appleTV]!.value
        do { try await apple.submitPIN(pin, forDeviceID: deviceID) }
        catch {
            guard epochs[.appleTV]!.accepts(epoch), selected(.appleTV)?.id == deviceID, active else { return }
            throw error
        }
        guard epochs[.appleTV]!.accepts(epoch), selected(.appleTV)?.id == deviceID else { return }
        if sheet?.id == "pin.\(deviceID)" { sheet = nil }
    }

    func confirmTrust(deviceID: String, fingerprint: String) async throws {
        guard selected(.samsung)?.id == deviceID else { throw RemoteFailure.message("This TV is no longer selected.") }
        let epoch = epochs[.samsung]!.value
        if sheet?.id == "trust.\(deviceID)" { sheet = nil }
        do { try await samsung.trustCurrentCertificate(forDeviceID: deviceID, expectedFingerprint: fingerprint) }
        catch {
            guard epochs[.samsung]!.accepts(epoch), selected(.samsung)?.id == deviceID, active else { return }
            throw error
        }
        guard epochs[.samsung]!.accepts(epoch) else { return }
    }

    func cancelSetup(_ kind: DeviceKind) {
        initialRoomSetup.reset()
        stopConnection(kind)
        sheet = nil
    }

    /// Stop only this TV's transport while keeping its saved setup and the
    /// current Settings screen available for an explicit Connect retry.
    func disconnect(_ kind: DeviceKind) {
        guard let device = selected(kind) else { return }
        connectionIntent.disconnect(device.id)
        stopConnection(kind)
        feedback = "Disconnected from \(device.name)."
    }

    private func stopConnection(_ kind: DeviceKind) {
        if kind == .appleTV {
            closeApps()
            keyboardReady = false
            toolsRequest = UUID()
            toolsLoading = false
        }
        _ = epochs[kind]!.advance()
        let previous = connectionTasks[kind]
        previous?.cancel()
        cancelCommands(for: kind)
        if let device = selected(kind) {
            states[device.id] = .disconnected
            sessionObservations.removeValue(forKey: device.id)
            retainedDrivers.removeValue(forKey: device.id)
        }
        let driver = driver(kind)
        connectionTasks[kind] = Task {
            if let previous { await previous.value }
            await driver.disconnect()
        }
    }

    func addSamsung(name: String, address: String, wakeMACAddress: String = "") throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = try SamsungProtocol.privateHost(address)
        guard !trimmed.isEmpty, trimmed.count <= 80, !address.isEmpty else { throw RemoteFailure.message("Enter a TV name and its local IP address.") }
        var device = devices.first(where: { $0.kind == .samsung && $0.address == address }) ??
            RemoteDevice(kind: .samsung, name: trimmed, address: address, port: 8002)
        if !wakeMACAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let mac = try SamsungWakeOnLAN.normalizedMAC(wakeMACAddress)
            if devices.contains(where: { $0.id == device.id }) { try setSamsungWakeMAC(mac, for: device.id) }
            device.wakeMACAddress = mac
        }
        try registerForPairing(device)
        sheet = nil
    }

    func addApple(_ device: RemoteDevice) {
        guard device.kind == .appleTV else { return }
        do { try registerForPairing(device); sheet = nil }
        catch { alertMessage = error.localizedDescription }
    }

    private func registerForPairing(_ device: RemoteDevice) throws {
        let assigned = try registry.addForPairing(device, roomID: selectedRoomID, initialSetup: &initialRoomSetup)
        connectionIntent.requestConnection(to: device.id)
        let wasSelected = selected(device.kind)?.id == device.id
        setSelection(device.id, kind: device.kind, preservingInitialRoomSetup: true)
        if wasSelected, !state(device.kind).isConnected { connect(device.kind) }
        persist()
        feedback = assigned ? "Added \(device.name) to \(currentRoom.name)." :
            "Selected \(name(device.kind)) for pairing. Saved room assignments are unchanged."
    }

    func discoverAppleTVs() {
        discoveryTask?.cancel()
        let request = UUID()
        discoveryRequest = request
        isDiscovering = true
        discoveredAppleTVs = []
        discoveryTask = Task { [weak self] in
            defer { if self?.discoveryRequest == request { self?.isDiscovering = false } }
            do {
                let devices = try await AppleTVDriver.discover()
                guard !Task.isCancelled, self?.discoveryRequest == request else { return }
                self?.discoveredAppleTVs = devices
                if devices.isEmpty { self?.feedback = "No Apple TVs found. Check home Wi-Fi and Local Network access in Settings." }
            } catch { if !Task.isCancelled, self?.discoveryRequest == request { self?.alertMessage = error.localizedDescription } }
        }
    }

    func saveAssignments() {
        initialRoomSetup.reset()
        var room = currentRoom
        room.samsungID = samsungID
        room.appleID = appleID
        do { try registry.saveRoom(room); persist(); feedback = "Saved devices for \(room.name)." }
        catch { alertMessage = error.localizedDescription }
    }

    func saveRoom(_ room: RoomProfile) throws { try registry.saveRoom(room); initialRoomSetup.reset(); persist() }
    func deleteRoom(_ id: String) {
        guard rooms.contains(where: { $0.id == id }) else { return }
        initialRoomSetup.reset()
        registry.rooms.removeAll { $0.id == id }
        if selectedRoomID == id {
            if let room = rooms.first { selectRoom(room.id) }
            else {
                leaveAutomaticRoom()
                selectedRoomID = "no-room"
                applySelection(nil, kind: .samsung)
                applySelection(nil, kind: .appleTV)
            }
        }
        persist()
    }

    func renameDevice(_ id: String, name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 80, let index = devices.firstIndex(where: { $0.id == id }) else { return }
        registry.devices[index].name = value
        persist()
    }

    func removeDevice(_ device: RemoteDevice) async {
        initialRoomSetup.reset()
        let target = retainedDrivers[device.id]
        sessionObservations.removeValue(forKey: device.id)
        states[device.id] = .disconnected
        if selected(device.kind)?.id == device.id { setSelection(nil, kind: device.kind) }
        retainedDrivers.removeValue(forKey: device.id)
        do {
            await target?.disconnect()
            if device.kind == .samsung { try await (target as? SamsungDriver ?? SamsungDriver(vault: vault)).forgetPairing(for: device) }
            else { try await (target as? AppleTVDriver ?? AppleTVDriver(vault: vault)).forgetPairing(for: device) }
            registry.removeDevice(device.id)
            states.removeValue(forKey: device.id)
            persist()
        } catch { alertMessage = error.localizedDescription }
    }

    func rePair(_ device: RemoteDevice) async {
        initialRoomSetup.reset()
        guard registry.device(device.id, kind: device.kind) != nil else { return }
        if selected(device.kind)?.id != device.id { setSelection(device.id, kind: device.kind) }
        cancelSetup(device.kind)
        let epoch = epochs[device.kind]!.value
        do {
            var target = device
            if device.kind == .appleTV, device.serviceName != nil {
                // A reset Apple TV advertises a new identity at the same address.
                feedback = "Looking for \(device.name) on Wi-Fi…"
                let discovered = (try? await AppleTVDriver.discover()) ?? []
                guard epochs[device.kind]!.accepts(epoch), active, devices.contains(where: { $0.id == device.id }) else { return }
                target = AppleTVDriver.resetReplacement(for: device, in: discovered, savedIDs: Set(devices.map(\.id))) ?? device
            }
            if device.kind == .samsung { try await samsung.forgetPairing(for: device) }
            else { try await apple.forgetPairing(for: device) }
            guard epochs[device.kind]!.accepts(epoch), active, devices.contains(where: { $0.id == device.id }) else { return }
            if target.id != device.id {
                try await apple.forgetPairing(for: target)
                guard epochs[device.kind]!.accepts(epoch), active, devices.contains(where: { $0.id == device.id }) else { return }
                try registry.replaceAppleIdentity(device.id, with: target)
                states.removeValue(forKey: device.id)
                sessionObservations.removeValue(forKey: device.id)
                retainedDrivers.removeValue(forKey: device.id)
                persist()
            }
            connectionIntent.requestConnection(to: target.id)
            if selected(device.kind)?.id == target.id { connect(device.kind) }
            else { setSelection(target.id, kind: device.kind) }
            if target.id != device.id { feedback = "\(target.name) was reset. Enter the code shown on the TV." }
        } catch {
            guard epochs[device.kind]!.accepts(epoch), active else { return }
            alertMessage = error.localizedDescription
        }
    }

    func openKeyboard() {
        guard !shortcutPhase.isInProgress, active, let device = selected(.appleTV), state(.appleTV).isConnected else { feedback = "Connect the selected Apple TV first."; return }
        closeApps()
        sheet = .keyboard
        toolsLoading = true
        keyboardReady = false
        let epoch = epochs[.appleTV]!.value
        let request = UUID()
        toolsRequest = request
        Task {
            defer { if toolsRequest == request { toolsLoading = false } }
            guard active, epochs[.appleTV]!.accepts(epoch), toolsRequest == request,
                  selected(.appleTV)?.id == device.id, !Task.isCancelled else { return }
            do { let ready = try await apple.keyboardAvailable(toDeviceID: device.id); if epochs[.appleTV]!.accepts(epoch), toolsRequest == request { keyboardReady = ready } }
            catch { if epochs[.appleTV]!.accepts(epoch), toolsRequest == request { alertMessage = error.localizedDescription } }
        }
    }

    func connectionAction(_ kind: DeviceKind) {
        guard let device = selected(kind) else { return }
        switch state(kind) {
        case .awaitingPin: sheet = .pin(device.id)
        case .trustRequired(let fingerprint): sheet = .trust(device.id, fingerprint)
        case .connected, .connecting, .awaitingApproval: disconnect(kind)
        default: connect(kind)
        }
    }

    func connectionActionTitle(_ kind: DeviceKind) -> String {
        switch state(kind) {
        case .connected: "Disconnect"
        case .awaitingPin: "Enter code"
        case .trustRequired: "Review TV"
        case .connecting, .awaitingApproval: "Cancel"
        default: "Connect"
        }
    }

    func sendText(_ text: String, toDeviceID expectedID: String) async throws {
        guard !shortcutPhase.isInProgress else { throw RemoteFailure.message("Finish or cancel the shortcut first.") }
        guard active, keyboardReady, state(.appleTV).isConnected else { throw RemoteFailure.message("Open a text field on the selected Apple TV first.") }
        guard let device = selected(.appleTV) else { throw RemoteFailure.message("Choose an Apple TV first.") }
        guard expectedID == device.id else { throw CancellationError() }
        let epoch = epochs[.appleTV]!.value
        try await apple.sendText(text, toDeviceID: device.id)
        if epochs[.appleTV]!.accepts(epoch), selected(.appleTV)?.id == device.id, !Task.isCancelled {
            feedback = "Text sent to \(device.name)."
            if sheet?.id == "keyboard" { sheet = nil }
        }
    }

    func openApps() {
        guard !shortcutPhase.isInProgress, active, let device = selected(.appleTV), state(.appleTV).isConnected else { feedback = "Connect the selected Apple TV first."; return }
        if sheet?.id != "apps" || appsPresentationID == nil { appsPresentationID = UUID() }
        appsLoadTask?.cancel()
        appsLaunchTask?.cancel()
        appsLaunchRequest = UUID()
        appsLaunchingID = nil
        appsError = nil
        sheet = .apps
        appsDeviceID = device.id
        installedApps = []
        appsLoaded = false
        toolsLoading = true
        let epoch = epochs[.appleTV]!.value
        let request = UUID()
        toolsRequest = request
        appsLoadTask = Task {
            defer { if toolsRequest == request { toolsLoading = false } }
            guard active, epochs[.appleTV]!.accepts(epoch), toolsRequest == request,
                  selected(.appleTV)?.id == device.id, !Task.isCancelled else { return }
            do {
                let apps: [RemoteAppInfo]
                #if DEBUG
                if CommandLine.arguments.contains("--ui-testing-screenshots") {
                    // A fuller demo library for README screenshots.
                    apps = [RemoteAppInfo(id: "com.comcast.cim.x2", name: "Stream"),
                            RemoteAppInfo(id: "com.google.ios.youtube", name: "YouTube"),
                            RemoteAppInfo(id: "com.netflix.Netflix", name: "Netflix"),
                            RemoteAppInfo(id: "com.apple.TVWatchList", name: "TV"),
                            RemoteAppInfo(id: "com.apple.TVMusic", name: "Music"),
                            RemoteAppInfo(id: "com.apple.TVPhotos", name: "Photos"),
                            RemoteAppInfo(id: "com.apple.podcasts", name: "Podcasts"),
                            RemoteAppInfo(id: "com.apple.Fitness", name: "Fitness"),
                            RemoteAppInfo(id: "com.apple.Arcade", name: "Arcade")]
                } else if CommandLine.arguments.contains("--ui-testing-apps") {
                    apps = [RemoteAppInfo(id: "com.comcast.cim.x2", name: "Stream"),
                            RemoteAppInfo(id: "com.example.Stream", name: "Stream"),
                            RemoteAppInfo(id: "com.apple.TVMusic", name: "Music")]
                } else { apps = try await apple.listApps(toDeviceID: device.id) }
                #else
                apps = try await apple.listApps(toDeviceID: device.id)
                #endif
                guard active, epochs[.appleTV]!.accepts(epoch), toolsRequest == request,
                      selected(.appleTV)?.id == device.id, !Task.isCancelled else { return }
                installedApps = apps
                appsLoaded = true
            } catch {
                guard active, epochs[.appleTV]!.accepts(epoch), toolsRequest == request,
                      selected(.appleTV)?.id == device.id, !Task.isCancelled else { return }
                appsError = error.localizedDescription
            }
        }
    }

    func appLibrary(search: String = "") -> AppLibrarySections {
        guard appsDeviceID == appleID, appsPresentationID != nil else { return AppLibrarySections(apps: [], starredIDs: []) }
        return AppLibrarySections(apps: installedApps, starredIDs: appleID.map { registry.effectiveStarredAppIDs(for: $0) } ?? [], search: search)
    }

    func isAppStarred(_ appID: String) -> Bool {
        guard let appleID else { return false }
        return registry.effectiveStarredAppIDs(for: appleID).contains(appID)
    }

    var universalStarsEnabled: Bool { registry.universalStarsEnabled }

    func setUniversalStarsEnabled(_ enabled: Bool) {
        guard registry.universalStarsEnabled != enabled else { return }
        do {
            var updated = registry
            updated.setUniversalStarsEnabled(enabled)
            try saveRegistryPreferences(updated)
        } catch { alertMessage = error.localizedDescription }
    }

    func toggleAppStar(_ app: RemoteAppInfo) {
        guard let appleID, appsDeviceID == appleID, appsPresentationID != nil,
              !toolsLoading, installedApps.contains(app) else { return }
        do {
            var updated = registry
            if try updated.setEffectiveAppStarred(!isAppStarred(app.id), appID: app.id, for: appleID) { try saveRegistryPreferences(updated) }
        } catch { alertMessage = error.localizedDescription }
    }

    func appStarImportSources(for destinationID: String) -> [RemoteDevice] {
        devices.filter { $0.kind == .appleTV && $0.id != destinationID }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
    }

    func installedStarCount(from sourceID: String) -> Int {
        let stars = registry.starredAppIDs(for: sourceID)
        return Set(installedApps.map(\.id)).intersection(stars).count
    }

    func importAppStars(from sourceID: String, to destinationID: String) throws -> Int {
        guard !universalStarsEnabled else { throw RemoteFailure.message("Stars are already shared across your Apple TVs.") }
        guard appleID == destinationID, appsDeviceID == destinationID, appsPresentationID != nil,
              appsLoaded, !toolsLoading else { throw RemoteFailure.message("Load Apps for the intended Apple TV before importing stars.") }
        var updated = registry
        let added = try updated.importAppStars(from: sourceID, to: destinationID)
        if added > 0 { try saveRegistryPreferences(updated) }
        return added
    }

    private func saveRegistryPreferences(_ updated: DeviceRegistry) throws {
        var saved = updated
        saved.lastRoomID = selectedRoomID
        let data = try JSONEncoder().encode(saved)
        try RegistryStorage.save(saved, in: RegistryStorage.directory())
        UserDefaults.standard.set(data, forKey: persistenceKey)
        registry = saved
    }

    func launch(_ app: RemoteAppInfo) {
        guard !shortcutPhase.isInProgress, active, appsDeviceID == appleID, appsLaunchingID == nil, !toolsLoading, installedApps.contains(app),
              let device = selected(.appleTV), state(.appleTV).isConnected else { return }
        let epoch = epochs[.appleTV]!.value
        let request = UUID()
        appsLaunchRequest = request
        appsLaunchingID = app.id
        appsError = nil
        appsLaunchTask = Task {
            defer { if appsLaunchRequest == request { appsLaunchingID = nil } }
            guard active, epochs[.appleTV]!.accepts(epoch), appsLaunchRequest == request,
                  selected(.appleTV)?.id == device.id, !Task.isCancelled else { return }
            do {
                try await apple.launchApp(id: app.id, toDeviceID: device.id)
                guard active, epochs[.appleTV]!.accepts(epoch), appsLaunchRequest == request,
                      selected(.appleTV)?.id == device.id, !Task.isCancelled else { return }
                if sheet?.id == "apps" { sheet = nil }
                feedback = "Opened \(app.name) on \(device.name)."
            } catch {
                guard active, epochs[.appleTV]!.accepts(epoch), appsLaunchRequest == request,
                      selected(.appleTV)?.id == device.id, !Task.isCancelled else { return }
                appsError = error.localizedDescription
            }
        }
    }

    func closeApps(presentation expected: UUID? = nil) {
        if let expected, appsPresentationID != expected { return }
        appsPresentationID = nil
        appsDeviceID = nil
        appsLoaded = false
        appsLoadTask?.cancel()
        appsLaunchTask?.cancel()
        toolsRequest = UUID()
        appsLaunchRequest = UUID()
        toolsLoading = false
        appsLaunchingID = nil
    }

    func openShortcuts() {
        closeShortcuts()
        closeApps()
        shortcutsPresentationID = UUID()
        sheet = .shortcuts
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing-shortcut-success") {
            shortcutTarget = RemoteAppInfo(id: AppRestartWorkflow.xfinityAppID, name: "Xfinity Stream")
            shortcutPhase = .completed
        }
        #endif
    }

    func restartXfinityStream() {
        startRestart(RemoteAppInfo(id: AppRestartWorkflow.xfinityAppID, name: "Xfinity Stream"))
    }

    func chooseCurrentAppToRestart() {
        guard !shortcutPhase.isInProgress, active, let device = selected(.appleTV), state(.appleTV).isConnected,
              sheet?.id == "shortcuts", shortcutsPresentationID != nil else { return }
        guard let request = commandRequests.begin(for: .appleTV) else {
            shortcutError = "Wait for the current Apple TV action, then try again."
            shortcutPhase = .failed
            return
        }
        shortcutRequest = request
        let epoch = epochs[.appleTV]!.value
        shortcutEpoch = epoch
        restartChoiceDeviceID = device.id
        restartChoiceEpoch = epoch
        restartAppChoices = []
        restartChoiceError = nil
        shortcutError = nil
        showRestartAppChoice = true
        shortcutPhase = .loadingApps
        commandTasks[.appleTV] = Task { [weak self] in
            guard let self else { return }
            do {
                let apps = try await self.apple.listApps(toDeviceID: device.id)
                guard self.shortcutIsCurrent(request, deviceID: device.id, epoch: epoch), !Task.isCancelled else { return }
                self.restartAppChoices = apps.filter { AppRestartWorkflow.validAppID($0.id) }
                self.releaseShortcut(request)
                self.shortcutPhase = .idle
            } catch {
                guard self.shortcutIsCurrent(request, deviceID: device.id, epoch: epoch), !Task.isCancelled else { return }
                self.restartChoiceError = error.localizedDescription
                self.releaseShortcut(request)
                self.shortcutPhase = .failed
            }
        }
    }

    func restartChosenCurrentApp(_ app: RemoteAppInfo) {
        guard !shortcutPhase.isInProgress, restartChoiceDeviceID == appleID,
              restartChoiceEpoch == epochs[.appleTV]!.value, restartAppChoices.contains(app),
              active, state(.appleTV).isConnected else {
            restartChoiceError = "The Apple TV connection changed. Reload its apps before restarting."
            return
        }
        clearRestartAppChoice()
        startRestart(app)
    }

    func cancelRestartAppChoice() {
        if shortcutPhase == .loadingApps { cancelShortcutWork(); shortcutPhase = .idle }
        clearRestartAppChoice()
    }

    private func clearRestartAppChoice() {
        showRestartAppChoice = false
        restartAppChoices = []
        restartChoiceError = nil
        restartChoiceDeviceID = nil
        restartChoiceEpoch = nil
    }

    private func startRestart(_ app: RemoteAppInfo) {
        guard !shortcutPhase.isInProgress, active, let device = selected(.appleTV), state(.appleTV).isConnected,
              sheet?.id == "shortcuts", shortcutsPresentationID != nil,
              AppRestartWorkflow.validAppID(app.id) else { return }
        guard let request = commandRequests.begin(for: .appleTV) else {
            shortcutError = "Wait for the current Apple TV action, then try again."
            shortcutPhase = .failed
            return
        }
        shortcutRequest = request
        let epoch = epochs[.appleTV]!.value
        shortcutEpoch = epoch
        shortcutTarget = app
        shortcutError = nil
        shortcutPhase = .preparing
        commandTasks[.appleTV] = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.apple.restartApp(app, toDeviceID: device.id) { [weak self] in
                    guard let self else { throw CancellationError() }
                    try await self.markShortcutClosing(request, deviceID: device.id, epoch: epoch)
                }
                guard self.shortcutIsCurrent(request, deviceID: device.id, epoch: epoch), !Task.isCancelled else { return }
                self.shortcutPhase = .completed
                self.releaseShortcut(request)
            } catch {
                guard self.shortcutIsCurrent(request, deviceID: device.id, epoch: epoch), !Task.isCancelled else { return }
                self.failShortcut(error, request: request)
            }
        }
    }

    private func markShortcutClosing(_ request: UUID, deviceID: String, epoch: UInt64) throws {
        guard shortcutIsCurrent(request, deviceID: deviceID, epoch: epoch), !Task.isCancelled else { throw CancellationError() }
        shortcutPhase = .closing
    }

    func closeShortcuts(presentation expected: UUID? = nil) {
        if let expected, shortcutsPresentationID != expected { return }
        cancelShortcutWork()
        clearRestartAppChoice()
        shortcutsPresentationID = nil
        shortcutPhase = .idle
        shortcutError = nil
        shortcutTarget = nil
    }

    private func cancelShortcutWork() {
        if let request = shortcutRequest {
            commandTasks[.appleTV]?.cancel()
            releaseShortcut(request)
        }
    }

    private func discardShortcutRequest(_ request: UUID) {
        guard shortcutRequest == request else { return }
        cancelShortcutWork()
        shortcutPhase = .idle
        shortcutError = nil
    }

    private func failShortcut(_ error: any Error, request: UUID) {
        guard shortcutRequest == request else { return }
        let refresh = RemoteCommandDelivery.shouldRefresh(after: error, action: .home, to: .appleTV)
        releaseShortcut(request)
        if refresh { connect(.appleTV) }
        shortcutError = refresh
            ? error.localizedDescription + " Reconnecting… The shortcut stopped; start it again after reconnecting."
            : error.localizedDescription
        shortcutPhase = .failed
    }

    private func shortcutIsCurrent(_ request: UUID, deviceID: String, epoch: UInt64) -> Bool {
        shortcutRequest == request && commandRequests.accepts(request, for: .appleTV) && active &&
            epochs[.appleTV]!.accepts(epoch) && appleID == deviceID && state(.appleTV).isConnected &&
            sheet?.id == "shortcuts" && shortcutsPresentationID != nil
    }

    private func releaseShortcut(_ request: UUID) {
        guard shortcutRequest == request else { return }
        if commandRequests.finish(request, for: .appleTV) { commandTasks.removeValue(forKey: .appleTV) }
        shortcutRequest = nil
        shortcutEpoch = nil
    }

    private func startStatusMonitor() {
        statusTask?.cancel()
        let request = UUID()
        statusRequest = request
        statusTask = Task { [weak self] in
            var verify = true
            while !Task.isCancelled {
                guard await self?.refreshConnectionIndicators(request: request, verify: verify) == true else { return }
                verify = false
                do { try await Task.sleep(for: AutoRoomPolicy.statusInterval) } catch { return }
            }
        }
    }

    private func schedulePowerStatusRefresh(_ action: RemoteAction, to kind: DeviceKind,
                                            device: RemoteDevice, epoch: UInt64, driver: any RemoteDriver) {
        guard PowerConnectionRefresh.shouldCheck(action, to: kind) else { return }
        powerStatusTasks[kind]?.cancel()
        let request = UUID()
        let lifecycle = statusRequest
        let observation = connectionObservationTokens[kind]
        powerStatusRequests[kind] = request
        powerStatusTasks[kind] = Task { [weak self] in
            await PowerConnectionRefresh.run(isCurrent: { [weak self] in
                guard let self else { return false }
                return self.active && self.statusRequest == lifecycle &&
                    self.powerStatusRequests[kind] == request && self.selected(kind)?.id == device.id &&
                    self.epochs[kind]!.accepts(epoch) && self.connectionObservationTokens[kind] == observation
            }, observe: {
                await driver.connectionIsConnected(toDeviceID: device.id)
            }, update: { [weak self] connected in
                guard let self else { return }
                let current = self.state(kind)
                let refreshed = AutoRoomPolicy.refreshedState(current, transportConnected: connected)
                if refreshed != current { self.states[device.id] = refreshed }
            })
            guard let self, self.powerStatusRequests[kind] == request else { return }
            self.powerStatusTasks.removeValue(forKey: kind)
            self.powerStatusRequests.removeValue(forKey: kind)
        }
    }

    private func refreshConnectionIndicators(request: UUID, verify: Bool = false) async -> Bool {
        guard active, statusRequest == request, !Task.isCancelled else { return false }
        var sessions = retainedDrivers
        for kind in [DeviceKind.appleTV, .samsung] {
            if let device = selected(kind) { sessions[device.id] = driver(kind) }
        }
        let checks = sessions.filter { states[$0.key]?.isConnected == true }
        let observations = sessionObservations
        await withTaskGroup(of: (String, Bool).self) { group in
            for (id, driver) in checks {
                #if DEBUG
                if self.usesSyntheticConnections {
                    let connected = !self.uiLostSessionIDs.contains(id) && (id != "ui-apple-status" || self.uiObservedAppleConnected)
                    group.addTask { (id, connected) }
                    continue
                }
                #endif
                group.addTask { (id, verify ? await driver.verifyConnection(toDeviceID: id) : await driver.connectionIsConnected(toDeviceID: id)) }
            }
            for await (id, connected) in group {
                guard active, statusRequest == request, !Task.isCancelled,
                      sessionObservations[id] == observations[id],
                      let current = states[id] else { continue }
                let refreshed = AutoRoomPolicy.refreshedState(current, transportConnected: connected)
                if refreshed != current { states[id] = refreshed }
            }
        }
        guard active, statusRequest == request, !Task.isCancelled else { return false }
        if !transferBusy, !isDiscovering, !shortcutPhase.isInProgress, autoRoomTask == nil {
            if automaticRoomEnabled { beginAutoRoomSelection(force: false, reconnectSelectedPair: true) }
            else {
                for kind in [DeviceKind.appleTV, .samsung] {
                    if let last = lastConnectionAttempt[kind], last.duration(to: .now) < AutoRoomPolicy.retryInterval { continue }
                    connectAutomatically(kind)
                }
            }
        }
        return true
    }

    #if DEBUG
    func loseLivingConnectionOnNextReturn() {
        guard CommandLine.arguments.contains("--ui-testing-room-sessions") else { return }
        uiLoseLivingOnReturn = true
        // Hold automatic recovery only in this indicator-isolation fixture.
        connectionIntent.disconnect("ui-living-apple")
    }

    func recordUITestExport(_ data: Data) {
        guard CommandLine.arguments.contains("--ui-testing-apps") else { return }
        UserDefaults.standard.set(data, forKey: "ui.syntheticExport")
    }

    func simulateObservedConnectionLoss() {
        guard CommandLine.arguments.contains("--ui-testing-status-refresh") else { return }
        uiObservedAppleConnected = false
        // Isolate indicator observation from the separate retry-loop UI case.
        connectionIntent.disconnect("ui-apple-status")
    }
    #endif

    private func cancelAutoRoomSearch() {
        autoRoomRequest = UUID()
        autoRoomTask?.cancel()
        autoRoomTask = nil
        autoRoomSearching = false
    }

    private func beginAutoRoomSelection(force: Bool, reconnectSelectedPair: Bool = false) {
        guard active, automaticRoomEnabled, autoRoomTask == nil, sheet == nil,
              !transferBusy, !isDiscovering, commandTasks.isEmpty, !shortcutPhase.isInProgress else { return }
        let candidates = AutoRoomPolicy.candidates(registry: registry, preferredRoomID: selectedRoomID, intent: connectionIntent)
        let connectedIDs = Set(states.filter { $0.value.isConnected }.map(\.key))
        if let roomID = AutoRoomPolicy.connectedRoom(candidates: candidates, deviceIDs: connectedIDs) {
            if autoResolvedRoomID != roomID { autoResolvedRoomID = roomID }
            applyRoom(roomID)
            if force || reconnectSelectedPair {
                for kind in [DeviceKind.appleTV, .samsung] { connectAutomatically(kind) }
            }
            return
        }
        let pending = [DeviceKind.appleTV, .samsung].filter {
            switch state($0) {
            case .connecting, .awaitingApproval, .awaitingPin, .trustRequired: true
            default: false
            }
        }
        if !pending.isEmpty {
            guard force else { return }
            for kind in pending { stopConnection(kind) }
        }
        let now = ContinuousClock.now
        if !force, let lastAutoAttempt, lastAutoAttempt.duration(to: now) < AutoRoomPolicy.retryInterval { return }
        lastAutoAttempt = now
        guard !candidates.isEmpty else {
            autoResolvedRoomID = nil
            feedback = "Auto needs a paired TV assigned to a saved room."
            return
        }
        let request = UUID()
        autoRoomRequest = request
        autoRoomSearching = true
        let original = registry
        let vault = vault
        autoRoomTask = Task { [weak self] in
            let result = await AutoRoomRace.firstSuccess(targets: candidates, probe: { candidate -> AutoRoomConnection? in
                let device = candidate.device
                let driver: any RemoteDriver = device.kind == .appleTV
                    ? AppleTVDriver(vault: vault) : SamsungDriver(vault: vault)
                do {
                    try Task.checkCancellation()
                    try await driver.connectUsingSavedPairing(to: device, onState: { _ in })
                    guard !Task.isCancelled, await driver.connectionIsConnected(toDeviceID: device.id) else {
                        await driver.disconnect()
                        return nil
                    }
                    return AutoRoomConnection(device: device, driver: driver)
                } catch {
                    await driver.disconnect()
                    return nil
                }
            }, discard: { await $0.driver.disconnect() })
            guard let self else { if let result { await result.connection.driver.disconnect() }; return }
            defer {
                if self.autoRoomRequest == request { self.autoRoomTask = nil; self.autoRoomSearching = false }
            }
            guard self.active, self.automaticRoomEnabled, self.autoRoomRequest == request,
                  self.registry == original, self.sheet == nil, !Task.isCancelled else {
                if let result { await result.connection.driver.disconnect() }
                return
            }
            guard let result, let roomID = result.target.roomIDs.first,
                  self.rooms.contains(where: { $0.id == roomID }) else {
                self.autoResolvedRoomID = nil
                self.feedback = "Auto couldn’t connect to a paired TV in your saved rooms."
                return
            }
            // The main store takes ownership before the next suspension. After
            // this handoff, cancellation must not close a newer user connection
            // created on this same actor. Normal selection now owns its cleanup.
            await self.adoptAutoRoomConnection(result.connection, roomID: roomID, request: request)
        }
    }

    private func adoptAutoRoomConnection(_ winner: AutoRoomConnection, roomID: String, request: UUID) async {
        let kind = winner.device.kind
        let originalEpoch = epochs[kind]!.value
        let nextEpoch = originalEpoch &+ 1
        let observation = UUID()
        // This observer is gated by a token installed only at commit. A trial
        // that closes while adoption awaits cannot update a manual connection,
        // even if a concurrent room change happens to use the next epoch/ID.
        let observed = await winner.driver.observeEstablishedConnection(toDeviceID: winner.device.id,
            onState: connectionStateHandler(kind, device: winner.device, epoch: nextEpoch, observation: observation))
        guard observed, active, automaticRoomEnabled, autoRoomRequest == request,
              epochs[kind]!.accepts(originalEpoch), sheet == nil, !Task.isCancelled,
              let room = rooms.first(where: { $0.id == roomID }),
              (kind == .appleTV ? room.appleID : room.samsungID) == winner.device.id,
              registry.device(winner.device.id, kind: kind) == winner.device else {
            await winner.driver.disconnect()
            return
        }
        let oldDriver = driver(kind)
        let oldDevice = selected(kind)
        let keepOld = oldDevice.map { $0.id != winner.device.id && states[$0.id]?.isConnected == true } ?? false
        let previous = connectionTasks[kind]
        previous?.cancel()
        _ = epochs[kind]!.advance()
        connectionObservationTokens[kind] = observation
        cancelCommands(for: kind)
        if kind == .appleTV {
            closeApps()
            installedApps = []
            keyboardReady = false
            toolsRequest = UUID()
            toolsLoading = false
        }
        if let oldDevice {
            if keepOld { retainedDrivers[oldDevice.id] = oldDriver }
            else { sessionObservations.removeValue(forKey: oldDevice.id) }
        }
        sessionObservations[winner.device.id] = observation
        retainedDrivers[winner.device.id] = winner.driver
        if let winnerDriver = winner.driver as? AppleTVDriver {
            apple = winnerDriver
            appleID = winner.device.id
        } else if let winnerDriver = winner.driver as? SamsungDriver {
            samsung = winnerDriver
            samsungID = winner.device.id
        }
        // Ownership and the saved room pair change together without suspension.
        // After this point only normal selection can close this winner actor.
        states[winner.device.id] = .connected
        autoResolvedRoomID = roomID
        applyRoom(roomID)
        connectionTasks[kind] = Task {
            if let previous { await previous.value }
            if !keepOld { await oldDriver.disconnect() }
        }
        feedback = "Auto selected \(currentRoom.name)."
    }

    func setActive(_ value: Bool) {
        guard value != active else { return }
        active = value
        if value {
            #if DEBUG
            if uiLoseLivingOnReturn {
                uiLoseLivingOnReturn = false
                uiLostSessionIDs.insert("ui-living-apple")
            }
            #endif
            if let directory = try? RegistryStorage.directory(), let recovered = try? RegistryStorage.recover(registry, in: directory) {
                if recovered != registry { initialRoomSetup.reset(); registry = recovered; feedback = "Unassigned TVs from an interrupted import are available in Your TVs." }
            }
            if let url = queuedTransferURL { queuedTransferURL = nil; openTransfer(url) }
            startStatusMonitor()
            #if DEBUG
            if CommandLine.arguments.contains("--ui-testing-wake-confirmation") {
                // Local rendering fixture, used with --ui-testing-home. It
                // exercises the real banner expiry without sending a datagram.
                sheet = .power
                Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    guard let self, self.active, self.sheet?.id == "power" else { return }
                    self.showWakeConfirmation("Wake request sent to Living Room TV.")
                }
            }
            #endif
        } else {
            statusRequest = UUID()
            statusTask?.cancel()
            statusTask = nil
            cancelAutoRoomSearch()
            initialRoomSetup.reset()
            transferReadRequest = UUID()
            discoveryTask?.cancel()
            // Keep presentations and their drafts/navigation. Cancel transient
            // requests without destroying the installed-app snapshot or chooser.
            appsLoadTask?.cancel()
            appsLaunchTask?.cancel()
            appsLaunchRequest = UUID()
            appsLaunchingID = nil
            if sheet?.id == "apps", toolsLoading, !appsLoaded {
                appsError = "Loading paused. Tap Reload to continue."
            }
            keyboardReady = false
            toolsRequest = UUID()
            toolsLoading = false
            for kind in [DeviceKind.samsung, .appleTV] {
                if ConnectionLifecycle.preservesSessionOnBackground(state(kind)) {
                    // Keep this socket and its callback epoch. Cancel controls,
                    // not the connection; delayed results cannot own a new command.
                    cancelCommands(for: kind, preservingPresentation: true)
                } else {
                    stopConnection(kind)
                }
            }
        }
    }

    func openTransfer(_ url: URL) {
        guard active else { queuedTransferURL = url; return }
        let request = UUID()
        transferReadRequest = request
        Task {
            do {
                let data = try await Task.detached { try RoomTransfer.readFile(url) }.value
                guard transferReadRequest == request, active else { return }
                incomingTransfer = data
                sheet = .transfer
            } catch {
                guard transferReadRequest == request, active else { return }
                alertMessage = "The setup file could not be opened. \(error.localizedDescription)"
            }
        }
    }

    func clearIncomingTransfer() { incomingTransfer = nil }

    func transferPayload(selectedIDs: Set<String>,
                         includeStars: Bool = true, includeRemotePreferences: Bool = true,
                         includeRooms: Bool = false) async throws -> RoomTransferPayload {
        guard active, !transferBusy else { throw RoomTransfer.failure("Another transfer is in progress.") }
        transferBusy = true
        defer { transferBusy = false }
        let snapshot = registry
        let devices = snapshot.devices.filter { selectedIDs.contains($0.id) }
        var payload = RoomTransferPayload(devices: devices, rooms: [])
        if includeStars {
            payload.starredApps = Dictionary(uniqueKeysWithValues: devices.filter { $0.kind == .appleTV }.map {
                ($0.id, snapshot.starredAppIDs(for: $0.id))
            })
            if devices.contains(where: { $0.kind == .appleTV }) {
                payload.universalStars = SharedUniversalStars(enabled: snapshot.universalStarsEnabled, appIDs: snapshot.universalStarredAppIDs)
            }
        }
        if includeRemotePreferences { payload.remotePreferences = .current() }
        if payload.starredApps != nil || payload.remotePreferences != nil { payload.version = 2 }
        if payload.universalStars != nil { payload.version = 3 }
        if includeRooms {
            let ids = Set(devices.map(\.id))
            payload.rooms = snapshot.rooms.filter {
                $0.samsungID.map(ids.contains) == true || $0.appleID.map(ids.contains) == true
            }.map { room in
                var selected = room
                if !ids.contains(room.samsungID ?? "") { selected.samsungID = nil }
                if !ids.contains(room.appleID ?? "") { selected.appleID = nil }
                return selected
            }
            payload.version = 4
            payload.roomAssignmentsIncluded = true
        }
        try payload.validate()
        // Keep credentials local for both brands. A transferred Samsung token
        // can be refused on the other phone; it must obtain its own approval.
        guard active, !Task.isCancelled else { throw CancellationError() }
        try payload.validate()
        return payload
    }

    func importTransfer(_ incoming: RoomTransferPayload) async throws -> String {
        let payload = try incoming.deviceSetupOnly()
        guard active, !transferBusy else { throw RoomTransfer.failure("Another transfer is in progress.") }
        initialRoomSetup.reset()
        transferBusy = true
        defer { transferBusy = false }
        let directory = try RegistryStorage.directory()
        registry = try RegistryStorage.recover(registry, in: directory)
        let original = registry
        let plan = try RoomTransferPlan(payload: payload, existing: registry)
        try RegistryStorage.beginImport(plan.newDevices, in: directory)
        var imported: [RemoteDevice] = []
        do {
            for device in plan.newDevices {
                try Task.checkCancellation()
                guard active, registry == original else { throw CancellationError() }
                if let pairing = plan.samsungPairings.first(where: { $0.deviceID == device.id }) {
                    if try await samsung.importPairing(pairing, for: device) { imported.append(device) }
                }
            }
            guard active, !Task.isCancelled, registry == original else { throw CancellationError() }
            // Commit the full nonsecret registry to disk before retiring recovery.
            try RegistryStorage.save(plan.registry, in: directory)
            registry = plan.registry
            if !registry.rooms.contains(where: { $0.id == selectedRoomID }), let room = registry.rooms.first {
                adoptImportedRoom(room)
            } else if let room = registry.rooms.first(where: { $0.id == selectedRoomID }),
                      let previousRoom = original.rooms.first(where: { $0.id == selectedRoomID }),
                      previousRoom.samsungID == nil, previousRoom.appleID == nil,
                      (room.samsungID != previousRoom.samsungID || room.appleID != previousRoom.appleID) {
                adoptImportedRoom(room)
            }
            persist()
            payload.remotePreferences?.apply()
            try? RegistryStorage.finishImport(in: directory)
            var additions: [String] = []
            if !plan.newDevices.isEmpty { additions.append("\(plan.newDevices.count) TV\(plan.newDevices.count == 1 ? "" : "s")") }
            if plan.addedRoomCount > 0 { additions.append("\(plan.addedRoomCount) room group\(plan.addedRoomCount == 1 ? "" : "s")") }
            var message = additions.isEmpty ? "TVs and rooms are already saved." : "Added " + additions.joined(separator: " and ") + "."
            if plan.updatedRoomCount > 0 { message += " Set up \(plan.updatedRoomCount) empty room\(plan.updatedRoomCount == 1 ? "" : "s")." }
            if plan.copiedStarTVCount > 0 { message += " Copied starred apps for \(plan.copiedStarTVCount) Apple TV\(plan.copiedStarTVCount == 1 ? "" : "s")." }
            if payload.remotePreferences != nil { message += " Remote layout and pad copied." }
            if !plan.newDevices.isEmpty { message += " Pair each new TV on this iPhone." }
            feedback = message
            return message
        } catch {
            // Existing credentials never enter rollback. A durable nonsecret
            // journal makes every staged profile visible if cleanup is interrupted.
            for device in imported {
                if device.kind == .appleTV { try? await apple.forgetPairing(for: device) }
                else { try? await samsung.forgetPairing(for: device) }
            }
            if let recovered = try? RegistryStorage.recover(registry, in: directory) { registry = recovered; persist() }
            feedback = "Import did not finish. Check unassigned TVs in Your TVs and use Re-pair or Remove before retrying."
            throw error
        }
    }

    private func adoptImportedRoom(_ room: RoomProfile) {
        selectedRoomID = room.id
        // Reuse normal session/epoch handoff so a newly filled room cannot send
        // through the actor of a previously selected temporary TV.
        applySelection(room.samsungID, kind: .samsung, connectAfterSelection: false)
        applySelection(room.appleID, kind: .appleTV, connectAfterSelection: false)
        if navigationTarget == .appleTV, room.appleID == nil, room.samsungID != nil { navigationTarget = .samsung }
        if navigationTarget == .samsung, room.samsungID == nil, room.appleID != nil { navigationTarget = .appleTV }
    }

    private func driver(_ kind: DeviceKind) -> any RemoteDriver { kind == .samsung ? samsung : apple }
    private func cancelCommands(for kind: DeviceKind, preservingPresentation: Bool = false) {
        let cancelledWake = kind == .samsung && samsungWakeDeviceID != nil
        powerStatusTasks.removeValue(forKey: kind)?.cancel()
        powerStatusRequests.removeValue(forKey: kind)
        if kind == .samsung {
            samsungWakeDeviceID = nil
            clearWakeConfirmation()
            samsungWakeError = nil
        }
        if kind == .appleTV {
            let interrupted = shortcutPhase.isInProgress
            cancelShortcutWork()
            if preservingPresentation {
                if interrupted {
                    shortcutPhase = .failed
                    shortcutError = "Paused when you left the app. Start the shortcut again when ready."
                    if showRestartAppChoice { restartChoiceError = "Loading paused. Reload apps to continue." }
                }
            } else {
                clearRestartAppChoice()
                shortcutPhase = .idle
                shortcutError = nil
            }
        }
        commandRequests.cancel(for: kind)
        if let cancelled = commandTasks.removeValue(forKey: kind) {
            cancelled.cancel()
            if cancelledWake {
                let previous = wakeCleanupTask
                wakeCleanupTask = Task {
                    if let previous { await previous.value }
                    await cancelled.value
                }
            }
        }
    }
    private func persist() {
        registry.lastRoomID = selectedRoomID
        do {
            let directory = try RegistryStorage.directory()
            try RegistryStorage.save(registry, in: directory)
            UserDefaults.standard.set(try JSONEncoder().encode(registry), forKey: persistenceKey)
        }
        catch { alertMessage = "The room settings could not be saved." }
    }
}
