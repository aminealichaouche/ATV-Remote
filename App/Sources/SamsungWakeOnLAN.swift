import Foundation
import Network
import Darwin

/// Wake packets are sent to this saved TV's unicast IPv4 endpoint only. They do
/// not use the subnet broadcast address or require multicast entitlement access.
enum SamsungWakeOnLAN {
    static let port: UInt16 = 9

    static func normalizedMAC(_ raw: String) throws -> String {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups: [Substring]
        if input.contains(":") {
            groups = input.split(separator: ":", omittingEmptySubsequences: false)
            guard groups.count == 6, groups.allSatisfy({ $0.utf8.count == 2 }) else { throw invalidMAC() }
        } else if input.contains("-") {
            groups = input.split(separator: "-", omittingEmptySubsequences: false)
            guard groups.count == 6, groups.allSatisfy({ $0.utf8.count == 2 }) else { throw invalidMAC() }
        } else if input.contains(".") {
            groups = input.split(separator: ".", omittingEmptySubsequences: false)
            guard groups.count == 3, groups.allSatisfy({ $0.utf8.count == 4 }) else { throw invalidMAC() }
        } else {
            groups = [Substring(input)]
            guard input.utf8.count == 12 else { throw invalidMAC() }
        }
        let digits = groups.flatMap { Array($0.utf8) }
        guard digits.count == 12, digits.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { throw invalidMAC() }
        let text = String(decoding: digits, as: UTF8.self)
        var bytes: [UInt8] = []
        for offset in stride(from: 0, to: 12, by: 2) {
            let start = text.index(text.startIndex, offsetBy: offset)
            let end = text.index(start, offsetBy: 2)
            guard let byte = UInt8(text[start..<end], radix: 16) else { throw invalidMAC() }
            bytes.append(byte)
        }
        // Locally administered unicast MACs are valid; multicast, all-zero and
        // broadcast addresses cannot identify one TV and must never be sent.
        guard bytes[0] & 1 == 0, bytes.contains(where: { $0 != 0 }) else { throw invalidMAC() }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    static func packet(forMAC raw: String) throws -> Data {
        let canonical = try normalizedMAC(raw)
        let bytes = canonical.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }

    static func parameters(for source: SamsungWakeLocalEndpoint) -> NWParameters {
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = false
        parameters.prohibitedInterfaceTypes = [.cellular]
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(source.address), port: .any)
        return parameters
    }

    private static func invalidMAC() -> RemoteFailure {
        .message("Enter this Samsung TV's Wi-Fi or Ethernet MAC address, for example 00:12:34:56:78:9A. Use the address for its current network connection.")
    }
}

/// Capturing the endpoint and MAC together prevents a delayed action from being
/// redirected to another room, another TV or a later edited network address.
struct SamsungWakeTarget: Equatable, Sendable {
    let deviceID: String
    let address: String
    let macAddress: String
    let packetData: Data
    var port: UInt16 { SamsungWakeOnLAN.port }

    init(device: RemoteDevice) throws {
        guard device.kind == .samsung else { throw RemoteFailure.message("Select a Samsung TV to turn it on.") }
        guard device.port == nil || device.port == 8002 else {
            throw RemoteFailure.message("This Samsung TV must use the secure remote port, 8002.")
        }
        let host = try SamsungProtocol.privateHost(device.address)
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else {
            throw RemoteFailure.message("Turning on a Samsung TV requires its private IPv4 address, for example 192.168.1.50. IPv6 cannot be used.")
        }
        guard let rawMAC = device.wakeMACAddress, !rawMAC.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteFailure.message("Add this Samsung TV's MAC address in Settings before turning it on.")
        }
        deviceID = device.id
        address = host
        macAddress = try SamsungWakeOnLAN.normalizedMAC(rawMAC)
        packetData = try SamsungWakeOnLAN.packet(forMAC: macAddress)
    }

    func matches(_ device: RemoteDevice) -> Bool {
        guard let current = try? SamsungWakeTarget(device: device) else { return false }
        return self == current
    }
}

struct SamsungWakeLocalEndpoint: Equatable, Sendable {
    let interfaceName: String
    let address: String
}

