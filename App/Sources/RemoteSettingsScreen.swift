import SwiftUI

struct RemoteSettingsScreen: View {
    @ObservedObject var store: RemoteStore
    @AppStorage(RemoteLayout.storageKey) private var remoteLayout: RemoteLayout = RemoteLayout.defaultLayout

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    deviceRows(.appleTV)
                    deviceRows(.samsung)
                } header: {
                    Text(store.currentRoom.name)
                        .textCase(nil)
                        .accessibilityIdentifier("roomGroupTVs")
                }
                if store.isCustomPair {
                    Section("Room assignment") {
                        Text("These selected TVs differ from the saved pair for \(store.currentRoom.name). Pairing a TV keeps this room’s saved assignments until you choose Save.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Save this pair for \(store.currentRoom.name)") { store.saveAssignments() }
                            .accessibilityIdentifier("saveRoomPair")
                    }
                }
                layoutSettings
                Section {
                    Toggle("Universal stars", isOn: Binding(
                        get: { store.universalStarsEnabled },
                        set: { store.setUniversalStarsEnabled($0) }
                    ))
                    .accessibilityIdentifier("universalStarsToggle")
                } header: { Text("Apps") }
                footer: { Text("Use the same stars on every Apple TV. Only installed apps appear.") }
                management
                Section {
                    Text("Selecting a TV here is temporary until you save the pair. Choosing a room on the remote restores that room’s saved TVs.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("ATV Remote \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · Same home network required")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(store.currentRoom.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { store.sheet = nil } }
            }
        }
    }

    private var layoutSettings: some View {
        Section("Remote layout") {
            Menu {
                Picker("Layout", selection: $remoteLayout) {
                    ForEach(RemoteLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(remoteLayout.title)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 20)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remote layout")
            .accessibilityValue(remoteLayout.title)
            .accessibilityIdentifier("remoteLayoutPicker")
        }
    }

    @ViewBuilder private func deviceRows(_ kind: DeviceKind) -> some View {
        HStack(spacing: 16) {
            Menu {
                Picker(kind.title, selection: Binding<String?>(
                    get: { store.selected(kind)?.id },
                    set: { store.setSelection($0, kind: kind) }
                )) {
                    Text("None").tag(String?.none)
                    ForEach(store.devices.filter { $0.kind == kind }) { device in
                        Text("\(device.settingsDisplayName) · \(device.address)").tag(String?.some(device.id))
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(kind.title).font(.caption).foregroundStyle(.secondary)
                        Text(store.selected(kind)?.settingsDisplayName ?? "Choose a TV")
                            .lineLimit(1).truncationMode(.middle)
                        if let device = store.selected(kind) {
                            Text(device.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
                .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(kind.title)
            .accessibilityValue(store.selected(kind).map { "\($0.settingsDisplayName), \($0.address)" } ?? "None")
            .accessibilityIdentifier(kind == .appleTV ? "appleDeviceMenu" : "samsungDeviceMenu")
            if let device = store.selected(kind) {
                VStack(spacing: 4) {
                    Button { store.connectionAction(kind) } label: {
                        Text(store.connectionActionTitle(kind)).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(store.connectionActionTitle(kind)) \(kind.title), \(device.name)")
                    .accessibilityIdentifier(kind == .appleTV ? "appleConnectionAction" : "samsungConnectionAction")
                    HStack(spacing: 5) {
                        Circle().fill(store.state(kind).isConnected ? Color.green : Color.gray).frame(width: 6, height: 6)
                        if store.state(kind) == .connecting || store.state(kind) == .awaitingApproval {
                            ProgressView().controlSize(.mini)
                        }
                    }.accessibilityLabel(store.state(kind).title)
                        .accessibilityIdentifier(kind == .appleTV ? "appleConnectionState" : "samsungConnectionState")
                }.fixedSize(horizontal: true, vertical: false)
            }
        }.padding(.vertical, 4)
    }

    private var management: some View {
        Section("Manage setup") {
            NavigationLink { DevicesScreen(store: store, embedded: true) } label: {
                Label("Manage TVs", systemImage: "tv")
            }
                .accessibilityIdentifier("manageDevices")
            NavigationLink { RoomsScreen(store: store, embedded: true) } label: {
                Label("Manage rooms", systemImage: "door.left.hand.open")
            }
                .accessibilityIdentifier("manageRooms")
            NavigationLink { TransferScreen(store: store, embedded: true) } label: {
                Label("Share or import setup", systemImage: "square.and.arrow.up")
            }
                .accessibilityIdentifier("transferSetup")
        }
    }
}
