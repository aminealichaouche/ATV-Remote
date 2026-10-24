import Foundation

enum AppRestartStage: String, Sendable {
    case opening = "Open app"
    case switcher = "Open app switcher"
    case closing = "Close gesture"
    case reopening = "Reopen app"
}

struct AppRestartFailure: LocalizedError {
    let stage: AppRestartStage
    let underlying: any Error
    var errorDescription: String? { "\(stage.rawValue) failed: \(underlying.localizedDescription)" }
}

/// A staged shortcut tied to one selected TV and one live connection. It is not
/// Codable and cannot be restored or transferred as a pending control action.
struct AppleAppRestartContext: Equatable, Sendable {
    let deviceID: String
    let sessionID: UUID
    let appID: String
    let workflowID: UUID

    init(deviceID: String, sessionID: UUID, appID: String, workflowID: UUID = UUID()) {
        self.deviceID = deviceID
        self.sessionID = sessionID
        self.appID = appID
        self.workflowID = workflowID
    }
}

/// Runs one launch/switcher/swipe/relaunch macro for an explicitly identified
/// installed app. tvOS card focus and process termination are not acknowledged;
/// every effect remains scoped to the original TV/session and is never retried.
struct AppRestartWorkflow: Sendable {
    static let xfinityAppID = "com.comcast.cim.x2"

    enum TouchPhase: Sendable, Equatable { case press, hold, release }
    struct TouchSample: Sendable, Equatable {
        let x: Int
        let y: Int
        let phase: TouchPhase
    }

    struct Steps: Sendable {
        let validate: @Sendable (AppleAppRestartContext) async throws -> Void
        let fetchAppIDs: @Sendable () async throws -> [String]
        let launchApp: @Sendable (String) async throws -> Void
        let showSwitcher: @Sendable () async throws -> Void
        let wait: @Sendable (UInt64) async throws -> Void
        let touch: @Sendable (TouchSample) async throws -> Void
        /// Cleanup is deliberately scoped to the original captured touch sender.
        /// It bypasses caller cancellation and current-selection validation,
        /// performs only a release, and must not reconnect or retry.
        let releaseOriginalTouch: @Sendable (TouchSample) async -> Void
    }

    let context: AppleAppRestartContext
    let supportsSwipe: Bool
    let steps: Steps

    static func validAppID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 512 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty } && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-")
        }
    }

    func run(onPrepared: @Sendable () async throws -> Void = {}) async throws {
        try await prepare()
        try await checked { try await onPrepared() }
        try await finish()
    }

    func prepare() async throws {
        try await check()
        guard supportsSwipe else {
            throw RemoteFailure.message("This Apple TV has not provided swipe support for the restart shortcut.")
        }
        let appIDs = try await checked { try await steps.fetchAppIDs() }
        guard appIDs.contains(context.appID) else {
            throw RemoteFailure.message("The chosen app is not in this Apple TV’s installed app list.")
        }
        try await checked(stage: .opening) { try await steps.launchApp(context.appID) }
        try await checked { try await steps.wait(2_000_000_000) }
        try await checked(stage: .switcher) { try await steps.showSwitcher() }
        try await checked { try await steps.wait(1_000_000_000) }
    }

    func finish() async throws {
        try await check()
        guard supportsSwipe else {
            throw RemoteFailure.message("This Apple TV has not provided swipe support for the restart shortcut.")
        }
        try await checked(stage: .closing) { try await upwardSwipe() }
        // Launch by bundle ID directly from the switcher. An extra Back HID
        // request could time out after closing, preventing the relaunch entirely.
        try await checked { try await steps.wait(1_200_000_000) }
        try await checked(stage: .reopening) { try await steps.launchApp(context.appID) }
    }

    private func upwardSwipe() async throws {
        var touchMayBeDown = false
        var lastPoint = TouchSample(x: 500, y: 1000, phase: .press)
        do {
            // Mark before awaiting press: a failed acknowledgement/write may
            // still have reached the peer, so cleanup releases that original touch.
            let initialPoint = lastPoint
            try await checked {
                touchMayBeDown = true
                try await steps.touch(initialPoint)
            }
            // Fewer frames shorten the flick and limit per-frame transport and
            // validation overhead. Keep one full-height gesture, with movement
            // to the endpoint before release; never repeat on the next app card.
            // This is gesture tuning, not a verified tvOS force-quit threshold.
            for index in 1...6 {
                try await checked { try await steps.wait(16_000_000) }
                let point = TouchSample(x: 500, y: 1000 - 1000 * index / 6, phase: .hold)
                try await checked {
                    lastPoint = point
                    try await steps.touch(point)
                }
            }
            try await checked { try await steps.wait(16_000_000) }
            let release = TouchSample(x: lastPoint.x, y: lastPoint.y, phase: .release)
            try await checked {
                lastPoint = release
                try await steps.touch(release)
            }
            touchMayBeDown = false
        } catch {
            if touchMayBeDown {
                let release = TouchSample(x: lastPoint.x, y: lastPoint.y, phase: .release)
                await steps.releaseOriginalTouch(release)
            }
            throw error
        }
    }

    private func check() async throws {
        try Task.checkCancellation()
        guard !context.deviceID.isEmpty, Self.validAppID(context.appID) else {
            throw RemoteFailure.message("This restart shortcut has an invalid app or TV target.")
        }
        try await steps.validate(context)
        try Task.checkCancellation()
    }

    private func checked<Value: Sendable>(stage: AppRestartStage? = nil,
                                          _ operation: () async throws -> Value) async throws -> Value {
        try await check()
        let value: Value
        do { value = try await operation() }
        catch is CancellationError { throw CancellationError() }
        catch {
            guard let stage else { throw error }
            throw AppRestartFailure(stage: stage, underlying: error)
        }
        try await check()
        return value
    }
}
