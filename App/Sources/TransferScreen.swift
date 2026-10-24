import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct TransferExport: Identifiable {
    let id = UUID()
    let url: URL
    let roomCount: Int
    let code: String?
    let deviceCount: Int
    let starCount: Int
    let includesStars: Bool
    let remotePreferences: SharedRemotePreferences?
}

struct TransferScreen: View {
    @ObservedObject var store: RemoteStore
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var mode = 0
    @State private var selectedIDs: Set<String> = []
    @AppStorage("transferRequiresPhrase") private var requiresPhrase = false
    @AppStorage("transferIncludeRooms") private var includeRooms = true
    @State private var includeStars = true
    @State private var includeRemotePreferences = true
    @State private var importDeviceIDs: Set<String> = []
    @State private var importRoomIDs: Set<String> = []
    @State private var importStars = true
    @State private var importRemotePreferences = true
    @State private var export: TransferExport?
    @State private var showFilePicker = false
    @State private var file: Data?
    @State private var code = ""
    @State private var payload: RoomTransferPayload?
    @State private var busy = false
    @State private var error: String?
    @State private var success: String?
    @State private var request = UUID()
    @State private var operation: Task<Void, Never>?

    var body: some View {
        Group {
            if embedded { content }
            else { NavigationStack { content } }
        }
        .overlay {
            if phase != .active {
                Color(.systemGroupedBackground).ignoresSafeArea()
                    .overlay { Label("ATV Remote", systemImage: "lock") }
            }
        }
        .onAppear { selectedIDs = Set(store.devices.map(\.id)); consumeIncoming(); cleanStaleExports() }
        .onChange(of: store.incomingTransfer) { _, _ in consumeIncoming() }
        .onChange(of: phase) { _, phase in if phase == .background { cancelOperation() } }
        .onDisappear { reset() }
    }

