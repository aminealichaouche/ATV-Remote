import SwiftUI

struct DevicesScreen: View {
    @ObservedObject var store: RemoteStore
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var savedExpanded = false

    @ViewBuilder var body: some View {
        if embedded { content }
        else { NavigationStack { content } }
    }

    private var content: some View {
        Form {
            Section {
                Button { withAnimation(.easeInOut(duration: 0.18)) { savedExpanded.toggle() } } label: {
                    HStack {
                        Text("Saved TVs (\(store.devices.count))").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: savedExpanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.borderless)
                .accessibilityValue(savedExpanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("savedTVsDisclosure")
                if savedExpanded {
                    ForEach(store.devices) { device in
                        NavigationLink { ManageTVScreen(store: store, deviceID: device.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: device.kind == .samsung ? "tv" : "appletv")
                                    .foregroundStyle(.tint).frame(width: 28)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(device.name).font(.body.weight(.medium))
                                    Text("\(device.kind.title) · \(device.address)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("manageTV." + device.id)
                    }
                    if store.devices.isEmpty { Text("No TVs added yet.").foregroundStyle(.secondary) }
                }
            }
            Section {
                NavigationLink { AddTVScreen(store: store) } label: {
                    Label("Add a TV", systemImage: "plus").foregroundStyle(.blue)
                }.accessibilityIdentifier("addTV")
            }
            Section {
                NavigationLink { TransferScreen(store: store, embedded: true) } label: {
                    Label("Share or import setup", systemImage: "square.and.arrow.up")
                }.accessibilityIdentifier("transferSetup")
                Button("Open iPhone app settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .navigationTitle("Your TVs").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if embedded { store.sheet = nil } else { dismiss() } } } }
    }
}

struct AddTVScreen: View {
    @ObservedObject var store: RemoteStore
    @State private var name = ""
    @State private var address = ""
    @State private var wakeMACAddress = ""
    @State private var kind = DeviceKind.samsung
    @State private var validationError: String?
    @State private var scanDraft: ScanDraft?
    private struct ScanDraft: Identifiable {
        let id = UUID()
        let address: String
        let mac: String
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) { ForEach(DeviceKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                if kind == .samsung {
                    TextField("Name, e.g. Bedroom Samsung", text: $name).textInputAutocapitalization(.words)
                    HStack {
                        TextField("TV’s local IP address", text: $address)
                            .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button { scanDraft = ScanDraft(address: address, mac: wakeMACAddress) } label: {
                            Image(systemName: "text.viewfinder").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Scan TV IP address")
                        .accessibilityIdentifier("scanNewSamsungTVIP")
                    }
                    HStack {
                        TextField("MAC address for power-on (optional)", text: $wakeMACAddress)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .accessibilityIdentifier("newSamsungWakeMAC")
                        Button { scanDraft = ScanDraft(address: address, mac: wakeMACAddress) } label: {
                            Image(systemName: "text.viewfinder").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Scan TV MAC address")
                        .accessibilityIdentifier("scanNewSamsungTVMAC")
                    }
                    Button("Add and pair Samsung TV") {
                        do { try store.addSamsung(name: name, address: address, wakeMACAddress: wakeMACAddress) }
                        catch { validationError = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || address.isEmpty)
                    if let validationError { Text(validationError).foregroundStyle(.red).font(.footnote) }

                } else {
                    Button { store.discoverAppleTVs() } label: { HStack { Text("Find Apple TVs"); Spacer(); if store.isDiscovering { ProgressView() } else { Image(systemName: "magnifyingglass") } } }.disabled(store.isDiscovering)
                    ForEach(store.discoveredAppleTVs) { device in
                        Button { store.addApple(device) } label: {
                            VStack(alignment: .leading) { Text(device.name); Text(device.address).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Text("Connect to home Wi-Fi and allow Local Network access. Pairing displays a code on the Apple TV. You can rename devices after adding them.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Add a TV").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $scanDraft) { draft in
            TVPhotoScanScreen(initialAddress: draft.address, initialMACAddress: draft.mac) { result in
                if let ip = result.ipAddresses.first { address = ip }
                if let mac = result.macAddresses.first { wakeMACAddress = mac.address }
                validationError = nil
            }.id(draft.id)
        }
    }
}

struct ApplePINScreen: View {
    @ObservedObject var store: RemoteStore
    let deviceID: String
    @State private var pin = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Pair \(store.devices.first { $0.id == deviceID }?.name ?? "Apple TV")").font(.headline)
                    Text("Enter the four-digit code shown on that TV.")
                    SecureField("Pairing code", text: $pin).keyboardType(.numberPad)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                    Button(busy ? "Pairing…" : "Pair Apple TV") {
                        guard pin.utf8.count == 4, pin.utf8.allSatisfy({ (48...57).contains($0) }) else { error = "Enter a four-digit code."; return }
                        let submitted = pin; pin = ""; busy = true; error = nil
                        Task { do { try await store.submitPIN(submitted, deviceID: deviceID) } catch { self.error = error.localizedDescription }; busy = false }
                    }.disabled(busy)
                }
            }
            .navigationTitle("Pair Apple TV")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pin = ""; store.cancelSetup(.appleTV) } } }
        }.interactiveDismissDisabled()
    }
}

struct SamsungTrustScreen: View {
    @ObservedObject var store: RemoteStore
    let deviceID: String
    let fingerprint: String
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Confirm your Samsung TV") {
                    Text(store.devices.first { $0.id == deviceID }?.name ?? "Samsung TV").font(.headline)
                    Text("\(store.devices.first { $0.id == deviceID }?.address ?? "")").font(.subheadline).foregroundStyle(.secondary)
                    Text("Only continue if this is your TV’s local IP address and you’re on your trusted home network. The app will remember this TV’s certificate and reject unexpected changes.")
                    DisclosureGroup("Certificate fingerprint") { Text(fingerprint).font(.caption.monospaced()).textSelection(.enabled) }
                    Text("After continuing, choose Allow for this remote’s access request on the TV.").font(.footnote).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                    Button(busy ? "Connecting…" : "Trust this TV and request access") {
                        busy = true
                        Task { do { try await store.confirmTrust(deviceID: deviceID, fingerprint: fingerprint) } catch { self.error = error.localizedDescription; store.alertMessage = error.localizedDescription }; busy = false }
                    }.disabled(busy)
                }
            }.navigationTitle("Pair Samsung TV")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { store.cancelSetup(.samsung) } } }
        }.interactiveDismissDisabled()
    }
}

struct RoomsScreen: View {
    @ObservedObject var store: RemoteStore
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var editing: RoomProfile?
    @State private var deletingRoom: RoomProfile?
    // Delete buttons appear only after Edit, so a row tap reads as "open".
    @State private var isEditing = false
    @ViewBuilder var body: some View {
        if embedded { content }
        else { NavigationStack { content } }
    }

