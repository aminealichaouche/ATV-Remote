import SwiftUI

struct AppsScreen: View {
    @ObservedObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var presentationID: UUID?
    @State private var search = ""

    init(store: RemoteStore) {
        self.store = store
        _presentationID = State(initialValue: store.appsPresentationID)
    }
    var body: some View {
        NavigationStack {
            List {
                Section(store.name(.appleTV)) {
                    if store.toolsLoading { ProgressView("Loading installed apps…") }
                    if let error = store.appsError {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("appsError")
                    } else if !store.toolsLoading, store.installedApps.isEmpty {
                        Text("This Apple TV returned no launchable apps.").foregroundStyle(.secondary)
                    }
                    if !store.universalStarsEnabled, let deviceID = store.appleID {
                        NavigationLink {
                            ImportAppStarsScreen(store: store, destinationID: deviceID)
                        } label: {
                            Label("Import stars from another Apple TV", systemImage: "star")
                        }
                        .disabled(!store.appsLoaded || store.toolsLoading || store.appsLaunchingID != nil || store.appStarImportSources(for: deviceID).isEmpty)
                        .accessibilityIdentifier("importAppStars")
                    }
                    if !store.toolsLoading {
                        Button("Reload apps", systemImage: "arrow.clockwise") { store.openApps() }
                            .disabled(store.appsLaunchingID != nil || !store.state(.appleTV).isConnected)
                            .accessibilityIdentifier("reloadApps")
                    }
                }
                let library = store.appLibrary(search: search)
                appSection("Starred", apps: library.starred)
                appSection("Downloaded", apps: library.downloaded)
                appSection("Included", apps: library.included)
                if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   library.starred.isEmpty, library.downloaded.isEmpty, library.included.isEmpty {
                    Text("No matching apps").foregroundStyle(.secondary)
                }
            }.searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search apps")
                .navigationTitle("Apps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.onDisappear {
            if let presentationID { store.closeApps(presentation: presentationID) }
        }
    }

    @ViewBuilder private func appSection(_ title: String, apps: [RemoteAppInfo]) -> some View {
        if !apps.isEmpty {
            Section(title) {
                ForEach(apps) { app in
                    HStack(spacing: 8) {
                        Button { store.launch(app) } label: {
                            HStack(spacing: 12) {
                                Text(app.name).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if store.appsLaunchingID == app.id { ProgressView() }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.toolsLoading || store.appsLaunchingID != nil || !store.state(.appleTV).isConnected)
                        .accessibilityLabel("Open \(app.name)")
                        .accessibilityIdentifier("launchApp.\(app.id)")
                        Button { store.toggleAppStar(app) } label: {
                            Image(systemName: store.isAppStarred(app.id) ? "star.fill" : "star")
                                .foregroundStyle(store.isAppStarred(app.id) ? Color.yellow : Color.secondary)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.toolsLoading)
                        .accessibilityLabel("\(store.isAppStarred(app.id) ? "Unstar" : "Star") \(app.name)")
                        .accessibilityValue(store.isAppStarred(app.id) ? "Starred" : "Not starred")
                        .accessibilityIdentifier("starApp.\(app.id)")
                    }
                }
            }
        }
    }

}

struct ImportAppStarsScreen: View {
    @ObservedObject var store: RemoteStore
    let destinationID: String
    @Environment(\.dismiss) private var dismiss
    @State private var sourceID: String?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Picker("From Apple TV", selection: $sourceID) {
                    Text("Choose an Apple TV").tag(String?.none)
                    ForEach(store.appStarImportSources(for: destinationID)) { device in
                        Text("\(device.name) · \(device.address)").tag(String?.some(device.id))
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("appStarSource")
                if let sourceID {
                    let count = store.registry.starredAppIDs(for: sourceID).count
                    Text("\(count) saved stars · \(store.installedStarCount(from: sourceID)) matching installed apps")
                        .font(.subheadline)
                    Button("Import stars") {
                        do {
                            _ = try store.importAppStars(from: sourceID, to: destinationID)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(store.universalStarsEnabled || count == 0 || !store.appsLoaded || store.toolsLoading || store.appsLaunchingID != nil || store.appleID != destinationID)
                    .accessibilityIdentifier("confirmAppStarImport")
                }
                if let error { Text(error).foregroundStyle(.red) }
            } header: {
                Text("Import into \(store.registry.device(destinationID, kind: .appleTV)?.name ?? "Apple TV")")
            } footer: {
                Text("Adds to this TV’s stars. Apps that aren’t installed stay hidden and appear starred if installed later. The other TV’s stars stay the same.")
            }
        }
        .navigationTitle("Import stars")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: sourceID) { _, _ in error = nil }
    }
}

