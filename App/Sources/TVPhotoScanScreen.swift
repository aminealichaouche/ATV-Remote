import AVFoundation
import SwiftUI
import VisionKit

/// Live, on-device text recognition. The camera controller exists only while
/// scanning; review never keeps a paused camera preview alive.
@MainActor
struct TVPhotoScanScreen: View {
    let destinationName: String?
    let destinationAddress: String?
    let initialAddress: String
    let initialMACAddress: String
    let onApply: (TVPhotoScanResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var phase: ScanPhase = .permission
    @State private var visible = false
    @State private var started = false
    @State private var generation = UUID()
    @State private var permissionTask: Task<Void, Never>?
    @State private var ipCandidates: [String] = []
    @State private var macCandidates: [TVPhotoMACCandidate] = []
    @State private var modelName: String?
    @State private var modelIsAmbiguous = false
    @State private var ipAddress = ""
    @State private var macAddress = ""
    @State private var macInterface: TVPhotoMACInterface = .unspecified
    @State private var ipWasChosen = false
    @State private var macWasChosen = false

    init(destinationName: String? = nil, destinationAddress: String? = nil,
         initialAddress: String = "", initialMACAddress: String = "",
         onApply: @escaping (TVPhotoScanResult) -> Void) {
        self.destinationName = destinationName
        self.destinationAddress = destinationAddress
        self.initialAddress = destinationAddress ?? initialAddress
        self.initialMACAddress = initialMACAddress
        self.onApply = onApply
        _ipAddress = State(initialValue: self.initialAddress)
        _macAddress = State(initialValue: initialMACAddress)
        _ipWasChosen = State(initialValue: !self.initialAddress.isEmpty)
        _macWasChosen = State(initialValue: !initialMACAddress.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .permission:
                    ProgressView("Checking camera access…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .scanning:
                    scanningView
                case .review:
                    reviewView
                case .unavailable(let message, let settings):
                    unavailableView(message, settings: settings)
                }
            }
            .navigationTitle(destinationAddress == nil ? "Scan TV text" : "TV MAC address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { endSession(clear: true); dismiss() }
                }
            }
        }
        .onAppear {
            visible = true
            guard !started else { return }
            started = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-scan-manual") {
                phase = .unavailable("Enter the TV addresses manually.", false)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-scan-text") {
                ingest(TVPhotoTextParser.parse(lines: [
                    "IP address: 192.168.1.50",
                    "Wireless MAC address: 02:11:22:33:44:66",
                    "Wired MAC address: 02:11:22:33:44:88",
                    "Bluetooth MAC address: 04:11:22:33:44:99"
                ]))
                phase = .review
                return
            }
            #endif
            startCamera()
        }
        .onChange(of: scenePhase) { _, value in
            switch value {
            case .active:
                // The system permission alert may return its answer before
                // the app becomes active. Resume the authorized session then.
                if case .permission = phase, permissionTask == nil { startCamera() }
            case .inactive:
                // A camera permission prompt itself makes the app inactive.
                // There is no camera controller yet, so keep that request alive.
                if case .permission = phase { return }
                if case .scanning = phase { endSession(clear: false) }
            case .background:
                endSession(clear: false)
            @unknown default:
                endSession(clear: false)
            }
        }
        .onDisappear { visible = false; endSession(clear: true) }
    }

    private var scanningView: some View {
        VStack(spacing: 12) {
            Text(destinationAddress == nil
                 ? "Point at the TV’s Network Status or About This TV text."
                 : "Point at this TV’s Wi-Fi or Ethernet MAC address.")
                .font(.subheadline)
                .padding(.horizontal)
            let token = generation
            LiveTVTextScanner { result in
                guard visible, scenePhase == .active, generation == token,
                      case .scanning = phase else { return }
                ingest(result)
            } onUnavailable: { message in
                guard visible, generation == token, case .scanning = phase else { return }
                endSession(clear: false)
                phase = .unavailable(message, false)
            }
            .id(token)
            .accessibilityIdentifier("liveTVTextScanner")
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            HStack(spacing: 16) {
                if destinationAddress == nil { Label("\(ipCandidates.count) IP", systemImage: "network") }
                Label("\(macCandidates.count) MAC", systemImage: "tv")
            }
            .font(.subheadline)
            Button(destinationAddress == nil ? "Review addresses" : "Review MAC address", systemImage: "checkmark.viewfinder") {
                endSession(clear: false)
                phase = .review
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("scanTVReview")
            Button(destinationAddress == nil ? "Enter addresses manually" : "Enter MAC manually") {
                endSession(clear: false)
                phase = .review
            }
            .frame(minHeight: 44)
            Button("Clear and rescan", role: .destructive) {
                endSession(clear: true)
                startCamera()
            }
            .frame(minHeight: 44)
        }
        .padding(.vertical, 12)
    }

    private var reviewView: some View {
        Form {
            if let destinationName {
                Section(destinationName) {
                    if let destinationAddress {
                        LabeledContent("IP address", value: destinationAddress)
                            .accessibilityIdentifier("scanTVSavedIP")
                    }
                }
            }
            if destinationAddress == nil {
                Section("TV IP address") {
                    if ipCandidates.count > 1 {
                        Picker("Detected IP", selection: Binding(
                            get: { ipCandidates.contains(ipAddress) ? ipAddress : "" },
                            set: { ipAddress = $0; ipWasChosen = true }
                        )) {
                            Text("Choose an IP address").tag("")
                            ForEach(ipCandidates, id: \.self) { Text($0).tag($0) }
                        }
                        .accessibilityIdentifier("scanTVIPPicker")
                    }
                    TextField("IP address, e.g. 192.168.1.50", text: Binding(
                        get: { ipAddress },
                        set: { ipAddress = $0; ipWasChosen = true }
                    ))
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("scanTVIP")
                }
            }
            Section {
                if !macCandidates.isEmpty {
                    Picker("Detected connection", selection: Binding(
                        get: { macCandidates.first { $0.address == macAddress && $0.interface == macInterface }?.id ?? "" },
                        set: { id in
                            guard let candidate = macCandidates.first(where: { $0.id == id }) else {
                                macAddress = ""; macInterface = .unspecified; macWasChosen = true; return
                            }
                            macAddress = candidate.address
                            macInterface = candidate.interface
                            macWasChosen = true
                        }
                    )) {
                        Text("Choose Wi-Fi or Ethernet").tag("")
                        ForEach(macCandidates) { candidate in
                            Text("\(candidate.interface.title) · \(candidate.address)")
                                .tag(candidate.id)
                                .accessibilityIdentifier("scanTVMAC-\(candidate.interface.rawValue)-\(candidate.address)")
                        }
                    }
                    .accessibilityIdentifier("scanTVMACPicker")
                }
                TextField("TV MAC address", text: Binding(
                    get: { macAddress },
                    set: { value in
                        macAddress = value; macWasChosen = true
                        let matches = macCandidates.filter { $0.address == (try? SamsungWakeOnLAN.normalizedMAC(value)) }
                        macInterface = matches.count == 1 ? matches[0].interface : .unspecified
                    }
                ))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .accessibilityIdentifier("scanTVMAC")
            } header: {
                Text("TV MAC address")
            } footer: {
                Text("Use the Wi-Fi MAC for a wireless connection, or the Ethernet MAC for a wired connection.")
            }
            if let validationMessage {
                Section { Text(validationMessage).foregroundStyle(.red) }
                    .accessibilityIdentifier("scanTVError")
            }
            Section {
                Button(destinationAddress == nil ? "Use these addresses" : "Use MAC address") {
                    guard let result = reviewedResult else { return }
                    endSession(clear: true)
                    onApply(result)
                    dismiss()
                }
                .disabled(reviewedResult == nil)
                .accessibilityIdentifier("scanTVApply")
                Button("Scan again", systemImage: "text.viewfinder") {
                    endSession(clear: true)
                    startCamera()
                }
                .accessibilityIdentifier("scanTVResume")
            }
        }
    }

    private func unavailableView(_ message: String, settings: Bool) -> some View {
        ContentUnavailableView {
            Label("Camera text scan unavailable", systemImage: "text.viewfinder")
        } description: {
            Text(message)
        } actions: {
            if settings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button(destinationAddress == nil ? "Enter addresses manually" : "Enter MAC manually") { phase = .review }
            Button("Try again") { startCamera() }
        }
        .accessibilityIdentifier("scanTVUnavailable")
    }

    private var trimmedIP: String { ipAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedMAC: String { macAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var normalizedIP: String? {
        guard !trimmedIP.isEmpty, let value = try? SamsungProtocol.privateHost(trimmedIP), !value.contains(":") else { return nil }
        return value
    }
    private var normalizedMAC: String? { try? SamsungWakeOnLAN.normalizedMAC(trimmedMAC) }

    private var validationMessage: String? {
        if !trimmedIP.isEmpty, normalizedIP == nil { return "Enter a valid private IPv4 address from the TV’s Network Status screen." }
        if !trimmedMAC.isEmpty, normalizedMAC == nil { return "Enter a valid TV MAC address. Check any unclear characters on the TV." }
        if destinationAddress == nil, ipCandidates.count > 1, trimmedIP.isEmpty { return "Choose which detected IP address belongs to this TV." }
        if macCandidates.count > 1, trimmedMAC.isEmpty { return "Choose the Wi-Fi or Ethernet MAC for the TV’s active connection." }
        if let destinationAddress {
            if ipCandidates.contains(where: { $0 != destinationAddress }) {
                return "A different IP address was scanned. Scan again using \(destinationName ?? "the selected TV") (\(destinationAddress)) before applying a MAC address."
            }
        }
        return nil
    }

    private var reviewedResult: TVPhotoScanResult? {
        guard validationMessage == nil, normalizedIP != nil || normalizedMAC != nil else { return nil }
        if destinationAddress != nil, normalizedMAC == nil { return nil }
        return TVPhotoScanResult(
            ipAddresses: normalizedIP.map { [$0] } ?? [],
            macAddresses: normalizedMAC.map { [TVPhotoMACCandidate(address: $0, interface: macInterface)] } ?? [],
            modelName: modelName
        )
    }

    private func ingest(_ result: TVPhotoScanResult) {
        for ip in result.ipAddresses where !ipCandidates.contains(ip) && ipCandidates.count < 8 { ipCandidates.append(ip) }
        for candidate in result.macAddresses {
            if candidate.interface != .unspecified {
                macCandidates.removeAll { $0.address == candidate.address && $0.interface == .unspecified }
            } else if macCandidates.contains(where: { $0.address == candidate.address }) { continue }
            if !macCandidates.contains(candidate), macCandidates.count < 8 { macCandidates.append(candidate) }
        }
        if !ipWasChosen { ipAddress = ipCandidates.count == 1 ? ipCandidates[0] : "" }
        if !macWasChosen {
            macAddress = macCandidates.count == 1 ? macCandidates[0].address : ""
            macInterface = macCandidates.count == 1 ? macCandidates[0].interface : .unspecified
        }
        if !modelIsAmbiguous, let incoming = result.modelName {
            if let existing = modelName, existing != incoming { modelName = nil; modelIsAmbiguous = true }
            else { modelName = incoming }
        }
    }

    private func startCamera() {
        permissionTask?.cancel()
        generation = UUID()
        let token = generation
        guard visible, scenePhase == .active else { phase = .review; return }
        phase = .permission
        permissionTask = Task { @MainActor in
            guard !Task.isCancelled, visible, generation == token else { return }
            guard scenePhase == .active else { permissionTask = nil; return }
            guard DataScannerViewController.isSupported else {
                permissionTask = nil
                phase = .unavailable("Live text scanning is not supported on this iPhone. You can still enter the addresses manually.", false)
                return
            }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            let granted: Bool
            switch status {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
            case .denied, .restricted: granted = false
            @unknown default: granted = false
            }
            guard !Task.isCancelled, visible, generation == token else { return }
            permissionTask = nil
            guard granted else {
                let restricted = AVCaptureDevice.authorizationStatus(for: .video) == .restricted
                phase = .unavailable(restricted
                    ? "Camera access is restricted on this iPhone. You can enter the addresses manually."
                    : "Allow Camera access for ATV Remote in Settings to read TV text. You can also enter the addresses manually.", !restricted)
                return
            }
            guard scenePhase == .active else { return }
            guard DataScannerViewController.isAvailable else {
                phase = .unavailable("The camera cannot scan text right now. Close other camera apps and try again, or enter the addresses manually.", false)
                return
            }
            phase = .scanning
        }
    }

    private func endSession(clear: Bool) {
        permissionTask?.cancel()
        permissionTask = nil
        generation = UUID()
        phase = .review
        if clear {
            ipCandidates = []; macCandidates = []; modelName = nil; modelIsAmbiguous = false
            ipAddress = initialAddress; macAddress = initialMACAddress; macInterface = .unspecified
            ipWasChosen = !initialAddress.isEmpty; macWasChosen = !initialMACAddress.isEmpty
        }
    }

    private enum ScanPhase {
        case permission, scanning, review
        case unavailable(String, Bool)
    }
}

@MainActor
private struct LiveTVTextScanner: UIViewControllerRepresentable {
    let onResult: (TVPhotoScanResult) -> Void
    let onUnavailable: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult, onUnavailable: onUnavailable) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["en-US"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.start(scanner)
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onResult = onResult
        context.coordinator.onUnavailable = onUnavailable
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        coordinator.active = false
        coordinator.startTask?.cancel()
        controller.delegate = nil
        controller.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onResult: (TVPhotoScanResult) -> Void
        var onUnavailable: (String) -> Void
        var active = true
        var startTask: Task<Void, Never>?
        private var lastFrameTime: TimeInterval = 0

        init(onResult: @escaping (TVPhotoScanResult) -> Void, onUnavailable: @escaping (String) -> Void) {
            self.onResult = onResult
            self.onUnavailable = onUnavailable
        }

        func start(_ scanner: DataScannerViewController) {
            startTask = Task { @MainActor [weak self, weak scanner] in
                await Task.yield()
                guard !Task.isCancelled, let self, self.active, let scanner else { return }
                do { try scanner.startScanning() }
                catch { self.fail() }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) { read(allItems) }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) { read(allItems) }
        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) { read(allItems) }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) { fail() }

        private func fail() {
            guard active else { return }
            active = false
            onUnavailable("Live text scanning stopped. Try again, or enter the addresses manually.")
        }

        private func read(_ items: [RecognizedItem]) {
            guard active else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastFrameTime >= 0.12 else { return }
            lastFrameTime = now
            onResult(TVPhotoTextParser.parse(lines: Self.rows(items)))
        }

        /// Every parse uses a single complete current frame. Geometry joins a
        /// label and value from the same physical row, never from old frames.
        private static func rows(_ items: [RecognizedItem]) -> [String] {
            struct Piece {
                let text: String
                let minX: CGFloat
                let midY: CGFloat
                let height: CGFloat
            }
            var pieces: [Piece] = []
            var bytes = 0
            for item in items.prefix(200) {
                guard case .text(let text) = item else { continue }
                let points = [text.bounds.topLeft, text.bounds.topRight, text.bounds.bottomLeft, text.bounds.bottomRight]
                guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { continue }
                let minX = points.map(\.x).min() ?? 0
                let minY = points.map(\.y).min() ?? 0
                let maxY = points.map(\.y).max() ?? 0
                let transcript = text.transcript
                guard transcript.utf8.prefix(20_001).count <= 20_000 else { continue }
                let lines = transcript.components(separatedBy: .newlines)
                guard lines.count <= 200 else { continue }
                let height = max(1, maxY - minY) / CGFloat(max(1, lines.count))
                for (index, value) in lines.enumerated() {
                    let row = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !row.isEmpty, row.count <= 400 else { continue }
                    let count = row.utf8.count
                    guard bytes + count <= 20_000, pieces.count < 200 else { break }
                    bytes += count
                    pieces.append(Piece(text: row, minX: minX, midY: minY + (CGFloat(index) + 0.5) * height, height: height))
                }
            }
            pieces.sort { $0.midY == $1.midY ? $0.minX < $1.minX : $0.midY < $1.midY }
            var rows: [[Piece]] = []
            for piece in pieces {
                if let last = rows.last, let anchor = last.first,
                   abs(piece.midY - anchor.midY) <= min(piece.height, anchor.height) * 0.45 {
                    rows[rows.count - 1].append(piece)
                } else { rows.append([piece]) }
            }
            return rows.map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ") }
        }
    }
}
