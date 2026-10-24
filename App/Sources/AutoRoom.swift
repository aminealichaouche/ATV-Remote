import Foundation

enum RoomMenuSelection: Hashable { case automatic, room(String) }

struct AutoRoomCandidate: Sendable, Equatable {
    let device: RemoteDevice
    let roomIDs: [String]
}

enum AutoRoomPolicy {
    // Hidden until room detection can choose rooms reliably.
    static let isAvailable = false
    static let preferenceKey = "RoomRemote.autoRoom.v1"
    static let statusInterval: Duration = .seconds(3)
    static let retryInterval: Duration = .seconds(3)
    static let maximumConcurrentTrials = 4

    /// Shared TVs get one trial. The current room wins an ambiguous shared-TV
    /// match; otherwise saved room order breaks the tie deterministically.
    static func candidates(registry: DeviceRegistry, preferredRoomID: String,
                           intent: ConnectionIntent) -> [AutoRoomCandidate] {
        let rooms = registry.rooms.filter { $0.id == preferredRoomID } + registry.rooms.filter { $0.id != preferredRoomID }
        var result: [AutoRoomCandidate] = []
        for room in rooms {
            for kind in [DeviceKind.appleTV, .samsung] {
                let id = kind == .appleTV ? room.appleID : room.samsungID
                guard let device = registry.device(id, kind: kind),
                      intent.allowsAutomaticConnection(to: device.id) else { continue }
                if let index = result.firstIndex(where: { $0.device.id == device.id }) {
                    let old = result[index]
                    result[index] = AutoRoomCandidate(device: old.device, roomIDs: old.roomIDs + [room.id])
                } else {
                    result.append(AutoRoomCandidate(device: device, roomIDs: [room.id]))
                }
            }
        }
        return result
    }

    static func connectedRoom(candidates: [AutoRoomCandidate], deviceIDs: Set<String>) -> String? {
        candidates.first { deviceIDs.contains($0.device.id) }?.roomIDs.first
    }

    /// A poll can downgrade a stale green dot. Pending/error detail stays owned
    /// by the driver callback; a poll never fabricates a successful handshake.
    static func refreshedState(_ state: DeviceConnectionState, transportConnected: Bool) -> DeviceConnectionState {
        state.isConnected && !transportConnected ? .disconnected : state
    }
}

struct AutoRoomRaceResult<Target: Sendable, Connection: Sendable>: Sendable {
    let target: Target
    let connection: Connection
}

enum AutoRoomRace {
    /// Returns the first successfully authenticated connection, not a listening
    /// TCP port. Every other successful connection is closed, including late
    /// successes after cancellation. The caller owns the returned winner.
    static func firstSuccess<Target: Sendable, Connection: Sendable>(
        targets: [Target], maximumConcurrent: Int = AutoRoomPolicy.maximumConcurrentTrials,
        probe: @escaping @Sendable (Target) async -> Connection?,
        discard: @escaping @Sendable (Connection) async -> Void
    ) async -> AutoRoomRaceResult<Target, Connection>? {
        guard !targets.isEmpty, !Task.isCancelled else { return nil }
        var winner: AutoRoomRaceResult<Target, Connection>?
        await withTaskGroup(of: AutoRoomRaceResult<Target, Connection>?.self) { group in
            var next = 0
            let limit = min(targets.count, max(1, maximumConcurrent))
            for _ in 0..<limit {
                let target = targets[next]; next += 1
                group.addTask {
                    let connection = await probe(target)
                    return connection.map { AutoRoomRaceResult(target: target, connection: $0) }
                }
            }
            while let completion = await group.next() {
                if let completion {
                    if winner == nil, !Task.isCancelled {
                        winner = completion
                        group.cancelAll()
                    } else {
                        await discard(completion.connection)
                    }
                }
                if winner == nil, !Task.isCancelled, next < targets.count {
                    let target = targets[next]; next += 1
                    group.addTask {
                        let connection = await probe(target)
                        return connection.map { AutoRoomRaceResult(target: target, connection: $0) }
                    }
                }
            }
        }
        if Task.isCancelled, let winner {
            await discard(winner.connection)
            return nil
        }
        return winner
    }
}

struct AutoRoomConnection: Sendable {
    let device: RemoteDevice
    let driver: any RemoteDriver
}
