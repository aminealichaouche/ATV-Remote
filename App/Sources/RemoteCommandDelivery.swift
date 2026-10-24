import Foundation
import SwiftATV

/// Records one command attempt. A missing acknowledgement is not permission to
/// replay a press; the caller may refresh the connection for future commands.
struct RemoteCommandDelivery: Sendable {
    let error: (any Error)?
    let refreshAppleTVConnection: Bool

    static let recoveryMessage = "Apple TV didn’t reply. Reconnecting… The button press may already have reached the TV."

    static func perform(_ action: RemoteAction, to kind: DeviceKind,
                        operation: @Sendable () async throws -> Void) async -> Self {
        do {
            try await operation()
            return Self(error: nil, refreshAppleTVConnection: false)
        } catch {
            return Self(error: error, refreshAppleTVConnection: shouldRefresh(after: error, action: action, to: kind))
        }
    }

    static func shouldRefresh(after error: any Error, action: RemoteAction, to kind: DeviceKind) -> Bool {
        let cause = (error as? AppRestartFailure)?.underlying ?? error
        // Opening another session after sleep could undo the user's intent.
        guard kind == .appleTV, action != .sleep, action != .powerOff,
              let error = cause as? ATVError, case .operationTimeout(let context) = error else { return false }
        return context.protocol == .companion && context.operation == "request" && context.requestID == "_hidC"
    }
}
