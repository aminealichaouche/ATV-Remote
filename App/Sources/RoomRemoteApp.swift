import SwiftUI

@main
struct RoomRemoteApp: App {
    @StateObject private var store = RemoteStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RemoteScreen(store: store)
                .overlay {
                    if phase != .active {
                        Color(.systemGroupedBackground).ignoresSafeArea()
                            .overlay { Label("ATV Remote", systemImage: "lock") }
                    }
                }
                .onChange(of: phase, initial: true) { _, phase in
                    if phase == .active { store.setActive(true) }
                    else if phase == .background { store.setActive(false) }
                }
                .onOpenURL { store.openTransfer($0) }
        }
    }
}
