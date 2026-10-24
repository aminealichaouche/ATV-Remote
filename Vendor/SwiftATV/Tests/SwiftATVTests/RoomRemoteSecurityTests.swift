import Foundation
import Testing
@testable import SwiftATV

@Suite("Room Remote: untrusted Companion input bounds")
struct RoomRemoteSecurityTests {
    @Test("OPACK rejects excessive nesting without recursive stack exhaustion")
    func depthLimit() {
        let nested = Data(repeating: 0xD1, count: 64) + Data([0x04])
        #expect(throws: ATVError.self) { _ = try OPACK.decode(nested) }
    }

    @Test("OPACK caps nodes even for inline values with no object-table entries")
    func nodeLimit() {
        let many = Data([0xDF]) + Data(repeating: 0x04, count: 32_769) + Data([0x03])
        #expect(throws: ATVError.self) { _ = try OPACK.decode(many) }
    }

    @Test("OPACK bounds quadratic scalar de-duplication work")
    func comparisonLimit() {
        var data = Data([0xDF])
        for value in 0..<2_100 {
            let text = String(format: "%08d", value)
            data.append(0x48)
            data.append(Data(text.utf8))
        }
        data.append(0x03)
        #expect(throws: ATVError.self) { _ = try OPACK.decode(data) }
    }

    @Test("OPACK bounds allocation before parsing")
    func payloadLimit() {
        #expect(throws: ATVError.self) { _ = try OPACK.decode(Data(repeating: 0, count: 1_048_577)) }
    }

    @Test("Valid Companion content remains decodable")
    func validPayload() throws {
        let encoded = OPACK.encode(.dictionary([("_i", .string("_hidC")), ("_c", .dictionary([("_hidC", .uint(6))]))]))
        #expect(try OPACK.decode(encoded)["_i"]?.stringValue == "_hidC")
    }

    @Test("Oversized frame header closes before waiting for attacker body")
    func oversizedFrameHeader() async throws {
        let connection = CompanionConnection(host: "127.0.0.1", port: 0)
        connection.handleReceivedData(Data([CompanionFrameType.eOPACK.rawValue, 0x10, 0x00, 0x01]))
        await #expect(throws: ATVError.self) { _ = try await connection.waitForFrame(type: .eOPACK) }
        await connection.close()
    }

    @Test("Outbound frames obey same memory limit")
    func outboundFrameLimit() {
        #expect(throws: ATVError.self) {
            _ = try CompanionConnection.encodeFrame(type: .eOPACK,
                payload: Data(repeating: 0, count: 1_048_577), cipher: nil)
        }
    }

    @Test("Backlogged frame delivery fails closed rather than losing responses")
    func frameBacklogLimit() async throws {
        let connection = CompanionConnection(host: "127.0.0.1", port: 0)
        _ = connection.frameStream
        for _ in 0..<65 { connection.handleReceivedData(Data([1, 0, 0, 0])) }
        await #expect(throws: ATVError.self) { _ = try await connection.waitForFrame(type: .noOp) }
        await connection.close()
    }

    @Test("Pair-verify requires the successful M4 state")
    func verifyFinish() throws {
        let valid = wrapCompanionAuthEnvelope(innerTLV: TLV8.encode([.init(tag: .state, data: Data([4]))]))
        try validateCompanionVerifyFinish(valid)
        let invalid = wrapCompanionAuthEnvelope(innerTLV: TLV8.encode([.init(tag: .state, data: Data([2]))]))
        #expect(throws: ATVError.self) { try validateCompanionVerifyFinish(invalid) }
        #expect(throws: ATVError.self) { try validateCompanionVerifyFinish(wrapCompanionAuthEnvelope(innerTLV: Data())) }
    }

    @Test("Unconsumed state snapshots retain the latest value only")
    func boundedStateSnapshots() async {
        let store = CompanionStateStore()
        let volume = store.volumeStream()
        let power = store.powerStateStream()
        let focus = store.focusStateStream()
        for index in 0..<1_000 {
            store.setVolume(Float(index % 100))
            store.setPowerState(index % 2 == 0 ? .on : .off)
            store.setTextFocusState(index % 2 == 0 ? .focused : .unfocused)
        }
        var volumeIterator = volume.makeAsyncIterator()
        var powerIterator = power.makeAsyncIterator()
        var focusIterator = focus.makeAsyncIterator()
        #expect(await volumeIterator.next() == 99)
        #expect(await powerIterator.next() == .off)
        #expect(await focusIterator.next() == .unfocused)
    }

    @Test("SRP rejects oversized unauthenticated math inputs before conversion")
    func srpInputBounds() {
        var client = SRPClient(privateKey: 1)
        #expect(throws: ATVError.self) {
            _ = try client.processChallenge(salt: Data([1]), serverPublicB: Data(repeating: 1, count: 385), pin: "1234")
        }
        #expect(throws: ATVError.self) {
            _ = try client.processChallenge(salt: Data(repeating: 1, count: 65), serverPublicB: Data([1]), pin: "1234")
        }
    }

    @Test("RTI rejects excessive object count before Foundation allocates it")
    func textObjectLimit() {
        var data = Data("bplist00".utf8) + Data(count: 32)
        data[data.count - 22] = 0x01
        #expect(throws: ATVError.self) { _ = try CompanionTextInputSession.decodeStartResponse(data) }
    }
}
