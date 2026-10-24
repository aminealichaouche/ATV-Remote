import Foundation
import Testing
@testable import SwiftATV

@Suite("Companion apps: session registration and real peer replies")
struct CompanionAppsReplyTests {
    private func response(_ content: OPACK.Value, extra: [(String, OPACK.Value)] = []) -> OPACK.Value {
        .dictionary([("_t", .uint(3)), ("_x", .uint(123)), ("_c", content)] + extra)
    }

    @Test("A primary-documented result-type-1 app list preserves bundle IDs and names")
    func documentedList() throws {
        let reply = response(.dictionary([("com.example.Player", .string("Player")),
            ("com.example.Search", .string("Search"))]), extra: [("_rT", .uint(1))])
        // Exercise actual OPACK wire serialization and decoding, then the parser.
        let apps = try CompanionAppsReply.parseAppList(OPACK.decode(OPACK.encode(reply)))
        #expect(apps == [App(name: "Player", identifier: "com.example.Player"),
            App(name: "Search", identifier: "com.example.Search")])
    }

    @Test("A genuine empty dictionary is distinguishable from malformed content")
    func genuineEmptyList() throws {
        #expect(try CompanionAppsReply.parseAppList(response(.dict([]))).isEmpty)
        #expect(throws: ATVError.self) {
            _ = try CompanionAppsReply.parseAppList(.dictionary([("_t", .uint(3))]))
        }
        #expect(throws: ATVError.self) { _ = try CompanionAppsReply.parseAppList(response(.array([]))) }
    }

    @Test("Invalid names/IDs and duplicate IDs cannot silently become a partial or empty list")
    func malformedEntries() {
        let malformed: [OPACK.Value] = [
            .dict([(.uint(1), .string("Player"))]),
            .dictionary([("com.example.Player", .uint(1))]),
            .dictionary([("com.example.Player", .string("A")), ("com.example.Player", .string("B"))]),
        ]
        for content in malformed {
            #expect(throws: ATVError.self) { _ = try CompanionAppsReply.parseAppList(response(content)) }
        }
    }

    @Test("An actual unlabelled app is retained using its returned identifier")
    func blankLabel() throws {
        let apps = try CompanionAppsReply.parseAppList(response(.dictionary([("com.example.Player", .string(""))])))
        #expect(apps == [App(name: nil, identifier: "com.example.Player")])
    }

    @Test("The primary issue #2868 FBS error envelope is a failed launch")
    func fbsLaunchError() throws {
        let rejected = response(.dict([]), extra: [
            ("_eu", .dictionary([("_ec", .uint(4)), ("_ed", .string("FBSOpenApplicationErrorDomain"))])),
            ("_rT", .uint(8)), ("_ed", .string("FBSOpenApplicationServiceErrorDomain")), ("_ec", .uint(4)),
        ])
        let wireReply = try OPACK.decode(OPACK.encode(rejected))
        do {
            try CompanionAppsReply.validateLaunch(wireReply)
            Issue.record("App-launch rejection was treated as success")
        } catch let error {
            guard case .protocolError(let message) = error else {
                Issue.record("Expected a protocol error with peer rejection details")
                return
            }
            #expect(message.contains("FBSOpenApplicationErrorDomain"))
            #expect(message.contains("code 4"))
        }
        #expect(throws: ATVError.self) { _ = try CompanionAppsReply.parseAppList(wireReply) }
    }

    @Test("A launch needs a real acknowledgement; malformed error codes fail")
    func acknowledgement() throws {
        try CompanionAppsReply.validateLaunch(response(.dict([])))
        #expect(throws: ATVError.self) {
            try CompanionAppsReply.validateLaunch(.dictionary([("_t", .uint(3))]))
        }
        #expect(throws: ATVError.self) {
            try CompanionAppsReply.validateLaunch(response(.dict([]), extra: [("_ec", .string("invalid"))]))
        }
    }

    @Test("App query registers the documented TVRC session before fetching apps")
    func registrationOrdering() async throws {
        let fixture = Fixture(list: response(.dictionary([("com.example.Player", .string("Player"))])))
        let state = CompanionStateStore()
        let apps = CompanionApps(request: { identifier, content, timeout throws(ATVError) in
            try await fixture.exchange(identifier, content: content, timeout: timeout)
        }, stateStore: state)
        #expect(try await apps.appList().count == 1)
        let calls = await fixture.calls
        #expect(calls.map(\.identifier) == ["TVRCSessionStart", "FetchLaunchableApplicationsEvent"])
        #expect(calls[0].content["ProtocolVersionKey"]?.stringValue == "1.2")
        #expect(calls[0].timeout == 3)
        #expect(state.capabilityInfo(.apps(.list)).state == .available)
    }

    @Test("Launch registers the same scoped handler and sends the actual bundle ID")
    func launchOrdering() async throws {
        let fixture = Fixture(list: response(.dict([])))
        let apps = CompanionApps(request: { identifier, content, timeout throws(ATVError) in
            try await fixture.exchange(identifier, content: content, timeout: timeout)
        })
        try await apps.launchApp(bundleID: "com.example.Player")
        let calls = await fixture.calls
        #expect(calls.map(\.identifier) == ["TVRCSessionStart", "_launchApp"])
        #expect(calls[1].content["_bundleID"]?.stringValue == "com.example.Player")
        _ = try await apps.appList()
        #expect(await fixture.calls.map(\.identifier) == ["TVRCSessionStart", "_launchApp", "FetchLaunchableApplicationsEvent"])
    }

    @Test("Older unsupported registration and its scoped timeout still allow a real list")
    func optionalRegistration() async throws {
        for outcome in [Fixture.Outcome.unsupported, .timeout] {
            let fixture = Fixture(list: response(.dictionary([("com.example.Player", .string("Player"))])), registration: outcome)
            let apps = CompanionApps(request: { identifier, content, timeout throws(ATVError) in
                try await fixture.exchange(identifier, content: content, timeout: timeout)
            })
            #expect(try await apps.appList().count == 1)
            #expect(await fixture.calls.count == 2)
        }
    }

    @Test("Connection loss, cancellation, and authentication rejection never continue into a fetch")
    func terminalRegistration() async {
        for outcome in [Fixture.Outcome.closed, .cancelled, .authentication] {
            let fixture = Fixture(list: response(.dict([])), registration: outcome)
            let apps = CompanionApps(request: { identifier, content, timeout throws(ATVError) in
                try await fixture.exchange(identifier, content: content, timeout: timeout)
            })
            await #expect(throws: ATVError.self) { _ = try await apps.appList() }
            #expect(await fixture.calls.count == 1)
        }
    }

    @Test("Caller cancellation while registration waits never sends a deferred launch")
    func cancelledDeferredLaunch() async throws {
        let blocker = RegistrationBlocker()
        let apps = CompanionApps(request: { identifier, content, timeout throws(ATVError) in
            try await blocker.exchange(identifier)
        })
        let launch = Task { try await apps.launchApp(bundleID: "com.example.Player") }
        while !(await blocker.started) { await Task.yield() }
        launch.cancel()
        await blocker.release()
        do {
            try await launch.value
            Issue.record("Cancelled app launch returned success")
        } catch { }
        #expect(await blocker.calls == ["TVRCSessionStart"])
    }

    @Test("Malformed app content does not advertise a successfully available apps capability")
    func capabilityAfterFailure() async {
        let fixture = Fixture(list: response(.array([])))
        let state = CompanionStateStore()
        let apps = CompanionApps(request: { identifier, content, timeout throws(ATVError) in
            try await fixture.exchange(identifier, content: content, timeout: timeout)
        }, stateStore: state)
        await #expect(throws: ATVError.self) { _ = try await apps.appList() }
        #expect(state.capabilityInfo(.apps(.list)).state == .unavailable)
    }

    private actor RegistrationBlocker {
        var calls: [String] = []
        var started = false
        private var waiter: CheckedContinuation<Void, Never>?
        func exchange(_ identifier: String) async throws(ATVError) -> OPACK.Value {
            calls.append(identifier)
            if identifier == "TVRCSessionStart" {
                await withCheckedContinuation { continuation in waiter = continuation; started = true }
            }
            return .dictionary([("_t", .uint(3)), ("_c", .dict([]))])
        }
        func release() { waiter?.resume(); waiter = nil }
    }

    private actor Fixture {
        enum Outcome: Sendable { case supported, unsupported, timeout, closed, cancelled, authentication }
        struct Call: Sendable {
            let identifier: String
            let content: OPACK.Value
            let timeout: TimeInterval?
        }
        let list: OPACK.Value
        let registration: Outcome
        var calls: [Call] = []
        init(list: OPACK.Value, registration: Outcome = .supported) {
            self.list = list
            self.registration = registration
        }
        func exchange(_ identifier: String, content: OPACK.Value, timeout: TimeInterval?) throws(ATVError) -> OPACK.Value {
            calls.append(Call(identifier: identifier, content: content, timeout: timeout))
            if identifier == "TVRCSessionStart" {
                switch registration {
                case .supported: return .dictionary([("_t", .uint(3)), ("_c", .dictionary([("ProtocolVersionKey", .string("1.2"))]))])
                case .unsupported: throw ATVError.protocolError("No request handler")
                case .timeout: throw ATVError.operationTimeout(.init(protocol: .companion, operation: "request", requestID: identifier, duration: 3))
                case .closed: throw ATVError.connectionLost("Closed old fixture session")
                case .cancelled: throw ATVError.operationCancelled(.init(protocol: .companion, operation: "request", requestID: identifier, duration: 3))
                case .authentication: throw ATVError.protocolError("Authentication rejected")
                }
            }
            if identifier == "FetchLaunchableApplicationsEvent" { return list }
            if identifier == "_launchApp" { return .dictionary([("_t", .uint(3)), ("_c", .dict([]))]) }
            throw ATVError.invalidState("Unexpected fixture request")
        }
    }
}
