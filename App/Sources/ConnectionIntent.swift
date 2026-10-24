/// A manual disconnect belongs to a TV, rather than its room or driver slot.
/// Keep it for this app session so foregrounding and room selection cannot
/// silently undo the user's choice. Only an explicit connection request clears it.
struct ConnectionIntent: Sendable {
    private var disconnectedDeviceIDs: Set<String> = []

    func allowsAutomaticConnection(to deviceID: String?) -> Bool {
        guard let deviceID else { return false }
        return !disconnectedDeviceIDs.contains(deviceID)
    }

    /// Returning to the app must not replace an established or pending session.
    /// Explicit Connect still bypasses this check to retry an unresponsive TV.
    func allowsAutomaticConnection(to deviceID: String?, state: DeviceConnectionState) -> Bool {
        guard allowsAutomaticConnection(to: deviceID) else { return false }
        switch state {
        case .disconnected, .failed: return true
        case .connected, .connecting, .awaitingApproval, .awaitingPin, .trustRequired: return false
        }
    }

    mutating func disconnect(_ deviceID: String) {
        disconnectedDeviceIDs.insert(deviceID)
    }

    mutating func requestConnection(to deviceID: String) {
        disconnectedDeviceIDs.remove(deviceID)
    }
}

enum ConnectionLifecycle {
    /// Established outbound sessions can stay in memory while iOS suspends the
    /// app. Interactive setup is canceled; no new work runs in the background.
    static func preservesSessionOnBackground(_ state: DeviceConnectionState) -> Bool {
        state.isConnected
    }
}
