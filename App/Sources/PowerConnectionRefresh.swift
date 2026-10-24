import Foundation

/// An off attempt can close the transport before the regular status tick.
/// Observe that session once, without sending a probe or reconnecting it.
enum PowerConnectionRefresh {
    static let delay: Duration = .seconds(1)

    static func shouldCheck(_ action: RemoteAction, to kind: DeviceKind) -> Bool {
        switch (kind, action) {
        case (.appleTV, .sleep), (.appleTV, .powerOff), (.samsung, .powerToggle): true
        default: false
        }
    }

    @MainActor
    static func run(
        wait: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        isCurrent: @MainActor () -> Bool,
        observe: @MainActor () async -> Bool,
        update: @MainActor (Bool) -> Void
    ) async {
        guard !Task.isCancelled, isCurrent() else { return }
        do { try await wait(delay) } catch { return }
        guard !Task.isCancelled, isCurrent() else { return }
        let connected = await observe()
        guard !Task.isCancelled, isCurrent() else { return }
        update(connected)
    }
}
