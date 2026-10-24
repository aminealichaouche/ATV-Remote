import Foundation
import Network
import Security
import CryptoKit
import Darwin

/// Security's completion block predates Sendable. The lock makes its one-shot transfer
/// from the Security queue to this adapter's actor explicit, without sharing TLS trust objects.
private final class SamsungTLSDecision: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: sec_protocol_verify_complete_t?

    init(_ completion: @escaping sec_protocol_verify_complete_t) { self.completion = completion }
    func finish(_ allowed: Bool) {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(allowed)
    }
}

/// An original Samsung Tizen adapter. No commands are held for a later connection.
actor SamsungDriver: RemoteDriver {
    private struct PendingTrust {
        let device: RemoteDevice
        let fingerprint: Data
        let callback: @Sendable (DeviceConnectionState) -> Void
    }
    private struct PendingWrite {
        let id: UUID
        let action: RemoteAction
        let continuation: CheckedContinuation<Void, Error>
        let timeout: Task<Void, Never>
    }
    private struct PendingPing {
        let id: UUID
        var waiters: [UUID: CheckedContinuation<Bool, Never>]
        let timeout: Task<Void, Never>
    }
    private var pendingPing: PendingPing?

    private let vault: KeychainVault
    private let queue = DispatchQueue(label: "local.RoomRemote.samsung.transport")
    private var generation = UUID()
    private var connection: NWConnection?
    private var device: RemoteDevice?
    private var state: DeviceConnectionState = .disconnected
    private var stateCallback: (@Sendable (DeviceConnectionState) -> Void)?
    private var pendingTrust: PendingTrust?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var connectTimeout: Task<Void, Never>?
    private var pendingWrite: PendingWrite?
    private var clientName = ""
    private var pairingImports: Set<String> = []
    private var pairingRevisions: [String: UUID] = [:]
    private var savedPairingOnlyMode = false
    private var originalTrialToken: Data?
    private var originalTrialCertificate: Data?
    private var pendingTrialToken: String?

    init(vault: KeychainVault) { self.vault = vault }

    #if DEBUG
    /// Test an already established loopback WebSocket without TLS or Keychain setup.
    func installTestConnection(_ socket: NWConnection, for device: RemoteDevice) {
        precondition(device.address == "127.0.0.1")
        reset(notify: false)
        self.connection = socket
        self.device = device
        state = .connected
        receiveNext(attempt: generation)
    }
    #endif

    func connect(to device: RemoteDevice, onState: @escaping @Sendable (DeviceConnectionState) -> Void) async throws {
        try await connect(to: device, onState: onState, savedPairingOnly: false)
    }

    func connectUsingSavedPairing(to device: RemoteDevice, onState: @escaping @Sendable (DeviceConnectionState) -> Void) async throws {
        try await connect(to: device, onState: onState, savedPairingOnly: true)
    }

    func connectionIsConnected(toDeviceID id: String) -> Bool {
        guard device?.id == id, state.isConnected, let connection,
              case .ready = connection.state else { return false }
        return true
    }

    func verifyConnection(toDeviceID id: String) async -> Bool {
        guard connectionIsConnected(toDeviceID: id), let socket = connection else { return false }
        let attempt = generation
        let waiterID = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                if pendingPing != nil { pendingPing?.waiters[waiterID] = continuation; return }
                let pingID = UUID()
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    await self?.finishPing(pingID, attempt: attempt, connected: false)
                }
                pendingPing = PendingPing(id: pingID, waiters: [waiterID: continuation], timeout: timeout)
                let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
                metadata.setPongHandler(queue) { [weak self] error in
                    Task { await self?.finishPing(pingID, attempt: attempt, connected: error == nil) }
                }
                let context = NWConnection.ContentContext(identifier: pingID.uuidString, metadata: [metadata])
                socket.send(content: Data(pingID.uuidString.utf8), contentContext: context, isComplete: true,
                    completion: .contentProcessed { [weak self] error in
                        if error != nil { Task { await self?.finishPing(pingID, attempt: attempt, connected: false) } }
                    })
            }
        } onCancel: {
            Task { await self.cancelPingWaiter(waiterID, attempt: attempt) }
        }
        guard !Task.isCancelled, generation == attempt else { return connectionIsConnected(toDeviceID: id) }
        if !result { fail("The Samsung connection check timed out. Reconnecting when selected.", attempt: attempt) }
        return result && connectionIsConnected(toDeviceID: id)
    }

    private func finishPing(_ id: UUID, attempt: UUID, connected: Bool) {
        guard generation == attempt, let ping = pendingPing, ping.id == id else { return }
        pendingPing = nil
        ping.timeout.cancel()
        for waiter in ping.waiters.values { waiter.resume(returning: connected) }
    }

    private func cancelPingWaiter(_ id: UUID, attempt: UUID) {
        guard generation == attempt, let waiter = pendingPing?.waiters.removeValue(forKey: id) else { return }
        waiter.resume(returning: false)
        if pendingPing?.waiters.isEmpty == true {
            pendingPing?.timeout.cancel()
            pendingPing = nil
        }
    }

    private func cancelPing() {
        let ping = pendingPing
        pendingPing = nil
        ping?.timeout.cancel()
        if let ping { for waiter in ping.waiters.values { waiter.resume(returning: false) } }
    }

    func observeEstablishedConnection(toDeviceID id: String, onState: @escaping @Sendable (DeviceConnectionState) -> Void) async -> Bool {
        guard connectionIsConnected(toDeviceID: id) else { return false }
        let attempt = generation
        if savedPairingOnlyMode, let pendingTrialToken, let originalTrialToken, let originalTrialCertificate {
            do {
                guard !Task.isCancelled,
                      try await vault.refreshExistingToken(Data(pendingTrialToken.utf8),
                        forKey: SamsungProtocol.tokenKey(deviceID: id), expectedToken: originalTrialToken,
                        certificateKey: SamsungProtocol.certificateKey(deviceID: id), expectedCertificate: originalTrialCertificate),
                      generation == attempt, !Task.isCancelled else { return false }
            } catch { return false }
        }
        guard generation == attempt, connectionIsConnected(toDeviceID: id), !Task.isCancelled else { return false }
        savedPairingOnlyMode = false
        pendingTrialToken = nil
        originalTrialToken = nil
        originalTrialCertificate = nil
        stateCallback = onState
        return true
    }

    private func connect(to device: RemoteDevice, onState: @escaping @Sendable (DeviceConnectionState) -> Void,
                         savedPairingOnly: Bool) async throws {
        guard !pairingImports.contains(device.id) else {
            throw RemoteFailure.message("Finish importing this Samsung TV before connecting to it.")
        }
        reset(notify: false)
        savedPairingOnlyMode = savedPairingOnly
        guard device.kind == .samsung else { throw RemoteFailure.message("This is not a Samsung TV.") }
        let host = try SamsungProtocol.privateHost(device.address)
        guard device.port == nil || device.port == 8002 else {
            throw RemoteFailure.message("This Samsung adapter requires the secure Tizen remote port, 8002.")
        }
        let attempt = generation
        self.device = device
        stateCallback = onState
        clientName = SamsungProtocol.clientName(deviceID: device.id)
        update(.connecting)

        do {
            let pin = try await vault.data(forKey: SamsungProtocol.certificateKey(deviceID: device.id))
            let tokenData = try await vault.data(forKey: SamsungProtocol.tokenKey(deviceID: device.id))
            guard generation == attempt else { throw CancellationError() }
            if let pin, pin.count != SHA256.byteCount {
                throw RemoteFailure.message("The saved TV identity is invalid. Forget this TV's pairing and pair again.")
            }
            let token: String?
            if let tokenData {
                guard let decoded = String(data: tokenData, encoding: .utf8), SamsungProtocol.validToken(decoded) else {
                    throw RemoteFailure.message("The saved Samsung pairing token is invalid. Forget pairing and try again.")
                }
                token = decoded
            } else { token = nil }
            guard !savedPairingOnly || (pin != nil && token != nil) else {
                throw RemoteFailure.message("Auto requires an existing Samsung TV pairing.")
            }
            if savedPairingOnly {
                originalTrialToken = tokenData
                originalTrialCertificate = pin
            }
            let url = try SamsungProtocol.webSocketURL(host: host, clientName: clientName, token: token)
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            // A resumed TLS session must not bypass the per-connection identity decision.
            sec_protocol_options_set_tls_resumption_enabled(tls.securityProtocolOptions, false)
            sec_protocol_options_set_tls_tickets_enabled(tls.securityProtocolOptions, false)
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { [weak self] _, trust, complete in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first else {
                    complete(false)
                    return
                }
                let fingerprint = Data(SHA256.hash(data: SecCertificateCopyData(leaf) as Data))
                let decision = SamsungTLSDecision(complete)
                Task {
                    let allowed = await self?.verifyCertificate(fingerprint, savedPin: pin, attempt: attempt) ?? false
                    decision.finish(allowed)
                }
            }, queue)
            let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
            let webSocket = NWProtocolWebSocket.Options()
            webSocket.autoReplyPing = true
            webSocket.maximumMessageSize = SamsungProtocol.maximumFrameBytes
            parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
            let socket = NWConnection(to: .url(url), using: parameters)
            connection = socket
            socket.stateUpdateHandler = { [weak self] state in
                Task { await self?.connectionChanged(state, attempt: attempt) }
            }
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { continuation in
                    connectContinuation = continuation
                    connectTimeout = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(45)) } catch { return }
                        await self?.connectExpired(attempt: attempt)
                    }
                    socket.start(queue: queue)
                }
            } onCancel: {
                Task { await self.cancelAttempt(attempt) }
            }
        } catch {
            if generation == attempt {
                let message = (error as? RemoteFailure)?.localizedDescription ?? "Samsung connection was cancelled."
                reset(notify: false)
                update(.failed(message))
            }
            throw error
        }
    }

    /// Explicit first-use approval from the UI. A changed existing pin cannot enter this path.
    func trustCurrentCertificate(forDeviceID deviceID: String, expectedFingerprint: String? = nil) async throws {
        guard let pendingTrust, pendingTrust.device.id == deviceID, case .trustRequired = state else {
            throw RemoteFailure.message("There is no new TV identity waiting for confirmation.")
        }
        if let expectedFingerprint, expectedFingerprint != SamsungProtocol.formattedFingerprint(pendingTrust.fingerprint) {
            throw RemoteFailure.message("The TV identity changed while confirmation was open. Review its current fingerprint and try again.")
        }
        let attempt = generation
        pairingRevisions[pendingTrust.device.id] = UUID()
        try await vault.store(pendingTrust.fingerprint, forKey: SamsungProtocol.certificateKey(deviceID: pendingTrust.device.id))
        guard generation == attempt, self.pendingTrust?.device.id == pendingTrust.device.id else {
            throw CancellationError()
        }
        try await connect(to: pendingTrust.device, onState: pendingTrust.callback)
    }

    func forgetPairing(for device: RemoteDevice) async throws {
        guard !pairingImports.contains(device.id) else {
            throw RemoteFailure.message("Finish importing this Samsung TV before changing its pairing.")
        }
        pairingRevisions[device.id] = UUID()
        if self.device?.id == device.id { reset(notify: true) }
        try await vault.delete(forKey: SamsungProtocol.tokenKey(deviceID: device.id))
        try await vault.delete(forKey: SamsungProtocol.certificateKey(deviceID: device.id))
    }

    /// Reads exactly this saved TV's typed fields. No socket is opened and no accounts are enumerated.
    func exportPairing(for device: RemoteDevice) async throws -> SamsungPairingTransfer? {
        try Task.checkCancellation()
        try SamsungPairingTransferValidation.validateDevice(device)
        guard !pairingImports.contains(device.id) else {
            throw RemoteFailure.message("Finish importing this Samsung TV before sharing its pairing.")
        }
        let attempt = generation
        let revision = pairingRevisions[device.id]
        let token = try await vault.data(forKey: SamsungProtocol.tokenKey(deviceID: device.id))
        guard generation == attempt, pairingRevisions[device.id] == revision else { throw CancellationError() }
        let certificate = try await vault.data(forKey: SamsungProtocol.certificateKey(deviceID: device.id))
        guard generation == attempt, pairingRevisions[device.id] == revision else { throw CancellationError() }
        try Task.checkCancellation()
        guard let token, let certificate else { return nil }
        guard let decodedToken = String(data: token, encoding: .utf8) else {
            throw RemoteFailure.message("This Samsung TV's saved pairing could not be shared. Pair it again before sharing.")
        }
        let transfer = SamsungPairingTransfer(deviceID: device.id, token: decodedToken,
            certificateSHA256: certificate, clientName: SamsungProtocol.clientName(deviceID: device.id))
        try SamsungPairingTransferValidation.validate(transfer, for: device)
        return transfer
    }

    /// Imports into empty storage only. Returns true only for newly inserted records;
    /// false means an exact existing record was preserved and must never enter batch rollback.
    /// Connecting later still requires a matching certificate and an explicit TV authorization event.
    @discardableResult
    func importPairing(_ transfer: SamsungPairingTransfer, for device: RemoteDevice) async throws -> Bool {
        try Task.checkCancellation()
        try SamsungPairingTransferValidation.validate(transfer, for: device)
        guard self.device?.id != device.id else {
            throw RemoteFailure.message("Disconnect this Samsung TV before importing pairing data.")
        }
        guard pairingImports.insert(device.id).inserted else {
            throw RemoteFailure.message("This Samsung TV is already being imported.")
        }
        defer { pairingImports.remove(device.id) }
        let revision = UUID()
        pairingRevisions[device.id] = revision
        let tokenKey = SamsungProtocol.tokenKey(deviceID: device.id)
        let certificateKey = SamsungProtocol.certificateKey(deviceID: device.id)
        let token = try await vault.data(forKey: tokenKey)
        let certificate = try await vault.data(forKey: certificateKey)
        try Task.checkCancellation()
        switch SamsungPairingTransferValidation.storageDecision(transfer, existingToken: token, existingCertificate: certificate) {
        case .alreadyPresent: return false
        case .conflict:
            throw RemoteFailure.message("This iPhone already has different pairing data for that Samsung TV. Import cannot replace an existing pairing.")
        case .insert: break
        }

        var storedCertificate = false
        var storedToken = false
        do {
            try Task.checkCancellation()
            try await vault.store(transfer.certificateSHA256, forKey: certificateKey)
            storedCertificate = true
            try Task.checkCancellation()
            try await vault.store(Data(transfer.token.utf8), forKey: tokenKey)
            storedToken = true
            try Task.checkCancellation()
        } catch {
            // Both accounts were absent and this driver's per-device import lock is still held.
            // Never remove a pre-existing account as part of rollback.
            var rollbackFailed = false
            if storedToken {
                do { try await vault.delete(forKey: tokenKey) } catch { rollbackFailed = true }
            }
            if storedCertificate {
                do { try await vault.delete(forKey: certificateKey) } catch { rollbackFailed = true }
            }
            if rollbackFailed {
                throw RemoteFailure.message("Samsung pairing import could not be completed or fully undone. Unlock this iPhone and remove the saved pairing before retrying.")
            }
            throw error
        }
        return true
    }

    func disconnect() async { reset(notify: true) }

    func send(_ action: RemoteAction, toDeviceID deviceID: String) async throws {
        let payload = try SamsungProtocol.keyPayload(action)
        guard device?.id == deviceID else {
            throw RemoteFailure.message("The selected Samsung TV changed. This command was cancelled.")
        }
        guard state == .connected, let socket = connection else {
            throw RemoteFailure.message("Connect to this Samsung TV before sending a command.")
        }
        guard pendingWrite == nil else {
            throw RemoteFailure.message("A Samsung command is still being sent. Try again in a moment.")
        }
        let attempt = generation
        let writeID = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    await self?.writeFinished(writeID, attempt: attempt, failed: true)
                }
                pendingWrite = PendingWrite(id: writeID, action: action, continuation: continuation, timeout: timeout)
                let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
                let context = NWConnection.ContentContext(identifier: writeID.uuidString, metadata: [metadata])
                socket.send(content: payload, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
                    Task { await self?.writeFinished(writeID, attempt: attempt, failed: error != nil) }
                })
            }
        } onCancel: {
            Task { await self.cancelWrite(writeID, attempt: attempt) }
        }
        // A completed write does not acknowledge that the TV applied a key or changed power.
        // Keep the socket open to finish delivery; only observed transport events change its status.
        // Power is a single explicit toggle and is never replayed or retried here.
    }

    private func verifyCertificate(_ fingerprint: Data, savedPin: Data?, attempt: UUID) -> Bool {
        guard generation == attempt, connection != nil else { return false }
        if let savedPin {
            guard fingerprint == savedPin else {
                fail("This TV's certificate has changed. Check the selected TV and address, then explicitly forget pairing to trust a new identity.", attempt: attempt)
                return false
            }
            return true
        }
        guard let device, let stateCallback else { return false }
        pendingTrust = PendingTrust(device: device, fingerprint: fingerprint, callback: stateCallback)
        // Reject this handshake; a second handshake can proceed only after explicit approval.
        generation = UUID()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        connectTimeout?.cancel()
        connectTimeout = nil
        let continuation = connectContinuation
        connectContinuation = nil
        update(.trustRequired(fingerprint: SamsungProtocol.formattedFingerprint(fingerprint)))
        continuation?.resume()
        return false
    }

    private func connectionChanged(_ transportState: NWConnection.State, attempt: UUID) {
        guard generation == attempt else { return }
        switch transportState {
        case .ready:
            update(.awaitingApproval)
            receiveNext(attempt: attempt)
        case .failed:
            fail("Could not connect to the secure Samsung remote. Check that the TV is on, the address is correct, and both devices use the same Wi-Fi. This adapter requires a modern Tizen TV with port 8002.", attempt: attempt)
        case .cancelled:
            fail("The Samsung connection closed. Reconnect before sending more commands.", attempt: attempt)
        default: break
        }
    }

    private func receiveNext(attempt: UUID) {
        guard generation == attempt, let connection else { return }
        connection.receiveMessage { [weak self] data, context, complete, error in
            let opcode = (context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata)?.opcode
            Task { await self?.received(data, opcode: opcode, complete: complete, transportFailed: error != nil, attempt: attempt) }
        }
    }

    private func received(_ data: Data?, opcode: NWProtocolWebSocket.Opcode?, complete: Bool, transportFailed: Bool, attempt: UUID) async {
        guard generation == attempt else { return }
        guard !transportFailed, opcode != .close else {
            fail("The Samsung TV disconnected. Turn it on and reconnect.", attempt: attempt)
            return
        }
        if opcode == .ping || opcode == .pong { receiveNext(attempt: attempt); return }
        guard complete, opcode == .text, let data else {
            fail("The Samsung remote returned an unsupported message.", attempt: attempt)
            return
        }
        do {
            switch try SamsungProtocol.parse(data, clientName: clientName) {
            case .authorized(let token):
                guard state == .awaitingApproval, let device else { receiveNext(attempt: attempt); return }
                if let token {
                    if savedPairingOnlyMode {
                        pendingTrialToken = token
                    } else {
                        pairingRevisions[device.id] = UUID()
                        try await vault.store(Data(token.utf8), forKey: SamsungProtocol.tokenKey(deviceID: device.id))
                        guard generation == attempt else { return }
                    }
                }
                connectTimeout?.cancel()
                connectTimeout = nil
                update(.connected)
                let continuation = connectContinuation
                connectContinuation = nil
                continuation?.resume()
            case .denied:
                fail("Access was denied on the Samsung TV. Allow Room Remote in the TV's device connection settings, then reconnect.", attempt: attempt)
                return
            case .approvalTimedOut:
                fail("Samsung TV approval timed out. Reconnect and choose Allow on the TV.", attempt: attempt)
                return
            case .ignored: break
            }
            receiveNext(attempt: attempt)
        } catch {
            guard generation == attempt else { return }
            let message = (error as? RemoteFailure)?.localizedDescription ?? "The Samsung pairing response could not be saved securely."
            fail(message, attempt: attempt)
        }
    }

    private func connectExpired(attempt: UUID) {
        fail("Samsung TV approval timed out. Check the TV's Allow prompt, Wi-Fi connection, and the entered address. Older Samsung remote protocols are not supported by this test build.", attempt: attempt)
    }

    private func cancelAttempt(_ attempt: UUID) {
        guard generation == attempt else { return }
        reset(notify: true)
    }

    private func writeFinished(_ id: UUID, attempt: UUID, failed: Bool) {
        guard generation == attempt, let write = pendingWrite, write.id == id else { return }
        pendingWrite = nil
        write.timeout.cancel()
        if failed {
            let message = SamsungProtocol.deliveryFailure(for: write.action)
            write.continuation.resume(throwing: RemoteFailure.message(message))
            fail(message, attempt: attempt)
        } else { write.continuation.resume() }
    }

    private func cancelWrite(_ id: UUID, attempt: UUID) {
        guard generation == attempt, pendingWrite?.id == id else { return }
        // A cancelled transport write may already have reached the TV; never replay it.
        reset(notify: true)
    }

    private func fail(_ message: String, attempt: UUID) {
        guard generation == attempt else { return }
        cancelPing()
        generation = UUID()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        pendingTrust = nil
        connectTimeout?.cancel()
        connectTimeout = nil
        let continuation = connectContinuation
        connectContinuation = nil
        let write = pendingWrite
        pendingWrite = nil
        write?.timeout.cancel()
        let failureMessage = write?.action == .powerToggle ? SamsungProtocol.deliveryFailure(for: .powerToggle) : message
        update(.failed(failureMessage))
        continuation?.resume(throwing: RemoteFailure.message(failureMessage))
        write?.continuation.resume(throwing: RemoteFailure.message(failureMessage))
    }

    private func reset(notify: Bool) {
        cancelPing()
        generation = UUID()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        pendingTrust = nil
        savedPairingOnlyMode = false
        originalTrialToken = nil
        originalTrialCertificate = nil
        pendingTrialToken = nil
        device = nil
        connectTimeout?.cancel()
        connectTimeout = nil
        let continuation = connectContinuation
        connectContinuation = nil
        let write = pendingWrite
        pendingWrite = nil
        write?.timeout.cancel()
        if notify { update(.disconnected) } else { state = .disconnected }
        continuation?.resume(throwing: CancellationError())
        write?.continuation.resume(throwing: CancellationError())
    }

    private func update(_ state: DeviceConnectionState) {
        self.state = state
        stateCallback?(state)
    }
}