    private var content: some View {
        Form {
            Picker("Transfer", selection: Binding(get: { mode }, set: { value in
                guard value != mode else { return }
                cancelOperation(); error = nil; success = nil; mode = value
            })) {
                Text("Share").tag(0)
                Text("Import").tag(1)
            }.pickerStyle(.segmented).disabled(busy).accessibilityIdentifier("transferMode")
            if mode == 0 { shareContent } else { importContent }
            if busy { ProgressView("Working…") }
            if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("transferError") } }
        }
        .listSectionSpacing(16)
        .contentMargins(.top, 12, for: .scrollContent)
        .navigationTitle("Transfer setup")
        .navigationBarTitleDisplayMode(.inline)
        // A text Back replaces the system back button so the top bar reads Back … Share/Import.
        // It returns to the screen that opened Transfer setup, or closes it when shown alone.
        .navigationBarBackButtonHidden(embedded)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { reset(); dismiss() }
                    .accessibilityIdentifier("transferBack")
            }
            ToolbarItem(placement: .confirmationAction) { primaryAction }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.roomRemoteSetup, .roomRemoteDirectSetup], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { read(url) } }
            catch { self.error = error.localizedDescription }
        }
    }

    /// The top-right button runs the next step, so nobody has to scroll to the bottom:
    /// Share creates the transfer and then opens the share sheet; Import chooses a file,
    /// unlocks a protected one, then imports the reviewed selection.
    @ViewBuilder private var primaryAction: some View {
        if mode == 0, let export {
            ShareLink(item: SetupShareFile(url: export.url, requiresPhrase: export.code != nil),
                      preview: SharePreview("ATV Remote setup")) { Text("Share") }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("transferPrimary")
        } else if mode == 0 || success == nil {
            Button(mode == 0 ? "Share" : "Import") { performPrimaryAction() }
                .buttonStyle(.glassProminent)
                .disabled(!primaryActionEnabled)
                .accessibilityIdentifier("transferPrimary")
        }
    }

    private var primaryActionEnabled: Bool {
        guard !busy else { return false }
        if mode == 0 { return !(selectedIDs.isEmpty && !includeRemotePreferences) }
        if payload != nil { return importSelection != nil }
        if file != nil { return !code.isEmpty }
        return true
    }

    /// The reviewed import, when the current selection would import something.
    private var importSelection: (payload: RoomTransferPayload, review: RoomTransferReview)? {
        guard let payload, let review = try? RoomTransferReview(payload: payload, existing: store.registry),
              (try? RoomTransferPlan(payload: selectedImport(payload, review: review), existing: store.registry)) != nil else { return nil }
        return (payload, review)
    }

    private func performPrimaryAction() {
        if mode == 0 { prepareExport(); return }
        if let selection = importSelection {
            do { try performImportSelection(selection.payload, review: selection.review) }
            catch { self.error = error.localizedDescription }
        } else if payload == nil {
            if file != nil { unlockSetup() } else { showFilePicker = true }
        }
    }

    @ViewBuilder private var shareContent: some View {
        if let export {
            Section {
                Text(countLabel(export.deviceCount, "TV"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("exportSummary")
                if export.roomCount > 0 { Text("\(countLabel(export.roomCount, "room assignment")) included").font(.subheadline).accessibilityIdentifier("exportRooms") }
                if export.includesStars { Text("\(countLabel(export.starCount, "starred app")) included").font(.subheadline) }
                if let preferences = export.remotePreferences {
                    Text("\(preferences.layout.title) · \(preferences.useTouchpad ? "Touchpad" : "D-pad")").font(.subheadline)
                }
                ShareLink(item: SetupShareFile(url: export.url, requiresPhrase: export.code != nil),
                          preview: SharePreview("ATV Remote setup")) {
                    Label("Share setup", systemImage: "square.and.arrow.up")
                }
                    .accessibilityIdentifier("shareSetupFile")
            } header: { Text("Ready to share") } footer: {
                if export.code == nil {
                    Text("Choose AirDrop or Save to Files in the share sheet. The other iPhone reviews this setup without a phrase.")
                } else { Text("Use the current ATV Remote on both iPhones.") }
            }
            if let phrase = export.code {
                Section {
                    Text(phrase).font(.title3.monospaced()).privacySensitive()
                        .accessibilityIdentifier("transferCode")
                    Button("Copy phrase", systemImage: "doc.on.doc") {
                        UIPasteboard.general.setItems([[UTType.plainText.identifier: phrase]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
                    }
                } header: { Text("Transfer phrase") } footer: {
                    Text("Give these four words separately to the receiving person.")
                }
            }
            Section { Button("Change selection") { reset() } }
        } else {
            Section("TVs") {
                if store.devices.isEmpty { Text("No saved TVs").foregroundStyle(.secondary) }
                ForEach(store.devices) { device in
                    selectionRow(device, selected: selectedIDs.contains(device.id)) {
                        if selectedIDs.contains(device.id) { selectedIDs.remove(device.id) }
                        else { selectedIDs.insert(device.id) }
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("shareTV." + device.id)
                }
            }
            Section {
                choiceRow("Room assignments", detail: "Match the selected TVs to their rooms", selected: includeRooms) {
                    includeRooms.toggle()
                }.disabled(busy).accessibilityIdentifier("shareRoomGroups")
                choiceRow("Starred apps", detail: "Include your stars and universal stars setting", selected: includeStars) {
                    includeStars.toggle()
                }.disabled(busy).accessibilityIdentifier("shareStarredApps")
                choiceRow("Remote layout & pad", selected: includeRemotePreferences) {
                    includeRemotePreferences.toggle()
                }.disabled(busy).accessibilityIdentifier("shareRemotePreferences")
            } header: { Text("Include") } footer: {
                Text("TVs pair separately on each iPhone. Existing configured rooms are kept.")
            }
            Section {
                Toggle("Require a transfer phrase", isOn: $requiresPhrase)
                    .disabled(busy).accessibilityIdentifier("requireTransferPhrase")
            } header: { Text("Protection") } footer: {
                Text(requiresPhrase ? "Share the four-word phrase separately from the file." : "AirDrop encrypts the connection. The setup file has no password; share it only with someone you trust.")
            }
            Section {
                Button("Create transfer", systemImage: "square.and.arrow.up") { prepareExport() }
                    .disabled(busy || (selectedIDs.isEmpty && !includeRemotePreferences))
                    .accessibilityIdentifier("prepareTransfer")
            }
        }
    }

    @ViewBuilder private var importContent: some View {
        if let success {
            Section {
                Label("Setup imported", systemImage: "checkmark.circle.fill").font(.headline)
                Text(success).accessibilityIdentifier("transferSuccess")
                Button("Import another file") { file = nil; payload = nil; code = ""; self.success = nil; error = nil }
            } footer: { Text("Choose a room or TV, then tap its gray connection indicator.") }
        } else if let payload {
            importReview(payload)
        } else {
            Section {
                Button(file == nil ? "Choose setup file" : "Choose another file", systemImage: "doc") { showFilePicker = true }
                    .disabled(busy).accessibilityIdentifier("chooseSetupFile")
                if file != nil {
                    SecureField("Four-word transfer phrase", text: $code)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .disabled(busy)
                        .accessibilityIdentifier("importTransferCode")
                    Button("Preview setup") { unlockSetup() }
                        .disabled(code.isEmpty || busy).accessibilityIdentifier("unlockSetup")
                }
            } footer: {
                Text("AirDrop setup opens directly for review. Protected files ask for the sender’s phrase.")
            }
        }
    }

    @ViewBuilder private func importReview(_ payload: RoomTransferPayload) -> some View {
        if let review = try? RoomTransferReview(payload: payload, existing: store.registry) {
            let preview = Result { try RoomTransferPlan(payload: selectedImport(payload, review: review), existing: store.registry) }
            let plan = try? preview.get()
            Section("You’ll receive") {
                if let plan {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(countLabel(plan.newDevices.count, "new TV"))")
                            .font(.headline).accessibilityIdentifier("importSummary")
                        Text("\(countLabel(plan.reusedDeviceCount, "TV")) already saved")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    if importDeviceIDs.intersection(review.selectableDeviceIDs).isEmpty && payload.remotePreferences == nil {
                        Text("Choose a TV or remote settings.").foregroundStyle(.secondary)
                    } else if case .failure(let issue) = preview {
                        Text(issue.localizedDescription).foregroundStyle(.red)
                    }
                }
            }
            if !review.devices.isEmpty {
                Section("TVs") {
                    ForEach(review.devices) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            selectionRow(item.device, selected: importDeviceIDs.contains(item.id) && item.conflict == nil) {
                                if importDeviceIDs.contains(item.id) { importDeviceIDs.remove(item.id) }
                                else { importDeviceIDs.insert(item.id) }
                            }
                            .disabled(busy || item.conflict != nil)
                            .accessibilityIdentifier("importTV." + item.id)
                            if let conflict = item.conflict {
                                Text(conflict).font(.caption).foregroundStyle(.orange)
                                if let existing = item.existing {
                                    Text("This iPhone: \(existing.name) · \(existing.address)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else if let existing = item.existing {
                                Text("Saved here as \(existing.name) · Access kept")
                                    .font(.caption).foregroundStyle(.secondary)
                                if existing.address != item.device.address {
                                    Text("Keep saved IP: \(existing.address)").font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text("New TV · Pair on this iPhone")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let mac = item.device.wakeMACAddress {
                                    Text("Power-on MAC: \(mac)").font(.caption).foregroundStyle(.secondary)
                                }
                                if store.devices.contains(where: { $0.id != item.id && $0.address == item.device.address }) {
                                    Text("Another saved TV uses this address. Check before importing.")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
            if !payload.rooms.isEmpty {
                Section {
                    ForEach(payload.rooms) { room in
                        let eligible = roomIsEligible(room, review: review)
                        VStack(alignment: .leading, spacing: 6) {
                            choiceRow(room.name, selected: eligible && importRoomIDs.contains(room.id)) {
                                if importRoomIDs.contains(room.id) { importRoomIDs.remove(room.id) }
                                else { importRoomIDs.insert(room.id) }
                            }.disabled(busy || !eligible).accessibilityIdentifier("importRoom." + room.id)
                            roomTV(room.samsungID, kind: .samsung, review: review)
                            roomTV(room.appleID, kind: .appleTV, review: review)
                            if !eligible {
                                Text("Select a TV in this room to include it.").font(.caption).foregroundStyle(.secondary)
                            } else if let result = plan?.roomResults.first(where: { $0.incomingID == room.id }) {
                                let saved = store.rooms.first { $0.id == result.room.id }
                                Text(result.isAdded ? "Add as \(result.room.name)" : saved == result.room ? "Already set up" : "Fill empty room \(result.room.name)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                } header: { Text("Room assignments") } footer: {
                    Text("Configured rooms are never replaced. Conflicting assignments are added as separate rooms.")
                }
            }
            if !payload.devices.isEmpty {
                Section {
                    Text("Each iPhone pairs with its TVs separately. Stars and TV details transfer; saved TV access stays on its original phone.")
                        .font(.subheadline).accessibilityIdentifier("independentApplePairing")
                }
            }
            if let stars = payload.starredApps, !stars.isEmpty || payload.universalStars != nil {
                Section {
                    choiceRow("Copy sender’s stars", detail: payload.universalStars == nil ? "Copy stars for the selected Apple TVs" : "Also use sender’s universal stars setting", selected: importStars) {
                        importStars.toggle()
                    }.disabled(busy).accessibilityIdentifier("importStarredApps")
                    if let universal = payload.universalStars, universal.enabled {
                        LabeledContent("Universal stars", value: "On · \(countLabel(universal.appIDs.count, "starred app"))")
                    } else {
                        if payload.universalStars != nil { LabeledContent("Universal stars", value: "Off") }
                        ForEach(review.devices.filter { stars[$0.id] != nil }) { item in
                            LabeledContent(item.device.name, value: countLabel(stars[item.id]?.count ?? 0, "starred app"))
                                .foregroundStyle(importDeviceIDs.contains(item.id) && item.conflict == nil && importStars ? Color.primary : Color.secondary)
                        }
                    }
                } header: { Text("Starred apps") }
                footer: { Text("Missing apps stay hidden. With universal stars on, copied stars apply to all your Apple TVs. Per-TV lists are copied only for selected TVs.") }
            }
            if let preferences = payload.remotePreferences {
                Section("Remote") {
                    choiceRow("Use sender’s remote layout & pad", selected: importRemotePreferences) {
                        importRemotePreferences.toggle()
                    }.disabled(busy).accessibilityIdentifier("importRemotePreferences")
                    Text("\(preferences.layout.title) · \(preferences.useTouchpad ? "Touchpad" : "D-pad")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Import setup", systemImage: "square.and.arrow.down") {
                    do { try performImportSelection(payload, review: review) }
                    catch { self.error = error.localizedDescription }
                }
                .disabled(busy || plan == nil).accessibilityIdentifier("confirmSetupImport")
                Button("Cancel", role: .cancel) { file = nil; self.payload = nil; code = ""; error = nil }.disabled(busy)
            } footer: {
                Text("Only selected room assignments are imported. No TV commands are sent.")
            }
        } else {
            Section {
                Text("This setup is no longer valid.").foregroundStyle(.red)
                Button("Choose another file") { self.payload = nil; file = nil; code = ""; showFilePicker = true }
            }
        }
    }

    private func countLabel(_ count: Int, _ singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    private func choiceRow(_ title: String, detail: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectionRow(_ device: RemoteDevice, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: device.kind == .appleTV ? "appletv" : "tv").frame(width: 24)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name).foregroundStyle(.primary)
                    Text("\(device.kind.title) · \(device.address)").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func roomTV(_ id: String?, kind: DeviceKind, review: RoomTransferReview) -> some View {
        let item = review.devices.first { $0.id == id }
        let included = item.map { importDeviceIDs.contains($0.id) && $0.conflict == nil } ?? false
        let name = included ? item?.existing?.name ?? item?.device.name ?? "None" : id == nil ? "None" : "Not included"
        return Label("\(kind.title) · \(name)", systemImage: kind == .appleTV ? "appletv" : "tv")
            .font(.subheadline).foregroundStyle(.secondary)
    }

    private func roomIsEligible(_ room: RoomProfile, review: RoomTransferReview) -> Bool {
        let chosen = importDeviceIDs.intersection(review.selectableDeviceIDs)
        return (room.samsungID == nil && room.appleID == nil) || room.samsungID.map(chosen.contains) == true || room.appleID.map(chosen.contains) == true
    }

    private func selectedImport(_ payload: RoomTransferPayload, review: RoomTransferReview) throws -> RoomTransferPayload {
        try payload.selecting(deviceIDs: importDeviceIDs.intersection(review.selectableDeviceIDs),
                              roomIDs: importRoomIDs.intersection(Set(payload.rooms.filter { roomIsEligible($0, review: review) }.map(\.id))), includePairings: false,
                              includeStars: importStars, includeRemotePreferences: importRemotePreferences)
    }

    private func performImportSelection(_ payload: RoomTransferPayload, review: RoomTransferReview) throws {
        performImport(try selectedImport(payload, review: review))
    }

    private func prepareExport() {
        cancelOperation()
        busy = true; error = nil; success = nil
        let token = UUID(); request = token
        let ids = selectedIDs, protected = requiresPhrase
        let stars = includeStars, preferences = includeRemotePreferences, rooms = includeRooms
        operation = Task { @MainActor in
            defer { if request == token { busy = false } }
            do {
                guard request == token, !Task.isCancelled else { return }
                let payload = try await store.transferPayload(selectedIDs: ids,
                                                              includeStars: stars, includeRemotePreferences: preferences, includeRooms: rooms)
                guard request == token, !Task.isCancelled else { return }
                let code = protected ? try RoomTransfer.makeCode() : nil
                let data = try await TransferCryptography.run {
                    if let code { return try RoomTransfer.encrypt(payload, code: code) }
                    return try RoomTransfer.directFile(payload)
                }
                #if DEBUG
                store.recordUITestExport(data)
                #endif
                guard request == token, !Task.isCancelled else { return }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RoomRemoteTransfers", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                let url = folder.appendingPathComponent(protected ? "ATV-Remote.roomremote" : "ATV-Remote.atvsetup")
                do { try data.write(to: url, options: [.atomic, .completeFileProtection]) }
                catch { try? FileManager.default.removeItem(at: folder); throw error }
                export = TransferExport(url: url, roomCount: payload.rooms.count, code: code,
                                        deviceCount: payload.devices.count,
                                        starCount: payload.sharedStarCount,
                                        includesStars: payload.starredApps != nil, remotePreferences: payload.remotePreferences)
            } catch { if request == token, !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    private func unlockSetup() {
        guard let file else { error = "Choose a setup file first."; return }
        let phrase = code
        cancelOperation()
        busy = true; error = nil; success = nil
        let token = UUID(); request = token
        operation = Task { @MainActor in
            defer { if request == token { busy = false } }
            do {
                let decoded = try await TransferCryptography.run { try RoomTransfer.decrypt(file, code: phrase).deviceSetupOnly() }
                guard request == token, !Task.isCancelled else { return }
                try preview(decoded)
            } catch { if request == token, !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    private func performImport(_ payload: RoomTransferPayload) {
        cancelOperation()
        busy = true; error = nil
        let token = UUID(); request = token
        operation = Task { @MainActor in
            defer { if request == token { busy = false } }
            do {
                let message = try await store.importTransfer(payload)
                guard request == token, !Task.isCancelled else { return }
                self.payload = nil; file = nil; code = ""; success = message
            } catch { if request == token, !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    private func read(_ url: URL) {
        cancelOperation()
        busy = true; error = nil
        let token = UUID(); request = token
        operation = Task { @MainActor in
            defer { if request == token { busy = false } }
            do {
                let data = try await Task.detached { try RoomTransfer.readFile(url) }.value
                guard request == token, !Task.isCancelled else { return }
                try receive(data)
            } catch { if request == token, !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    private func receive(_ data: Data) throws {
        file = nil; payload = nil; code = ""; success = nil; error = nil; mode = 1
        if let decoded = try RoomTransfer.directPayload(from: data) {
            try preview(decoded)
        } else { file = data }
    }

    private func preview(_ decoded: RoomTransferPayload) throws {
        let review = try RoomTransferReview(payload: decoded, existing: store.registry)
        importDeviceIDs = review.selectableDeviceIDs
        importRoomIDs = Set(decoded.rooms.map(\.id))
        importStars = true; importRemotePreferences = true
        payload = decoded; code = ""; error = nil
    }

    private func consumeIncoming() {
        guard let incoming = store.incomingTransfer else { return }
        reset()
        store.clearIncomingTransfer()
        do { try receive(incoming) }
        catch { mode = 1; self.error = error.localizedDescription }
    }

    private func cancelOperation() {
        request = UUID(); operation?.cancel(); operation = nil
        busy = false
    }

    private func reset() {
        cancelOperation()
        if let export { try? FileManager.default.removeItem(at: export.url.deletingLastPathComponent()) }
        export = nil; file = nil; payload = nil; importDeviceIDs = []; importRoomIDs = []; code = ""; error = nil; success = nil; busy = false
        showFilePicker = false
    }

    private func cleanStaleExports() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RoomRemoteTransfers", isDirectory: true)
        if export == nil { try? FileManager.default.removeItem(at: directory) }
    }
}

private enum TransferCryptography {
    static func run<Result: Sendable>(_ work: @escaping @Sendable () throws -> Result) async throws -> Result {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try work()
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