    private var content: some View {
        List {
            Section("Saved room groups") {
                ForEach(store.rooms) { room in
                    HStack {
                    Button { editing = room } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(room.name).font(.headline).foregroundStyle(.primary)
                                Text(deviceLabel(room.samsungID, kind: .samsung)).font(.caption).foregroundStyle(.secondary)
                                Text(deviceLabel(room.appleID, kind: .appleTV)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            if !isEditing {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit this room")
                    if isEditing {
                        Button(role: .destructive) { deletingRoom = room } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("Delete " + room.name)
                        .accessibilityIdentifier("deleteRoom." + room.id)
                    }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { deletingRoom = room } }
                }
            }
            Button("Add a room", systemImage: "plus") { editing = RoomProfile(name: "") }
            Section { Text("A room remembers one Samsung TV and one Apple TV. Either can be empty. Choosing a room selects its saved pair; individual dropdown changes stay temporary until you save them.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.default, value: isEditing)
            .onChange(of: store.rooms.isEmpty) { _, empty in if empty { isEditing = false } }
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isEditing = false }.accessibilityIdentifier("finishEditingRooms")
                    }
                } else {
                    if !store.rooms.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Edit") { isEditing = true }.accessibilityIdentifier("editRooms")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { close() } }
                }
            }
            .sheet(item: $editing) { room in RoomEditor(store: store, room: room) }
            .confirmationDialog("Delete room?", isPresented: Binding(get: { deletingRoom != nil }, set: { if !$0 { deletingRoom = nil } }), titleVisibility: .visible, presenting: deletingRoom) { room in
                Button("Delete room", role: .destructive) { store.deleteRoom(room.id); deletingRoom = nil }
            } message: { room in Text("Delete \(room.name)? Saved TVs and starred apps are kept.") }
    }

    private func close() {
        if embedded { store.sheet = nil } else { dismiss() }
    }

    private func deviceLabel(_ id: String?, kind: DeviceKind) -> String {
        guard let device = store.registry.device(id, kind: kind) else { return "No \(kind.title)" }
        return "\(device.name) (\(kind == .samsung ? "Samsung" : "Apple TV"))"
    }
}

struct RoomEditor: View {
    @ObservedObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @State var room: RoomProfile
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Room name", text: $room.name)
                deviceSelector(.samsung, selection: $room.samsungID)
                deviceSelector(.appleTV, selection: $room.appleID)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.navigationTitle("Room group")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { do { try store.saveRoom(room); if store.currentRoom.id == room.id { store.selectRoom(room.id) }; dismiss() } catch { self.error = error.localizedDescription } } }
                }
        }
    }

    private func deviceSelector(_ kind: DeviceKind, selection: Binding<String?>) -> some View {
        let device = store.registry.device(selection.wrappedValue, kind: kind)
        return VStack(alignment: .leading, spacing: 8) {
            Text(kind.title).font(.subheadline)
            Menu {
                Picker(kind.title, selection: selection) {
                    Text("None").tag(String?.none)
                    ForEach(store.devices.filter { $0.kind == kind }) { device in
                        Text("\(device.name) · \(device.address)").tag(String?.some(device.id))
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device?.name ?? "None")
                            .lineLimit(1).truncationMode(.middle)
                        if let device {
                            Text(device.address).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.body.weight(.semibold)).frame(width: 20)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(kind.title)
            .accessibilityValue(device.map { "\($0.name), \($0.address)" } ?? "None")
            .accessibilityIdentifier(kind == .appleTV ? "roomAppleMenu" : "roomSamsungMenu")
        }
    }
}

struct KeyboardScreen: View {
    @ObservedObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(store.name(.appleTV)) {
                    if store.toolsLoading { ProgressView("Checking text field…") }
                    else if store.keyboardReady {
                        TextField("Type text", text: $text, axis: .vertical).lineLimit(3...6).autocorrectionDisabled()
                        Button(busy ? "Sending…" : "Send text") {
                            guard let destinationID = store.appleID else { error = "Choose an Apple TV first."; return }
                            let value = text; text = ""; busy = true
                            Task { do { try await store.sendText(value, toDeviceID: destinationID) } catch { self.error = error.localizedDescription }; busy = false }
                        }.disabled(busy || text.isEmpty)
                    } else {
                        Text("Open a search or text field on this Apple TV, then check again.")
                        Button("Check again") { store.openKeyboard() }
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }.navigationTitle("Keyboard")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { text = ""; dismiss() } } }
        }.onDisappear { text = "" }
    }
}