/// Bounded, testable wire handling; credentials and full messages are never logged.
enum SamsungProtocol {
    static let maximumFrameBytes = 1_048_576
    enum Event: Equatable { case authorized(token: String?), denied, approvalTimedOut, ignored }

    static func tokenKey(deviceID: String) -> String { "samsung.\(deviceID).token" }
    static func certificateKey(deviceID: String) -> String { "samsung.\(deviceID).certificate" }
    static func clientName(deviceID: String) -> String { "Room Remote \(deviceID.prefix(8))" }
    static func formattedFingerprint(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    static func privateHost(_ address: String) throws -> String {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        if octets.count == 4 {
            let bytes = octets.compactMap { part -> UInt8? in
                guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let byte = UInt8(part), String(byte) == part else { return nil }
                return byte
            }
            if bytes.count == 4 {
                let isPrivate = bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
                    (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254)
                guard isPrivate, bytes[3] != 255 else {
                    throw RemoteFailure.message("Enter this TV's private local-network IP address, not a public, loopback, or broadcast address.")
                }
                return bytes.map(String.init).joined(separator: ".")
            }
        }
        var ipv6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
            if bytes[0] & 0xFE == 0xFC { return host.lowercased() }
        }
        throw RemoteFailure.message("Enter the TV's private IPv4 address (for example, 192.168.1.50) or its IPv6 unique-local address. URLs and hostnames are not accepted.")
    }