/// A datagram addressed to .127 can still be a broadcast on a /25 network.
/// The actual local interface's mask, rather than the last octet, decides whether
/// the saved TV address is an on-link individual host.
struct SamsungWakeLocalSubnet: Sendable {
    let interfaceName: String
    let address: String
    let netmask: String?
    let isUp: Bool
    let supportsBroadcast: Bool
    let isLoopback: Bool

    private struct Validated {
        let endpoint: SamsungWakeLocalEndpoint
        let address: UInt32
        let mask: UInt32
        let network: UInt32
        let broadcast: UInt32
        let prefixLength: Int
    }

    static func source(for target: String, among interfaces: [SamsungWakeLocalSubnet]) throws -> SamsungWakeLocalEndpoint {
        let canonicalTarget = try SamsungProtocol.privateHost(target)
        guard let targetValue = ipv4Value(canonicalTarget) else {
            throw RemoteFailure.message("Turning on a Samsung TV requires a private IPv4 address.")
        }
        let eligible = interfaces.compactMap { $0.validated }
        guard !eligible.contains(where: { $0.address == targetValue }) else {
            throw RemoteFailure.message("The saved TV address is this iPhone's address. Update the TV's IPv4 address in Settings.")
        }
        let matching = eligible.filter { targetValue & $0.mask == $0.network }
        guard !matching.isEmpty else {
            throw RemoteFailure.message("Connect this iPhone to the Samsung TV's local IPv4 network before turning it on. Its saved address must be on that network.")
        }
        // Fail closed for overlapping interface ranges too: the destination must
        // not be a network or broadcast address of any eligible matching subnet.
        guard matching.allSatisfy({ targetValue != $0.network && targetValue != $0.broadcast }) else {
            throw RemoteFailure.message("The saved TV address is a network or broadcast address on this iPhone's network. Enter the TV's individual IPv4 address.")
        }
        let preferred = matching.sorted {
            if $0.prefixLength != $1.prefixLength { return $0.prefixLength > $1.prefixLength }
            return $0.endpoint.interfaceName < $1.endpoint.interfaceName
        }[0]
        return preferred.endpoint
    }

    /// Reading the OS's interface table does not probe any local-network hosts.
    static func currentInterfaces() throws -> [SamsungWakeLocalSubnet] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            throw RemoteFailure.message("The iPhone's local IPv4 network could not be checked. Reconnect to the TV's network and try again.")
        }
        defer { freeifaddrs(first) }
        var interfaces: [SamsungWakeLocalSubnet] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ifa_next
            guard let rawAddress = entry.ifa_addr,
                  rawAddress.pointee.sa_family == sa_family_t(AF_INET),
                  let name = entry.ifa_name else { continue }
            let isUp = entry.ifa_flags & UInt32(IFF_UP) != 0
            let supportsBroadcast = entry.ifa_flags & UInt32(IFF_BROADCAST) != 0
            let isLoopback = entry.ifa_flags & UInt32(IFF_LOOPBACK) != 0
            guard isUp, supportsBroadcast, !isLoopback else { continue }
            let address = rawAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                ipv4String(UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
            }
            let netmask: String?
            if let rawMask = entry.ifa_netmask, rawMask.pointee.sa_family == sa_family_t(AF_INET) {
                netmask = rawMask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    ipv4String(UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
                }
            } else { netmask = nil }
            interfaces.append(SamsungWakeLocalSubnet(interfaceName: String(cString: name),
                address: address, netmask: netmask, isUp: isUp,
                supportsBroadcast: supportsBroadcast, isLoopback: isLoopback))
        }
        return interfaces
    }

    private var validated: Validated? {
        guard isUp, supportsBroadcast, !isLoopback, !interfaceName.isEmpty,
              // iOS cellular interfaces must not become a local source even if
              // their flags change. Network.framework separately prohibits them.
              !interfaceName.hasPrefix("pdp_ip"),
              let addressValue = Self.ipv4Value(address),
              let netmask, let mask = Self.ipv4Value(netmask) else { return nil }
        let prefixLength = mask.nonzeroBitCount
        guard (1...30).contains(prefixLength), mask == UInt32.max << (32 - prefixLength) else { return nil }
        let network = addressValue & mask
        let broadcast = network | ~mask
        guard addressValue != network, addressValue != broadcast else { return nil }
        return Validated(endpoint: SamsungWakeLocalEndpoint(interfaceName: interfaceName, address: address),
            address: addressValue, mask: mask, network: network, broadcast: broadcast, prefixLength: prefixLength)
    }

    private static func ipv4Value(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let byte = UInt8(part), String(byte) == part else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    private static func ipv4String(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> $0) & 0xFF) }.joined(separator: ".")
    }
}

