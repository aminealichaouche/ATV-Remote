import XCTest
@testable import RoomRemote

final class SamsungDriverTests: XCTestCase {
    private let remoteClientName = "Room Remote 12345678"

    private func parse(_ json: String) throws -> SamsungProtocol.Event {
        try SamsungProtocol.parse(Data(json.utf8), clientName: remoteClientName)
    }

    func testDenialCannotBecomeAuthorizedBecauseItContainsAToken() throws {
        XCTAssertEqual(try parse(#"{"event":"ms.channel.unauthorized","data":{"id":"ours","token":"secret"}}"#), .denied)
        XCTAssertEqual(try parse(#"{"event":"ms.channel.timeOut","data":{"token":"secret"}}"#), .approvalTimedOut)
    }

    func testUnrelatedAndPreApprovalMessagesDoNotAuthorize() throws {
        XCTAssertEqual(try parse(#"{"event":"ms.channel.clientConnect","data":{"id":"ours","token":"secret"}}"#), .ignored)
        XCTAssertEqual(try parse(#"{"event":"ed.edenTV.update","data":{}}"#), .ignored)
        XCTAssertThrowsError(try parse(#"{"event":"ms.channel.connect"}"#))
        XCTAssertThrowsError(try parse(#"{"event":"ms.channel.connect","data":{"id":""}}"#))
        XCTAssertThrowsError(try parse(#"{"event":"ms.channel.connect","data":{"id":true,"token":"secret"}}"#))
    }

    func testOnlyMatchingClientSuppliesNestedToken() throws {
        let json = #"{"event":"ms.channel.connect","data":{"id":"ours","clients":[{"id":"another","attributes":{"token":"wrong"}},{"id":"ours","attributes":{"name":"Room Remote 12345678","token":"right"}}]}}"#
        XCTAssertEqual(try parse(json), .authorized(token: "right"))
        let otherOnly = #"{"event":"ms.channel.connect","data":{"id":"ours","clients":[{"id":"another","attributes":{"token":"wrong"}}]}}"#
        XCTAssertEqual(try parse(otherOnly), .authorized(token: nil))
    }

    func testTopLevelTokenAndEncodedClientName() throws {
        let wireName = Data(remoteClientName.utf8).base64EncodedString()
        let json = "{\"event\":\"ms.channel.connect\",\"data\":{\"id\":\"ours\",\"token\":\"fresh\",\"clients\":[{\"id\":\"ours\",\"attributes\":{\"name\":\"\(wireName)\",\"token\":\"stale\"}}]}}"
        XCTAssertEqual(try parse(json), .authorized(token: "fresh"))
    }

    func testAmbiguousOrWrongClientIdentityIsRejected() {
        XCTAssertThrowsError(try parse(#"{"event":"ms.channel.connect","data":{"id":"ours","clients":[{"id":"ours","attributes":{"token":"a"}},{"id":"ours","attributes":{"token":"b"}}]}}"#))
        XCTAssertThrowsError(try parse(#"{"event":"ms.channel.connect","data":{"id":"ours","token":"a","clients":[{"id":"ours","attributes":{"name":"Someone else"}}]}}"#))
    }

    func testBadFramesAndTokensAreRejected() {
        XCTAssertThrowsError(try parse("not JSON"))
        XCTAssertThrowsError(try parse("[]"))
        XCTAssertThrowsError(try parse(#"{"event":"ms.channel.connect","data":{"id":"ours","token":true}}"#))
        XCTAssertThrowsError(try parse(#"{"event":"ms.channel.connect","data":{"id":"ours","token":""}}"#))
        XCTAssertThrowsError(try parse(#"{"event":"ms.channel.connect","data":{"id":"ours","clients":"not a list","token":"secret"}}"#))
        XCTAssertThrowsError(try parse(#"{"event":"ms.channel.connect","data":{"id":"ours","clients":[{"id":"ours","attributes":true}],"token":"secret"}}"#))
        XCTAssertThrowsError(try SamsungProtocol.parse(Data(repeating: 0x20, count: SamsungProtocol.maximumFrameBytes + 1), clientName: remoteClientName))
        XCTAssertFalse(SamsungProtocol.validToken("one\ntwo"))
        XCTAssertFalse(SamsungProtocol.validToken(String(repeating: "x", count: 2_049)))
    }

    func testOnlyExplicitPrivateNumericEndpointsAreAccepted() throws {
        for host in ["10.1.2.3", "172.16.2.3", "172.31.2.3", "192.168.50.2", "169.254.10.1", "fd00::1234"] {
            XCTAssertEqual(try SamsungProtocol.privateHost(host), host)
        }
        for host in ["8.8.8.8", "127.0.0.1", "0.0.0.0", "224.0.0.1", "255.255.255.255", "192.168.1.255", "172.15.0.1", "172.32.0.1", "192.168.1.300", "192.168.01.2", "tv.local", "192.168.1.2/evil", "https://192.168.1.2", "192.168.1.2@evil.com", "::1", "2001:db8::1", "::ffff:127.0.0.1"] {
            XCTAssertThrowsError(try SamsungProtocol.privateHost(host), "Unsafe endpoint accepted: \(host)")
        }
    }

    func testURLQueryCannotInjectAnotherParameter() throws {
        let token = "a&host=8.8.8.8#fragment+ space"
        let url = try SamsungProtocol.webSocketURL(host: "192.168.1.2", clientName: remoteClientName, token: token)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(components.host, "192.168.1.2")
        XCTAssertEqual(components.port, 8002)
        XCTAssertNil(components.fragment)
        XCTAssertEqual(components.path, "/api/v2/channels/samsung.remote.control")
        XCTAssertEqual(components.queryItems?.count, 2)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "token" })?.value, token)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "name" })?.value, Data(remoteClientName.utf8).base64EncodedString())
        let ipv6 = try SamsungProtocol.webSocketURL(host: "fd00::1234", clientName: remoteClientName, token: nil)
        XCTAssertTrue(ipv6.absoluteString.hasPrefix("wss://[fd00::1234]:8002/"))
    }

    func testPairingKeysArePerDeviceAndSeparateFromAppleCredentials() {
        XCTAssertNotEqual(SamsungProtocol.tokenKey(deviceID: "bedroom"), SamsungProtocol.tokenKey(deviceID: "living-room"))
        XCTAssertNotEqual(SamsungProtocol.tokenKey(deviceID: "bedroom"), SamsungProtocol.certificateKey(deviceID: "bedroom"))
        XCTAssertEqual(SamsungProtocol.tokenKey(deviceID: "stable-id"), "samsung.stable-id.token")
    }

    func testUnpairedDriverCannotSendOrApproveAnUnrelatedDevice() async {
        let driver = SamsungDriver(vault: KeychainVault())
        do {
            try await driver.send(.home, toDeviceID: "unpaired-id")
            XCTFail("An unpaired Samsung remote sent a key")
        } catch { }
        do {
            try await driver.trustCurrentCertificate(forDeviceID: "unpaired-id", expectedFingerprint: "unreviewed")
            XCTFail("An unpaired Samsung remote accepted an identity without a pending first-use challenge")
        } catch { }
    }

    func testCommandsHaveWireStringTypes() throws {
        let expected: [RemoteAction: String] = [.up: "KEY_UP", .select: "KEY_ENTER", .back: "KEY_RETURN", .home: "KEY_HOME", .playPause: "KEY_PLAYPAUSE", .volumeUp: "KEY_VOLUP", .volumeDown: "KEY_VOLDOWN", .mute: "KEY_MUTE", .source: "KEY_SOURCE"]
        for (action, key) in expected {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: SamsungProtocol.keyPayload(action)) as? [String: Any])
            let params = try XCTUnwrap(object["params"] as? [String: String])
            XCTAssertEqual(object["method"] as? String, "ms.remote.control")
            XCTAssertEqual(params["Cmd"], "Click")
            XCTAssertEqual(params["DataOfCmd"], key)
            XCTAssertEqual(params["TypeOfRemote"], "SendRemoteKey")
            XCTAssertEqual(params["Option"], "false")
        }
        XCTAssertThrowsError(try SamsungProtocol.keyPayload(.wake))
    }

    func testModernSamsungPowerUsesOneExplicitToggleClick() throws {
        // The maintained samsungtvws power shortcut uses Click KEY_POWER. A transport
        // write does not prove the TV is off, and this payload is never a hold/retry macro.
        let data = try SamsungProtocol.keyPayload(.powerToggle)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let parameters = try XCTUnwrap(object["params"] as? [String: String])
        XCTAssertEqual(object["method"] as? String, "ms.remote.control")
        XCTAssertEqual(parameters, ["Cmd": "Click", "DataOfCmd": "KEY_POWER", "Option": "false", "TypeOfRemote": "SendRemoteKey"])
    }

    func testDiscreteOffAndSleepNeverSilentlyBecomePowerToggles() {
        XCTAssertThrowsError(try SamsungProtocol.keyPayload(.powerOff))
        XCTAssertThrowsError(try SamsungProtocol.keyPayload(.sleep))
        let message = SamsungProtocol.deliveryFailure(for: .powerToggle)
        XCTAssertTrue(message.contains("could not be confirmed"))
        XCTAssertTrue(message.contains("Check the TV before pressing power again"))
        XCTAssertFalse(message.contains("Reconnect and try again"))
    }
}
