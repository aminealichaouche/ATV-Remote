import SwiftUI

struct PowerScreen: View {
    @ObservedObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var wakeRequestID: UUID?
    @State private var wakeSetupDeviceID: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        powerButton("On", systemImage: "power", identifier: "wakeAppleTV",
                                    enabled: store.state(.appleTV).isConnected && store.samsungWakeDeviceID == nil) {
                            store.send(.wake, to: .appleTV)
                            dismiss()
                        }
                        .accessibilityLabel("Turn on Apple TV")
                        powerButton("Off", systemImage: "moon", identifier: "sleepAppleTV",
                                    enabled: store.state(.appleTV).isConnected && store.samsungWakeDeviceID == nil) {
                            store.send(.sleep, to: .appleTV)
                            dismiss()
                        }
                        .accessibilityLabel("Turn off Apple TV")
                    }
                } header: {
                    deviceHeader(store.name(.appleTV), systemImage: "appletv")
                }
                Section {
                    if let device = store.selected(.samsung) {
                        HStack(spacing: 12) {
                            powerButton("On", systemImage: "power", identifier: "wakeSamsung",
                                        enabled: store.samsungWakeDeviceID == nil,
                                        isBusy: store.samsungWakeDeviceID == device.id) {
                                // Navigation can retain a rendered row while its
                                // editor saves. Read the current profile on tap.
                                guard let current = store.selected(.samsung), current.id == device.id else { return }
                                if current.wakeMACAddress == nil {
                                    wakeSetupDeviceID = current.id
                                } else if let request = store.wakeSamsung(expectedDeviceID: device.id) {
                                    wakeRequestID = request
                                }
                            }
                            .accessibilityLabel("Turn on Samsung TV")
                            .accessibilityHint(device.wakeMACAddress == nil ? "Set up this TV’s MAC address first." : "Send a network wake request.")
                            powerButton("Off", systemImage: "power", identifier: "powerOffSamsung",
                                        enabled: store.state(.samsung).isConnected && store.samsungWakeDeviceID == nil) {
                                store.send(.powerToggle, to: .samsung)
                                dismiss()
                            }
                            .accessibilityLabel("Turn off Samsung TV")
                            .accessibilityHint("Sends the power button once to the connected TV.")
                        }
                        if let error = store.samsungWakeError { Text(error).foregroundStyle(.red).accessibilityIdentifier("samsungWakeError") }
                        #if DEBUG
                        if let target = store.uiWakeTargetDescription {
                            Text(target).font(.caption).accessibilityIdentifier("wakeTargetDebug")
                        }
                        #endif
                    } else {
                        Text("Select a Samsung TV in Settings.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack(spacing: 8) {
                        deviceHeader(store.name(.samsung), systemImage: "tv")
                        Spacer(minLength: 8)
                        if let device = store.selected(.samsung) {
                            Button {
                                wakeSetupDeviceID = device.id
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.body)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless)
                            .disabled(store.samsungWakeDeviceID != nil)
                            .accessibilityLabel("Manage Samsung TV")
                            .accessibilityIdentifier("samsungWakeSetup")
                        }
                    }
                    .textCase(nil)
                }
            }.navigationTitle("Power")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(item: $wakeSetupDeviceID) { deviceID in
                    ManageTVScreen(store: store, deviceID: deviceID)
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .overlay(alignment: .bottom) {
                    if let message = store.samsungWakeMessage {
                        Text(message)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .padding(16)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("samsungWakeMessage")
                    }
                }
        }
        .onDisappear {
            if let wakeRequestID { store.cancelSamsungWake(request: wakeRequestID) }
        }
    }

    private func deviceHeader(_ name: String, systemImage: String) -> some View {
        Label(name, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .textCase(nil)
    }

    private func powerButton(_ title: String, systemImage: String, identifier: String,
                             enabled: Bool, isBusy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: systemImage).opacity(isBusy ? 0 : 1)
                    if isBusy { ProgressView() }
                }
                .frame(width: 22, height: 22)
                Text(title)
            }
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }
}