/// This gate is shared by the actual transport callbacks. Only the first ready
/// callback may issue the packet; a stale cancellation/completion cannot clear
/// an operation started after its own operation finished.
struct SamsungWakeSendGate: Sendable {
    private(set) var operationID: UUID?
    private(set) var isSending = false

    mutating func begin(_ id: UUID) -> Bool {
        guard operationID == nil else { return false }
        operationID = id
        isSending = false
        return true
    }

    mutating func ready(_ id: UUID) -> Bool {
        guard operationID == id, !isSending else { return false }
        isSending = true
        return true
    }

    mutating func finish(_ id: UUID) -> Bool {
        guard operationID == id else { return false }
        operationID = nil
        isSending = false
        return true
    }
}

/// A successful send means one UDP datagram was accepted by the local network
/// stack. Wake-on-LAN has no acknowledgment, so this never reports the TV as on.
actor SamsungWakeSender {
    private struct Operation {
        let id: UUID
        let target: SamsungWakeTarget
        let connection: NWConnection
        let continuation: CheckedContinuation<Void, Error>
        let timeout: Task<Void, Never>
    }

    private let queue = DispatchQueue(label: "local.RoomRemote.samsung.wake")
    private var gate = SamsungWakeSendGate()
    private var operation: Operation?

    func send(to target: SamsungWakeTarget) async throws {
        try Task.checkCancellation()
        let source = try SamsungWakeLocalSubnet.source(for: target.address,
            among: SamsungWakeLocalSubnet.currentInterfaces())
        try Task.checkCancellation()
        let id = UUID()
        guard gate.begin(id) else { throw RemoteFailure.message("A wake request is already being sent. Wait for it to finish.") }
        let parameters = SamsungWakeOnLAN.parameters(for: source)
        let connection = NWConnection(host: NWEndpoint.Host(target.address),
            port: NWEndpoint.Port(rawValue: target.port)!, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            Task { await self?.stateChanged(state, id: id) }
        }
        try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { continuation in
                    let timeout = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                        await self?.finish(id, error: RemoteFailure.message("The wake request timed out. Check that this iPhone is on the TV's local network and Local Network access is enabled."))
                    }
                    operation = Operation(id: id, target: target, connection: connection,
                        continuation: continuation, timeout: timeout)
                    connection.start(queue: queue)
                }
                try Task.checkCancellation()
            } catch {
                // Cancellation can already be set when the cancellation handler
                // is installed, before a continuation was registered.
                if gate.operationID == id, operation == nil {
                    _ = gate.finish(id)
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                }
                throw error
            }
        } onCancel: {
            // Stop the socket immediately, without waiting for actor scheduling;
            // only the matching actor operation may release its continuation.
            connection.cancel()
            Task { await self.finish(id, error: CancellationError()) }
        }
    }

    private func stateChanged(_ state: NWConnection.State, id: UUID) {
        guard let current = operation, current.id == id else { return }
        switch state {
        case .ready:
            guard gate.ready(id) else { return }
            current.connection.send(content: current.target.packetData, completion: .contentProcessed { [weak self] error in
                Task { await self?.finish(id, error: error) }
            })
        case .failed(let error): finish(id, error: error)
        case .cancelled: finish(id, error: CancellationError())
        default: break // Waiting, preparing and setup remain bounded by timeout.
        }
    }

    private func finish(_ id: UUID, error: Error?) {
        guard let current = operation, current.id == id, gate.finish(id) else { return }
        operation = nil
        current.timeout.cancel()
        current.connection.stateUpdateHandler = nil
        current.connection.cancel()
        if let error { current.continuation.resume(throwing: error) }
        else { current.continuation.resume() }
    }
}
