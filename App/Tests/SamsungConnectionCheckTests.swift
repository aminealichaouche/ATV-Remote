import XCTest
import Network
@testable import RoomRemote

final class SamsungConnectionCheckTests: XCTestCase {
    private let device = RemoteDevice(id: "loopback-ping", kind: .samsung, name: "Fixture TV", address: "127.0.0.1")

    func testPongAcknowledgesExistingConnectionWithoutRemoteKeysOrNewSockets() async throws {
        let server = try LocalWebSocket(answersPing: true)
        defer { server.stop() }
        let socket = try await server.client()
        let driver = SamsungDriver(vault: KeychainVault())
        await driver.installTestConnection(socket, for: device)
        let first = await driver.verifyConnection(toDeviceID: device.id)
        let second = await driver.verifyConnection(toDeviceID: device.id)
        XCTAssertTrue(first); XCTAssertTrue(second)
        XCTAssertEqual(server.connectionCount, 1)
        XCTAssertEqual(server.textCount, 0)
        await driver.disconnect()
    }

    func testMissingPongFailsWithinDeadlineAndClosesOnlyThatSession() async throws {
        let server = try LocalWebSocket(answersPing: false)
        defer { server.stop() }
        let socket = try await server.client()
        let driver = SamsungDriver(vault: KeychainVault())
        await driver.installTestConnection(socket, for: device)
        let start = ContinuousClock.now
        let result = await driver.verifyConnection(toDeviceID: device.id)
        let connected = await driver.connectionIsConnected(toDeviceID: device.id)
        XCTAssertFalse(result); XCTAssertFalse(connected)
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
        XCTAssertEqual(server.connectionCount, 1); XCTAssertEqual(server.textCount, 0)
        await driver.disconnect()
    }

    func testCancellingForegroundCheckDoesNotCloseAnOtherwiseReadySocket() async throws {
        let server = try LocalWebSocket(answersPing: false)
        defer { server.stop() }
        let socket = try await server.client()
        let driver = SamsungDriver(vault: KeychainVault())
        await driver.installTestConnection(socket, for: device)
        let deviceID = device.id
        let check = Task { await driver.verifyConnection(toDeviceID: deviceID) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while server.pingCount == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(server.pingCount, 1)
        let start = ContinuousClock.now
        check.cancel()
        _ = await check.value
        let connected = await driver.connectionIsConnected(toDeviceID: device.id)
        XCTAssertTrue(connected)
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        XCTAssertEqual(server.connectionCount, 1); XCTAssertEqual(server.textCount, 0)
        await driver.disconnect()
    }
}

private final class LocalWebSocket: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ATVRemoteTests.WebSocket")
    private let lock = NSLock()
    private var peers: [NWConnection] = []
    private var clients: [NWConnection] = []
    private var pings = 0
    private var texts = 0
    var connectionCount: Int { lock.withLock { peers.count } }
    var pingCount: Int { lock.withLock { pings } }
    var textCount: Int { lock.withLock { texts } }

    init(answersPing: Bool) throws {
        let parameters = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = answersPing
        parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] peer in
            guard let self else { peer.cancel(); return }
            self.lock.withLock { self.peers.append(peer) }
            peer.start(queue: self.queue)
            self.receive(peer)
        }
    }

    func client() async throws -> NWConnection {
        listener.start(queue: queue)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        var listeningPort: NWEndpoint.Port?
        while ContinuousClock.now < deadline {
            if case .ready = listener.state, let port = listener.port, port.rawValue != 0 {
                listeningPort = port
                break
            }
            if case .failed(let error) = listener.state { throw error }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard let port = listeningPort else { throw RemoteFailure.message("Loopback listener failed") }
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        let socket = NWConnection(to: .url(URL(string: "ws://127.0.0.1:\(port.rawValue)")!), using: parameters)
        lock.withLock { clients.append(socket) }
        socket.start(queue: queue)
        while ContinuousClock.now < deadline {
            if case .ready = socket.state { return socket }
            if case .failed(let error) = socket.state { throw error }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw RemoteFailure.message("Loopback WebSocket failed")
    }

    private func receive(_ peer: NWConnection) {
        peer.receiveMessage { [weak self] _, context, _, error in
            guard let self, error == nil else { return }
            let opcode = (context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata)?.opcode
            self.lock.withLock {
                if opcode == .ping { self.pings += 1 }
                if opcode == .text { self.texts += 1 }
            }
            self.receive(peer)
        }
    }

    func stop() {
        listener.cancel()
        let sockets = lock.withLock { peers + clients }
        sockets.forEach { $0.cancel() }
    }
}
