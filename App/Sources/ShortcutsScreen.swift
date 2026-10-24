import SwiftUI

struct ShortcutsScreen: View {
    @ObservedObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var presentationID: UUID?

    init(store: RemoteStore) {
        self.store = store
        _presentationID = State(initialValue: store.shortcutsPresentationID)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(store.name(.appleTV)) {
                    Button { store.restartXfinityStream() } label: {
                        Label("Restart Xfinity Stream", systemImage: "arrow.clockwise").frame(minHeight: 44)
                    }
                    .disabled(!store.state(.appleTV).isConnected || store.shortcutPhase.isInProgress)
                    .accessibilityIdentifier("restartXfinityStream")
                    Button { store.chooseCurrentAppToRestart() } label: {
                        Label("Restart current app", systemImage: "arrow.clockwise").frame(minHeight: 44)
                    }
                    .disabled(!store.state(.appleTV).isConnected || store.shortcutPhase.isInProgress)
                    .accessibilityIdentifier("restartCurrentApp")
                }
                if store.selected(.appleTV) == nil {
                    Section { Text("Choose an Apple TV in Settings first.") }
                } else if !store.state(.appleTV).isConnected {
                    Section { Text("Connect this Apple TV to run a shortcut.") }
                }
                if store.shortcutPhase != .idle {
                    Section {
                        switch store.shortcutPhase {
                        case .loadingApps: ProgressView("Loading apps…")
                        case .preparing: ProgressView("Opening \(store.shortcutTarget?.name ?? "app")…")
                        case .closing: ProgressView("Restarting \(store.shortcutTarget?.name ?? "app")…")
                        case .completed:
                            Label("\(store.shortcutTarget?.name ?? "App") restart sent", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                                .accessibilityIdentifier("shortcutCompleted")
                        case .idle, .failed: EmptyView()
                        }
                        if let error = store.shortcutError {
                            Text(error).foregroundStyle(.red).accessibilityIdentifier("shortcutError")
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(get: { store.showRestartAppChoice }, set: { if !$0 { store.cancelRestartAppChoice() } })) {
                CurrentAppRestartChoice(store: store)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.closeShortcuts(presentation: presentationID); dismiss() }
                }
            }
        }
        .onDisappear { if let presentationID { store.closeShortcuts(presentation: presentationID) } }
    }
}

private struct CurrentAppRestartChoice: View {
    @ObservedObject var store: RemoteStore

    var body: some View {
        List {
            Section(store.name(.appleTV)) {
                Text("Choose the app currently open on your TV.")
                if store.shortcutPhase == .loadingApps { ProgressView("Loading apps…") }
                ForEach(store.restartAppChoices) { app in
                    Button { store.restartChosenCurrentApp(app) } label: {
                        Text(app.name).frame(minHeight: 44)
                    }
                    .disabled(store.shortcutPhase.isInProgress)
                }
                if let error = store.restartChoiceError { Text(error).foregroundStyle(.red) }
                if store.shortcutPhase != .loadingApps, store.restartAppChoices.isEmpty, store.restartChoiceError == nil {
                    Text("No apps returned by this Apple TV.")
                }
                Button("Reload apps") { store.chooseCurrentAppToRestart() }
                    .disabled(store.shortcutPhase.isInProgress || !store.state(.appleTV).isConnected)
            }
        }
        .navigationTitle("Current app")
        .navigationBarTitleDisplayMode(.inline)
    }
}
