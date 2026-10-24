import SwiftUI

struct ManageTVScreen: View {
    @ObservedObject var store: RemoteStore
    let deviceID: String
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    @State private var macAddress: String
    @State private var error: String?
    @State private var showRemove = false
    @State private var scanDraft: ScanDraft?
    @FocusState private var editingField: Field?
    private enum Field: Hashable { case name, ip, mac }
    private struct ScanDraft: Identifiable {
        let id = UUID()
        let name: String
        let address: String
        let mac: String
        let kind: DeviceKind
    }

    init(store: RemoteStore, deviceID: String) {
        self.store = store; self.deviceID = deviceID
        let device = store.devices.first { $0.id == deviceID }
        _name = State(initialValue: device?.name ?? "")
        _address = State(initialValue: device?.address ?? "")
        _macAddress = State(initialValue: device?.wakeMACAddress ?? "")
    }

    var body: some View {
        Form {
            if let device = store.devices.first(where: { $0.id == deviceID }) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").font(.subheadline)
                        TextField("TV name", text: $name)
                            .textInputAutocapitalization(.words).autocorrectionDisabled()
                            .focused($editingField, equals: .name)
                            .accessibilityIdentifier("manageTVName")
                    }.padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IP address").font(.subheadline)
                        HStack {
                            TextField("TV’s local IP address", text: $address)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($editingField, equals: .ip)
                                .accessibilityIdentifier("manageTVIP")
                            if !address.isEmpty {
                                clearButton("Clear IP address", identifier: "clearManageTVIP") { address = "" }
                            }
                            scanButton("Scan TV IP address", identifier: "scanManageTVIP")
                        }
                    }.padding(.vertical, 4)
                    if device.kind == .samsung {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MAC address").font(.subheadline)
                            HStack {
                                TextField("TV MAC address", text: $macAddress)
                                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                    .focused($editingField, equals: .mac)
                                    .accessibilityIdentifier("samsungWakeMAC")
                                if !macAddress.isEmpty {
                                    clearButton("Clear MAC address", identifier: "clearManageTVMAC") { macAddress = "" }
                                }
                                scanButton("Scan TV MAC address", identifier: "scanSamsungWakeMAC")
                            }
                        }.padding(.vertical, 4)
                    }
                } header: {
                    Text("\(device.name) (\(device.kind == .appleTV ? "Apple TV" : "Samsung"))")
                        .textCase(nil).accessibilityIdentifier("manageTVHeading")
                }
                if device.kind == .samsung {
                    Section("Power on") {
                        Text("Use the wireless MAC for Wi-Fi or the wired MAC for Ethernet. Enable Power On with Mobile in the TV’s Network → Expert Settings.")
                            .font(.footnote)
                    }
                }
                Section {
                    Button("Re-pair") { Task { await store.rePair(device) } }
                    Button("Remove TV", role: .destructive) { showRemove = true }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("samsungWakeSaveError") }
                }
                Section {
                    Button("Save") {
                        editingField = nil
                        do {
                            let raw = macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                            let mac = device.kind == .samsung && !raw.isEmpty
                                ? try SamsungWakeOnLAN.normalizedMAC(raw) : nil
                            try store.updateTVNetwork(address: address, macAddress: mac, for: deviceID, name: name)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier(device.kind == .samsung ? "saveSamsungWakeMAC" : "saveTVNetwork")
                }
            } else { Text("This TV is no longer saved.") }
        }
        .navigationTitle("Manage TV")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove this TV?", isPresented: $showRemove, titleVisibility: .visible) {
            Button("Remove TV", role: .destructive) {
                if let device = store.devices.first(where: { $0.id == deviceID }) {
                    Task { await store.removeDevice(device); dismiss() }
                }
            }
        }
        .sheet(item: $scanDraft) { draft in
                TVPhotoScanScreen(destinationName: draft.name, initialAddress: draft.address,
                                  initialMACAddress: draft.mac) { result in
                    if let ip = result.ipAddresses.first { address = ip }
                    if draft.kind == .samsung, let mac = result.macAddresses.first { macAddress = mac.address }
                    error = nil
                }.id(draft.id)
        }
    }

    private func clearButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            error = nil
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary).frame(width: 44, height: 44)
        }.buttonStyle(.borderless).accessibilityLabel(title).accessibilityIdentifier(identifier)
    }

    private func scanButton(_ title: String, identifier: String) -> some View {
        Button {
            editingField = nil
            guard let device = store.devices.first(where: { $0.id == deviceID }) else { return }
            scanDraft = ScanDraft(name: device.name, address: address,
                                  mac: device.kind == .samsung ? macAddress : "", kind: device.kind)
        } label: {
            Image(systemName: "text.viewfinder").frame(width: 44, height: 44)
        }.buttonStyle(.borderless).accessibilityLabel(title).accessibilityIdentifier(identifier)
    }
}