    static func webSocketURL(host: String, clientName: String, token: String?) throws -> URL {
        let validatedHost = try privateHost(host)
        if let token, !validToken(token) { throw RemoteFailure.message("The Samsung pairing token is invalid.") }
        var components = URLComponents()
        components.scheme = "wss"
        components.host = validatedHost.contains(":") ? "[\(validatedHost)]" : validatedHost
        components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        var query = [URLQueryItem(name: "name", value: Data(clientName.utf8).base64EncodedString())]
        if let token { query.append(URLQueryItem(name: "token", value: token)) }
        components.queryItems = query
        guard let url = components.url else { throw RemoteFailure.message("The Samsung TV address is invalid.") }
        return url
    }

    static func validToken(_ token: String) -> Bool {
        !token.isEmpty && token.utf8.count <= 2_048 && !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    static func parse(_ data: Data, clientName: String) throws -> Event {
        guard data.count <= maximumFrameBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else {
            throw RemoteFailure.message("The Samsung TV sent an invalid or oversized remote message.")
        }
        switch event {
        case "ms.channel.unauthorized": return .denied
        case "ms.channel.timeOut": return .approvalTimedOut
        case "ms.channel.connect":
            guard let body = object["data"] as? [String: Any], let id = body["id"] as? String,
                  !id.isEmpty, id.utf8.count <= 256 else {
                throw RemoteFailure.message("The Samsung TV's approval response did not identify this connection.")
            }
            let wireName = Data(clientName.utf8).base64EncodedString()
            var matchingAttributes: [String: Any]?
            if let rawClients = body["clients"] {
                guard let clients = rawClients as? [[String: Any]] else {
                    throw RemoteFailure.message("The Samsung TV returned an invalid client list.")
                }
                guard clients.count <= 256 else { throw RemoteFailure.message("The Samsung TV returned too many remote clients.") }
                let matches = clients.filter { ($0["id"] as? String) == id }
                guard matches.count <= 1 else { throw RemoteFailure.message("The Samsung TV returned an ambiguous pairing response.") }
                if let match = matches.first {
                    if let rawAttributes = match["attributes"], !(rawAttributes is [String: Any]) {
                        throw RemoteFailure.message("The Samsung TV returned invalid pairing attributes.")
                    }
                    matchingAttributes = match["attributes"] as? [String: Any]
                    if let name = matchingAttributes?["name"] as? String, name != wireName && name != clientName {
                        throw RemoteFailure.message("The Samsung TV's approval response belongs to a different remote client.")
                    }
                }
            }
            let rawToken = body["token"] ?? matchingAttributes?["token"]
            if let rawToken {
                guard let token = rawToken as? String, validToken(token) else {
                    throw RemoteFailure.message("The Samsung TV returned an invalid pairing token.")
                }
                return .authorized(token: token)
            }
            return .authorized(token: nil)
        default: return .ignored
        }
    }

    static func keyPayload(_ action: RemoteAction) throws -> Data {
        let key: String
        switch action {
        case .up: key = "KEY_UP"
        case .down: key = "KEY_DOWN"
        case .left: key = "KEY_LEFT"
        case .right: key = "KEY_RIGHT"
        case .select: key = "KEY_ENTER"
        case .back: key = "KEY_RETURN"
        case .home: key = "KEY_HOME"
        case .appSwitcher, .controlCenter: throw RemoteFailure.message("This button action is available on Apple TV only.")
        case .playPause: key = "KEY_PLAYPAUSE"
        case .volumeUp: key = "KEY_VOLUP"
        case .volumeDown: key = "KEY_VOLDOWN"
        case .mute: key = "KEY_MUTE"
        case .source: key = "KEY_SOURCE"
        // Modern Tizen remotes use the physical power-button toggle. Never substitute
        // it for an off-only/sleep request: pressing it again may turn the TV back on.
        case .powerToggle: key = "KEY_POWER"
        case .sleep, .powerOff:
            throw RemoteFailure.message("A separate Samsung off-only command is not supported by this build. Use the Samsung power button, which toggles power, and check the TV's state.")
        case .wake:
            throw RemoteFailure.message("Wake is not available for Samsung TVs in this test build. Turn on the TV with its physical remote, then connect. Sending a key to a sleeping TV does not reliably wake it.")
        }
        return try JSONSerialization.data(withJSONObject: [
            "method": "ms.remote.control",
            "params": ["Cmd": "Click", "DataOfCmd": key, "Option": "false", "TypeOfRemote": "SendRemoteKey"]
        ])
    }

    static func deliveryFailure(for action: RemoteAction) -> String {
        if action == .powerToggle {
            return "Power-button delivery could not be confirmed. Check the TV before pressing power again; repeating it could turn the TV back on."
        }
        return "The command could not be sent to the Samsung TV. Reconnect and try again."
    }
}
