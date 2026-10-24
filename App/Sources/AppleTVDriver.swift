import Foundation
import CryptoKit
import SwiftATV

/// Direct, paired Companion control. Every selected target owns its connection
/// and its HAP identity pin; room names never serve as credential lookup keys.
actor AppleTVDriver: RemoteDriver {
    private struct PairingIndex: Codable {
        let deviceID: String
        let credentialKey: String
        let accessoryIdentity: Data
        let accessoryPublicKey: Data
    }
    private struct SavedPairing: Codable {
        let deviceID: String
        let accessoryIdentity: Data
        let accessoryPublicKey: Data
        let settings: ATVSettings
    }

    private let vault: KeychainVault
    private var selectedDevice: RemoteDevice?
    private var stateHandler: (@Sendable (DeviceConnectionState) -> Void)?
    private var service: CompanionService?
    private var pairing: CompanionPairingHandler?
    private var pairingSettings: ATVSettings?
    private var pairingCompletionToken: UUID?
    private var generation = UUID()
    private var connected = false
    private var commandTail: Task<Void, Error>?
    private var queuedCommands = 0
    private var pairingImportIDs: Set<String> = []
    private var pairingRemovalIDs: Set<String> = []
    private enum RestartPhase { case preparing, finishing }
    private var restart: (context: AppleAppRestartContext, phase: RestartPhase)?
    private var restartOperationID: UUID?

    init(vault: KeychainVault) { self.vault = vault }

    func connect(to device: RemoteDevice, onState: @escaping @Sendable (DeviceConnectionState) -> Void) async throws {
        try await connect(to: device, onState: onState, savedPairingOnly: false)
    }

    func connectUsingSavedPairing(to device: RemoteDevice, onState: @escaping @Sendable (DeviceConnectionState) -> Void) async throws {
        try await connect(to: device, onState: onState, savedPairingOnly: true)
    }

    func connectionIsConnected(toDeviceID id: String) -> Bool {
        selectedDevice?.id == id && connected && service != nil
    }

    func verifyConnection(toDeviceID id: String) async -> Bool {
        guard connectionIsConnected(toDeviceID: id), let service else { return false }
        let token = generation
        do {
            try await service.verifyConnection(timeout: 2)
            return generation == token && connectionIsConnected(toDeviceID: id)
        } catch {
            if Task.isCancelled { return connectionIsConnected(toDeviceID: id) }
            guard generation == token else { return false }
            connected = false
            stateHandler?(.disconnected)
            await closeConnections()
            return false
        }
    }

    func observeEstablishedConnection(toDeviceID id: String, onState: @escaping @Sendable (DeviceConnectionState) -> Void) -> Bool {
        guard connectionIsConnected(toDeviceID: id) else { return false }
        stateHandler = onState
        return true
    }

    private func connect(to device: RemoteDevice, onState: @escaping @Sendable (DeviceConnectionState) -> Void,
                         savedPairingOnly: Bool) async throws {
        try Task.checkCancellation()
        guard device.kind == .appleTV else { throw RemoteFailure.message("Choose an Apple TV.") }
        try requirePairingAvailable(device.id)
        let token = UUID()
        // Install this operation before any suspension. A slower earlier
        // connect cannot return from close and overwrite the newer target.
        generation = token
        commandTail?.cancel()
        commandTail = nil
        let previousStateHandler = stateHandler
        stateHandler = nil
        // Reserve the upcoming target across the awaited old-socket close;
        // passive import must not race a connect that has already started.
        selectedDevice = device
        await closeConnections()
        previousStateHandler?(.disconnected)
        try requireCurrent(token)
        selectedDevice = device
        stateHandler = onState
        onState(.connecting)
        do {
            let settings: ATVSettings
            if savedPairingOnly {
                guard let saved = try await savedSettings(for: device), saved.credentials(for: .companion) != nil else {
                    throw RemoteFailure.message("Auto requires an existing Apple TV pairing.")
                }
                settings = saved
            } else {
                settings = try await self.settings(for: device)
            }
            try requireCurrent(token)
            let endpoint = try await resolvedEndpoint(for: device, allowSavedEndpoint: settings.credentials(for: .companion) != nil)
            try requireCurrent(token)
            selectedDevice = endpoint
            if settings.credentials(for: .companion) == nil {
                try await startPairing(endpoint, settings: settings, token: token)
            } else {
                try await establish(endpoint, settings: settings, token: token)
            }
        } catch {
            if generation == token {
                onState(.failed(friendly(error)))
                await closeConnections()
            }
            throw error
        }
    }

    func beginPairing(for device: RemoteDevice, onState: @escaping @Sendable (DeviceConnectionState) -> Void) async throws {
        try Task.checkCancellation()
        // Explicit re-pairing is user-directed and replaces only this target.
        try await forgetPairing(for: device)
        try Task.checkCancellation()
        try await connect(to: device, onState: onState)
    }

    func submitPIN(_ pin: String, forDeviceID expectedID: String) async throws {
        try requireSelected(expectedID)
        guard pin.count == 4, pin.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw RemoteFailure.message("Enter the four digits shown on your Apple TV.")
        }
        guard let handler = pairing, let device = selectedDevice, var settings = pairingSettings else {
            throw RemoteFailure.message("Connect to an Apple TV to request a pairing code first.")
        }
        let token = generation
        guard pairingCompletionToken != token else { throw RemoteFailure.message("Pairing is already in progress.") }
        pairingCompletionToken = token
        defer { if pairingCompletionToken == token { pairingCompletionToken = nil } }
        stateHandler?(.connecting)
        do {
            try await handler.pin(pin)
            let result = try await handler.finish()
            try requireCurrent(token)
            let credentials = result.credentials
            guard credentials.ltpk.count == 32, credentials.ltsk.count == 32,
                  !credentials.atvIdentifier.isEmpty, !credentials.clientIdentifier.isEmpty else {
                throw RemoteFailure.message("Apple TV returned incomplete pairing credentials.")
            }
            settings.apply(result)
            try await save(settings: settings, credentials: credentials, for: device, token: token)
            try requireCurrent(token)
            await handler.close()
            try requireCurrent(token)
            pairing = nil
            pairingSettings = nil
            try await establish(device, settings: settings, token: token)
        } catch {
            if generation == token {
                stateHandler?(.failed(friendly(error)))
                await closeConnections()
            }
            throw error
        }
    }

    func disconnect() async {
        generation = UUID()
        commandTail?.cancel()
        commandTail = nil
        connected = false
        selectedDevice = nil
        let handler = stateHandler
        stateHandler = nil
        await closeConnections()
        handler?(.disconnected)
    }

    func forgetPairing(for device: RemoteDevice) async throws {
        try requirePairingAvailable(device.id)
        pairingRemovalIDs.insert(device.id)
        defer { pairingRemovalIDs.remove(device.id) }
        if selectedDevice?.id == device.id { await disconnect() }
        let indexKey = Self.indexKey(device.id)
        if let data = try await vault.data(forKey: indexKey),
           let index = try? JSONDecoder().decode(PairingIndex.self, from: data), index.deviceID == device.id,
           index.credentialKey.hasPrefix(Self.credentialPrefix(device.id)) {
            try await vault.delete(forKey: index.credentialKey)
        }
        try await vault.delete(forKey: indexKey)
    }

    /// Export only this explicitly supplied TV's pinned pairing. No arbitrary
    /// Keychain enumeration or new global controller identity is needed.
    func exportPairing(for device: RemoteDevice) async throws -> ApplePairingTransfer? {
        try Task.checkCancellation()
        guard device.kind == .appleTV else { throw RemoteFailure.message("Choose an Apple TV.") }
        try requirePairingAvailable(device.id)
        let token = generation
        guard let storedSettings = try await savedSettings(for: device) else { return nil }
        try requireCurrent(token)
        guard let serialized = storedSettings.credentials(for: .companion) else {
            throw RemoteFailure.message("The saved Apple TV pairing is incomplete.")
        }
        let credentials = try HAPCredentials.parse(serialized)
        let transfer = ApplePairingTransfer(deviceID: device.id,
            companionServiceIdentity: storedSettings.protocols.companion.identifier,
            accessoryIdentifier: credentials.atvIdentifier, accessoryPublicKey: credentials.ltpk,
            controllerPrivateKey: credentials.ltsk, controllerIdentifier: credentials.clientIdentifier,
            clientIdentity: storedSettings.clientIdentity)
        try ApplePairingTransfer.validate(transfer, for: device)
        return transfer
    }

    /// Import passive credentials for a new device profile only. Existing
    /// pairings and live connections are never replaced or activated here.
    func importPairing(_ transfer: ApplePairingTransfer, for device: RemoteDevice) async throws {
        try Task.checkCancellation()
        let validated = try transfer.validated(for: device)
        guard !pairingRemovalIDs.contains(device.id) else {
            throw RemoteFailure.message("This Apple TV pairing is being removed. Wait for it to finish.")
        }
        guard selectedDevice?.id != device.id else {
            throw RemoteFailure.message("Disconnect this Apple TV before importing its pairing.")
        }
        guard pairingImportIDs.insert(device.id).inserted else {
            throw RemoteFailure.message("This Apple TV pairing is already being imported.")
        }
        defer { pairingImportIDs.remove(device.id) }
        let token = generation
        guard try await vault.data(forKey: Self.indexKey(device.id)) == nil else {
            throw RemoteFailure.message("This Apple TV already has a saved pairing. Its existing pairing was preserved.")
        }
        try requireCurrent(token)
        guard selectedDevice?.id != device.id else { throw CancellationError() }
        try await save(settings: validated.settings, credentials: validated.credentials, for: device, token: token)
        // Publication is the import commit point. Return success even if the
        // caller was cancelled during the final Keychain await, so its restore
        // coordinator can record ownership and roll back this exact new device.
        // save() still rejects cancellation before publishing and cleans up its
        // unique unpublished credential record. Normal PIN pairing is unchanged.
    }

    func send(_ action: RemoteAction) async throws {
        guard let id = selectedDevice?.id else { throw RemoteFailure.message("Connect to your Apple TV first.") }
        try await send(action, toDeviceID: id)
    }

    func send(_ action: RemoteAction, toDeviceID expectedID: String) async throws {
        try requireSelected(expectedID)
        try requireRestartIdle()
        let token = generation
        guard connected, service != nil else { throw RemoteFailure.message("Connect to your Apple TV first.") }
        guard queuedCommands < 32 else { throw RemoteFailure.message("The Apple TV is catching up. Try again in a moment.") }
        let previous = commandTail
        queuedCommands += 1
        let task = Task { [weak self] in
            if let previous { _ = await previous.result }
            try Task.checkCancellation()
            guard let self else { throw CancellationError() }
            try await self.perform(action, token: token)
        }
        commandTail = task
        defer { queuedCommands -= 1 }
        try await task.value
    }

    func listApps() async throws -> [RemoteAppInfo] {
        guard let id = selectedDevice?.id else { throw RemoteFailure.message("Connect to your Apple TV first.") }
        return try await listApps(toDeviceID: id)
    }

    func listApps(toDeviceID expectedID: String) async throws -> [RemoteAppInfo] {
        try requireSelected(expectedID)
        let token = generation
        guard connected, let apps = service?.apps else { throw RemoteFailure.message("Connect to your Apple TV first.") }
        do {
            let result = try await apps.appList()
            try requireCurrent(token)
            return result.map { RemoteAppInfo(id: $0.identifier, name: $0.name ?? $0.identifier) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            try requireCurrent(token)
            if let atvError = error as? ATVError, case .operationTimeout(let context) = atvError,
               context.requestID == "FetchLaunchableApplicationsEvent" {
                throw RemoteFailure.message("Apple TV did not return its app list. Wake it, open Home, and retry.")
            }
            throw error
        }
    }

    func launchApp(id: String, toDeviceID expectedID: String) async throws {
        try requireSelected(expectedID)
        try requireRestartIdle()
        guard !id.isEmpty, id.utf8.count <= 512 else { throw RemoteFailure.message("Choose an Apple TV app.") }
        let token = generation
        guard connected, let apps = service?.apps else { throw RemoteFailure.message("Connect to your Apple TV first.") }
        do {
            try await apps.launchApp(bundleID: id)
            try requireCurrent(token)
        } catch {
            try requireCurrent(token)
            if let atvError = error as? ATVError, case .operationTimeout(let context) = atvError,
               context.requestID == "_launchApp" {
                throw RemoteFailure.message("Apple TV did not confirm the app launch. Check the TV and retry.")
            }
            throw error
        }
    }

    func keyboardAvailable() async throws -> Bool {
        guard let id = selectedDevice?.id else { return false }
        return try await keyboardAvailable(toDeviceID: id)
    }

    func keyboardAvailable(toDeviceID expectedID: String) async throws -> Bool {
        try requireSelected(expectedID)
        let token = generation
        guard connected, let keyboard = service?.keyboard else { return false }
        let text = try await keyboard.textGet()
        try requireCurrent(token)
        return text != nil
    }

    func sendText(_ text: String, toDeviceID expectedID: String) async throws {
        try requireSelected(expectedID)
        try requireRestartIdle()
        guard text.utf8.count <= 16_384 else { throw RemoteFailure.message("Send at most 16 KB of text at a time.") }
        let token = generation
        guard connected, let keyboard = service?.keyboard else { throw RemoteFailure.message("Connect to your Apple TV first.") }
        // Prove current focus again at send time: the cached UUID from opening
        // the keyboard can become stale when the TV changes text fields.
        guard try await keyboard.textGet() != nil else {
            throw RemoteFailure.message("Open a text field on this Apple TV before sending text.")
        }
        try requireCurrent(token)
        try await keyboard.textAppend(text)
        try requireCurrent(token)
    }

    func restartApp(_ app: RemoteAppInfo, toDeviceID expectedID: String,
                    onPrepared: @escaping @Sendable () async throws -> Void) async throws {
        try requireSelected(expectedID)
        guard AppRestartWorkflow.validAppID(app.id), connected, let originalService = service,
              let remote = originalService.remoteControl, let apps = originalService.apps,
              let touch = originalService.touch,
              originalService.capabilities?.capabilityInfo(.touch(.swipe)).state == .available else {
            throw RemoteFailure.message("Connect an Apple TV with available swipe support before restarting an app.")
        }
        guard restart == nil, restartOperationID == nil, queuedCommands == 0 else {
            throw RemoteFailure.message("Wait for the current Apple TV action to finish.")
        }
        let context = AppleAppRestartContext(deviceID: expectedID, sessionID: generation, appID: app.id)
        let operation = UUID()
        restart = (context, .preparing)
        restartOperationID = operation
        defer {
            if restartOperationID == operation { restartOperationID = nil }
            if restart?.context == context { restart = nil }
        }
        try await restartWorkflow(context, remote: remote, apps: apps, touch: touch).run { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.markRestartFinishing(context)
            try await onPrepared()
        }
    }

    private func markRestartFinishing(_ context: AppleAppRestartContext) throws {
        try requireRestartSession(context)
        restart = (context, .finishing)
    }

    private func requireRestartIdle() throws {
        guard restart == nil, restartOperationID == nil else {
            throw RemoteFailure.message("Finish or cancel the restart shortcut before sending another Apple TV action.")
        }
    }

    private func requireRestartSession(_ context: AppleAppRestartContext) throws {
        try requireSelected(context.deviceID)
        try requireCurrent(context.sessionID)
        guard connected, service != nil, AppRestartWorkflow.validAppID(context.appID),
              restart?.context == context else { throw CancellationError() }
    }

    private func restartWorkflow(_ context: AppleAppRestartContext,
        remote: CompanionRemoteControl, apps: CompanionApps, touch: CompanionTouch) -> AppRestartWorkflow {
        AppRestartWorkflow(context: context, supportsSwipe: true, steps: .init(
            validate: { [weak self] context in
                guard let self else { throw CancellationError() }
                try await self.requireRestartSession(context)
            },
            fetchAppIDs: { try await apps.appList().map(\.identifier) },
            launchApp: { try await apps.launchApp(bundleID: $0) },
            showSwitcher: { try await remote.home(action: .doubleTap) },
            wait: { try await Task.sleep(nanoseconds: $0) },
            touch: { point in
                let phase: TouchAction = switch point.phase {
                    case .press: .press
                    case .hold: .hold
                    case .release: .release
                }
                try await touch.action(x: point.x, y: point.y, mode: phase)
            },
            releaseOriginalTouch: { point in
                // A fresh task bypasses the cancelled caller, but captures only
                // the old touch sender. It cannot find/reconnect the new TV.
                let release = Task.detached {
                    try? await touch.action(x: point.x, y: point.y, mode: .release)
                }
                await release.value
            }
        ))
    }

    /// Companion TXT identifiers are stable across room renames and DHCP IP changes.
    static func discover() async throws -> [RemoteDevice] {
        let configurations = try await ATVClient.scan(timeout: 5, protocols: [.companion])
        return discoveredDevices(from: configurations)
    }

    private static func discoveredDevices(from configurations: [AppleTVConfiguration]) -> [RemoteDevice] {
        return configurations.compactMap { config in
            guard let service = config.service(for: .companion), service.enabled,
                  service.port > 0, service.port <= 65_535,
                  let identity = service.identifier ?? config.identifier,
                  !identity.isEmpty else { return nil }
            // Exclude Companion-advertising computers/phones when TXT metadata
            // proves they are not a TV. Unknown models remain available to pair.
            switch config.deviceInfo.model {
            case .homePod, .homePodMini, .homePod2, .airPortExpress, .airPortExpressGen2, .music:
                return nil
            default: break
            }
            if let model = config.deviceInfo.modelString,
               !model.hasPrefix("AppleTV"), config.deviceInfo.model == .unknown,
               config.deviceInfo.operatingSystem != .tvOS {
                return nil
            }
            return RemoteDevice(id: "apple:" + identity.lowercased(), kind: .appleTV,
                name: config.name, address: config.address, port: UInt16(service.port),
                serviceName: identity, serviceType: CompanionService.serviceType,
                serviceDomain: "local.", hardwareModel: config.deviceInfo.modelString)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Pure selection helper: a missing identity never substitutes a different
    /// room's Apple TV, even when that TV now occupies the saved IP address.
    static func matchingEndpoint(for expected: RemoteDevice, in discovered: [RemoteDevice], allowSavedEndpoint: Bool = false) throws -> RemoteDevice {
        guard expected.kind == .appleTV else { throw RemoteFailure.message("Choose an Apple TV.") }
        let matches = discovered.filter {
            $0.kind == .appleTV && $0.id == expected.id &&
            $0.serviceName?.lowercased() == expected.serviceName?.lowercased()
        }
        // A missed multicast advertisement must not block a saved pairing.
        // Pair-verify still authenticates the pinned accessory key at this IP.
        if matches.isEmpty, allowSavedEndpoint { return expected }
        guard matches.count == 1, var endpoint = matches.first else {
            throw RemoteFailure.message("This Apple TV was not found on Wi-Fi. Wake it and discover devices again.")
        }
        endpoint.name = expected.name
        return endpoint
    }

    /// A factory reset gives the Apple TV a new Companion identity. For an
    /// explicit Re-pair only, adopt the one unsaved Apple TV now at the saved
    /// IP address. Another saved TV is never taken over, and the new PIN on the
    /// TV screen confirms the choice before any credentials are saved.
    static func resetReplacement(for expected: RemoteDevice, in discovered: [RemoteDevice], savedIDs: Set<String>) -> RemoteDevice? {
        guard expected.kind == .appleTV, expected.id.hasPrefix("apple:"), expected.serviceName != nil,
              !discovered.contains(where: { $0.id == expected.id }) else { return nil }
        let candidates = discovered.filter {
            $0.kind == .appleTV && $0.address == expected.address && !savedIDs.contains($0.id)
        }
        guard candidates.count == 1, var replacement = candidates.first else { return nil }
        replacement.name = expected.name
        return replacement
    }

    private func resolvedEndpoint(for device: RemoteDevice, allowSavedEndpoint: Bool = false) async throws -> RemoteDevice {
        // Explicit manually entered endpoints have no advertised identity to
        // resolve. Existing pair-verify still pins their actual HAP identity.
        guard device.id.hasPrefix("apple:"), device.serviceName != nil else { return device }
        let configurations = try await ATVClient.scan(timeout: 3, protocols: [.companion])
        return try Self.matchingEndpoint(for: device, in: Self.discoveredDevices(from: configurations), allowSavedEndpoint: allowSavedEndpoint)
    }

    private func startPairing(_ device: RemoteDevice, settings: ATVSettings, token: UUID) async throws {
        let config = try configuration(for: device)
        let companionService = config.service(for: .companion)!
        let handler = try await CompanionPairingHandler.create(config: config, service: companionService, settings: settings)
        do {
            try requireCurrent(token)
            pairing = handler
            pairingSettings = settings
            try await handler.begin()
            try requireCurrent(token)
            stateHandler?(.awaitingPin)
        } catch {
            await handler.close()
            throw error
        }
    }

    private func establish(_ device: RemoteDevice, settings: ATVSettings, token: UUID) async throws {
        let config = try configuration(for: device)
        guard let serialized = settings.credentials(for: .companion) else {
            throw RemoteFailure.message("Pair this Apple TV first.")
        }
        let credentials = try HAPCredentials.parse(serialized)
        let connection = CompanionService(host: config.address,
            port: config.service(for: .companion)!.port,
            credentials: credentials, settings: settings,
            requestTimeout: 5, runtimeRequestTimeout: 5,
            onConnectionClosed: { [weak self] error in
                Task { await self?.connectionClosed(error: error, token: token) }
            })
        do {
            try requireCurrent(token)
            service = connection
            try await connection.setup()
            try requireCurrent(token)
            connected = true
            stateHandler?(.connected)
        } catch {
            await connection.close()
            throw error
        }
    }

    private func connectionClosed(error: Error?, token: UUID) {
        guard generation == token else { return }
        connected = false
        restart = nil
        stateHandler?(.failed(error.map(friendly) ?? "Apple TV disconnected. Connect again."))
    }

    private func closeConnections() async {
        let oldPairing = pairing
        let oldService = service
        pairing = nil
        pairingSettings = nil
        service = nil
        connected = false
        restart = nil
        await oldPairing?.close()
        await oldService?.close()
    }

    private func configuration(for device: RemoteDevice) throws -> AppleTVConfiguration {
        let address = device.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address.utf8.count <= 253,
              !address.contains("/"), !address.contains(" "), !address.contains("@"),
              address != "localhost", address != "127.0.0.1", address != "::1" else {
            throw RemoteFailure.message("Enter the Apple TV's local IP address or discover it on Wi-Fi.")
        }
        let port = Int(device.port ?? UInt16(CompanionService.defaultPort))
        guard port > 0 else { throw RemoteFailure.message("Apple TV's Companion port is invalid.") }
        return AppleTVConfiguration(address: address, name: device.name,
            services: [ServiceInfo(protocol: .companion, port: port,
                identifier: device.serviceName, pairingRequirement: .mandatory)],
            identifier: device.serviceName)
    }

    private func settings(for device: RemoteDevice) async throws -> ATVSettings {
        if let stored = try await savedSettings(for: device) { return stored }
        return ATVSettings(clientIdentity: try await controllerIdentity())
    }

    private func savedSettings(for device: RemoteDevice) async throws -> ATVSettings? {
        let indexKey = Self.indexKey(device.id)
        guard let indexData = try await vault.data(forKey: indexKey) else {
            return nil
        }
        let index = try JSONDecoder().decode(PairingIndex.self, from: indexData)
        guard index.deviceID == device.id,
              index.credentialKey.hasPrefix(Self.credentialPrefix(device.id)),
              let savedData = try await vault.data(forKey: index.credentialKey) else {
            throw RemoteFailure.message("Saved Apple TV pairing is incomplete. Use Pair again for this device.")
        }
        let saved = try JSONDecoder().decode(SavedPairing.self, from: savedData)
        guard saved.deviceID == device.id,
              saved.accessoryIdentity == index.accessoryIdentity,
              saved.accessoryPublicKey == index.accessoryPublicKey,
              let serialized = saved.settings.credentials(for: .companion) else {
            throw RemoteFailure.message("Saved Apple TV identity changed. Use Pair again for this device.")
        }
        let credentials = try HAPCredentials.parse(serialized)
        guard credentials.atvIdentifier == saved.accessoryIdentity,
              credentials.ltpk == saved.accessoryPublicKey,
              credentials.ltpk.count == 32, credentials.ltsk.count == 32 else {
            throw RemoteFailure.message("Saved Apple TV identity does not match its credentials. Use Pair again.")
        }
        return saved.settings
    }

    private func controllerIdentity() async throws -> ClientIdentitySettings {
        let key = "apple-controller-identity.v1"
        if let data = try await vault.data(forKey: key) {
            return try JSONDecoder().decode(ClientIdentitySettings.self, from: data)
        }
        // Locally generated identifiers identify this installation, never the TV.
        let bytes = Array(SHA256.hash(data: Data(UUID().uuidString.utf8)))
        let localMAC = ([UInt8(0x02)] + Array(bytes.prefix(5)))
            .map { String(format: "%02X", $0) }.joined(separator: ":")
        let localDevice = ([UInt8(0x02)] + Array(bytes.dropFirst(5).prefix(5)))
            .map { String(format: "%02X", $0) }.joined(separator: ":")
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let identity = ClientIdentitySettings(name: "Room Remote", macAddress: localMAC,
            deviceID: localDevice, operatingSystemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        try await vault.store(JSONEncoder().encode(identity), forKey: key)
        return identity
    }

    private func save(settings: ATVSettings, credentials: HAPCredentials, for device: RemoteDevice, token: UUID) async throws {
        try requireCurrent(token)
        let identityHash = SHA256.hash(data: credentials.atvIdentifier + credentials.ltpk)
            .map { String(format: "%02x", $0) }.joined()
        // A unique record per completed PIN attempt permits safe cleanup of
        // unpublished records without deleting a concurrent pairing's secret.
        let credentialKey = Self.credentialPrefix(device.id) + identityHash + "." + UUID().uuidString
        let saved = SavedPairing(deviceID: device.id, accessoryIdentity: credentials.atvIdentifier,
            accessoryPublicKey: credentials.ltpk, settings: settings)
        let index = PairingIndex(deviceID: device.id, credentialKey: credentialKey,
            accessoryIdentity: credentials.atvIdentifier, accessoryPublicKey: credentials.ltpk)
        let indexKey = Self.indexKey(device.id)
        let previousIndexData = try await vault.data(forKey: indexKey)
        try requireCurrent(token)
        try await vault.store(JSONEncoder().encode(saved), forKey: credentialKey)
        do {
            try requireCurrent(token)
            try await vault.store(JSONEncoder().encode(index), forKey: indexKey)
        } catch {
            // Only this attempt's unpublished key is deleted. Every name,
            // room, and another device's pairing remain outside this scope.
            try? await vault.delete(forKey: credentialKey)
            throw error
        }
        // Once published, a verified pairing remains useful for this exact
        // original device even if selection changes before reconnect setup.
        if let previousIndexData,
           let previous = try? JSONDecoder().decode(PairingIndex.self, from: previousIndexData),
           previous.deviceID == device.id,
           previous.credentialKey.hasPrefix(Self.credentialPrefix(device.id)),
           previous.credentialKey != credentialKey {
            try? await vault.delete(forKey: previous.credentialKey)
        }
    }

    private static func indexKey(_ id: String) -> String { "apple-pairing-index.v1." + id }
    private static func credentialPrefix(_ id: String) -> String { "apple-credentials.v1." + id + "." }
    private func requirePairingAvailable(_ id: String) throws {
        guard !pairingImportIDs.contains(id), !pairingRemovalIDs.contains(id) else {
            throw RemoteFailure.message("This Apple TV pairing is being updated. Wait for it to finish.")
        }
    }
    private func requireSelected(_ expectedID: String) throws {
        try Task.checkCancellation()
        guard selectedDevice?.id == expectedID else { throw CancellationError() }
    }

    private func requireCurrent(_ token: UUID) throws {
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
    }

    private func perform(_ action: RemoteAction, token: UUID) async throws {
        try requireCurrent(token)
        guard connected, let remote = service?.remoteControl else { throw RemoteFailure.message("Connect to your Apple TV first.") }
        switch action {
        case .up: try await remote.up(action: .singleTap)
        case .down: try await remote.down(action: .singleTap)
        case .left: try await remote.left(action: .singleTap)
        case .right: try await remote.right(action: .singleTap)
        case .select: try await remote.select(action: .singleTap)
        case .back: try await remote.menu(action: .singleTap)
        // The TV/Home key follows the TV's configurable destination. Holding
        // Back/Menu returns to the tvOS app grid independently of that setting.
        case .home: try await remote.menu(action: .hold)
        case .appSwitcher: try await remote.home(action: .doubleTap)
        case .controlCenter: try await remote.home(action: .hold)
        case .playPause: try await remote.playPause()
        case .volumeUp: try await remote.volumeUp()
        case .volumeDown: try await remote.volumeDown()
        case .wake: try await remote.wakeUp()
        case .sleep, .powerOff: try await remote.suspend()
        case .mute, .source, .powerToggle: throw RemoteFailure.message("Use the Samsung remote for TV power, mute, and input.")
        }
        try requireCurrent(token)
    }

    private func friendly(_ error: Error) -> String {
        if error is CancellationError { return "Connection cancelled." }
        if let error = error as? ATVError {
            switch error {
            case .authenticationFailed, .invalidCredentials:
                return "Apple TV pairing could not be verified. Use Pair again for this device."
            case .operationTimeout:
                return "Apple TV did not respond. Check Wi-Fi, wake it, and connect again."
            default: break
            }
        }
        return error.localizedDescription
    }
}
