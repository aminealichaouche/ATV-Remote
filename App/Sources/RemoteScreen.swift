import SwiftUI

struct RemoteScreen: View {
    @ObservedObject var store: RemoteStore
    @AppStorage(RemoteLayout.storageKey) private var remoteLayout: RemoteLayout = RemoteLayout.defaultLayout
    @AppStorage(RemoteLayout.touchpadStorageKey) private var useTouchpad = false
    @ScaledMetric(relativeTo: .caption) private var toolFontSize: CGFloat = 14.4
    @ScaledMetric(relativeTo: .caption) private var toolButtonHeight: CGFloat = 52.8
    @State private var gestureDeviceID: String?
    @State private var gestureKind: DeviceKind?
    @State private var gestureStarted = false
    @State private var gestureCancelled = false
    @GestureState private var dragActive = false

    var body: some View {
        NavigationStack {
            ViewThatFits(in: .vertical) {
                remoteContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { remoteContent }
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ATV Remote")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $store.sheet) { sheet in
                switch sheet {
                case .settings: RemoteSettingsScreen(store: store)
                case .devices: DevicesScreen(store: store)
                case .rooms: RoomsScreen(store: store)
                case .pin(let id): ApplePINScreen(store: store, deviceID: id)
                case .trust(let id, let fingerprint): SamsungTrustScreen(store: store, deviceID: id, fingerprint: fingerprint)
                case .keyboard: KeyboardScreen(store: store)
                case .apps: AppsScreen(store: store)
                case .power: PowerScreen(store: store)
                case .transfer: TransferScreen(store: store)
                case .shortcuts: ShortcutsScreen(store: store)
                }
            }
            .alert("Remote", isPresented: Binding(get: { store.alertMessage != nil }, set: { if !$0 { store.alertMessage = nil } })) {
                Button("OK") { store.alertMessage = nil }
            } message: { Text(store.alertMessage ?? "") }
            .onChange(of: store.samsungID) { _, _ in if gestureStarted { gestureCancelled = true } }
            .onChange(of: store.appleID) { _, _ in if gestureStarted { gestureCancelled = true } }
            .onChange(of: store.navigationTarget) { _, _ in if gestureStarted { gestureCancelled = true } }
            .onChange(of: store.sheet?.id) { _, sheet in if sheet != nil, gestureStarted { gestureCancelled = true } }
            .onChange(of: dragActive) { _, active in if !active { gestureStarted = false; gestureCancelled = false; gestureDeviceID = nil; gestureKind = nil } }
        }
    }

    private var remoteContent: some View {
        VStack(spacing: 12) {
            roomPicker
            connectionIndicators
            if store.devices.isEmpty {
                HStack(spacing: 12) {
                    Text("No TVs added yet.").font(.footnote).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button { openSettings() } label: {
                        Text("Set up TVs").font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("setupTVs")
                }
            }
            navigationControls
            if remoteLayout == .standard { volumeControls }
            tools.padding(.top, 6)
            #if DEBUG
            if CommandLine.arguments.contains("--ui-testing-room-sessions") {
                Text("Session diagnostic").font(.caption2).accessibilityLabel(store.uiSessionLog).accessibilityIdentifier("roomSessionLog")
                Button("Lose living connection on next return") { store.loseLivingConnectionOnNextReturn() }
                    .accessibilityIdentifier("loseLivingOnReturn")
            }
            if CommandLine.arguments.contains("--ui-testing-retry") {
                Text(store.uiRetryCounts).accessibilityIdentifier("retryAttemptLog")
                Text(store.uiNavigationRequests).accessibilityIdentifier("navigationConnectLog")
            }
            if CommandLine.arguments.contains("--ui-testing-home") {
                Text(store.feedback).font(.caption).accessibilityIdentifier("homeActionLog")
            }
            if CommandLine.arguments.contains("--ui-testing-status-refresh") {
                Button("Simulate connection loss") { store.simulateObservedConnectionLoss() }
                    .accessibilityIdentifier("simulateStatusLoss")
            }
            #endif
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var roomPicker: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("Room", selection: Binding(get: { store.roomMenuSelection }, set: { store.selectRoomMenuItem($0) })) {
                    if AutoRoomPolicy.isAvailable {
                        Text("Auto").tag(RoomMenuSelection.automatic)
                    }
                    ForEach(store.rooms) { room in Text(room.name).tag(RoomMenuSelection.room(room.id)) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(store.roomMenuTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 12)
                    if store.autoRoomSearching {
                        ProgressView().controlSize(.mini).accessibilityLabel("Finding a room")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .layoutPriority(1)
            .accessibilityLabel("Room")
            .accessibilityValue(store.roomMenuTitle)
            .accessibilityIdentifier("roomMenu")
            Button { openSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 20)).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Remote settings")
            .accessibilityIdentifier("remoteSettings")
            Spacer(minLength: 0)
            Button {
                if gestureStarted { gestureCancelled = true }
                store.openShortcuts()
            } label: {
                Image(systemName: "square.stack.3d.up").font(.system(size: 23, weight: .regular))
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Shortcuts")
            .accessibilityIdentifier("remoteShortcuts")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openSettings() {
        if gestureStarted { gestureCancelled = true }
        store.sheet = .settings
    }

    private var navigationControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Picker("Navigate", selection: Binding(get: { store.navigationTarget }, set: { store.selectNavigationTarget($0) })) {
                    Text("Apple TV").tag(DeviceKind.appleTV)
                    Text("Samsung").tag(DeviceKind.samsung)
                }.pickerStyle(.segmented)
                Button {
                    if gestureStarted { gestureCancelled = true }
                    useTouchpad.toggle()
                } label: {
                    Image(systemName: useTouchpad ? "dpad" : "hand.draw").font(.system(size: 20))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(useTouchpad ? "Use directional buttons" : "Use touchpad")
                .accessibilityValue(useTouchpad ? "Touchpad" : "D-pad")
                .accessibilityIdentifier("remotePadModeToggle")
                if remoteLayout.usesAppleTVButtons {
                    Button { store.sheet = .power } label: {
                        Image(systemName: "power").font(.system(size: 20))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Power")
                    .accessibilityIdentifier("remotePower")
                }
            }
            navigationSurface
            Group {
                if remoteLayout.usesAppleTVButtons {
                    appleTVRemoteButtons
                } else {
                    HStack(spacing: 12) {
                        labeledAction("Back", icon: "chevron.left", action: .back)
                        homeButton(circular: false)
                        labeledAction("Play / pause", icon: "playpause", action: .playPause)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("remoteNavigationActions")
                }
            }
            .padding(.top, remoteLayout == .expandedAppleTVRemote ? 20 : 12)
        }
    }

    private var padSize: CGFloat { remoteLayout == .appleTVRemote ? 200 : 228 }

    private var navigationSurface: some View {
        padSurface(size: padSize)
    }

    @ViewBuilder private func padSurface(size: CGFloat) -> some View {
        let compact = remoteLayout == .appleTVRemote
        let directionSize: CGFloat = compact ? 52 : 60
        let selectSize: CGFloat = compact ? 64 : 72
        if useTouchpad {
            VStack {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.largeTitle).foregroundStyle(.tint)
            }
            .frame(width: compact ? size : nil, height: size)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: compact ? size / 2 : 28))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($dragActive) { _, active, _ in active = true }
                .onChanged { _ in
                    if !gestureStarted { gestureStarted = true; gestureCancelled = false; gestureDeviceID = store.selected(store.navigationTarget)?.id; gestureKind = store.navigationTarget }
                }
                .onEnded { value in
                    defer { gestureStarted = false; gestureCancelled = false; gestureDeviceID = nil; gestureKind = nil }
                    guard !gestureCancelled, gestureKind == store.navigationTarget, gestureDeviceID == store.selected(store.navigationTarget)?.id else { return }
                    let dx = value.translation.width, dy = value.translation.height
                    let action: RemoteAction = max(abs(dx), abs(dy)) < 20 ? .select : abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                    store.send(action)
                })
            .accessibilityElement(children: .ignore).accessibilityLabel("Navigation touchpad")
            .accessibilityIdentifier("remoteTouchpad")
            .accessibilityHint("Swipe to move. Tap to select.")
            .accessibilityAction(named: "Up") { store.send(.up) }
            .accessibilityAction(named: "Down") { store.send(.down) }
            .accessibilityAction(named: "Left") { store.send(.left) }
            .accessibilityAction(named: "Right") { store.send(.right) }
            .accessibilityAction(named: "Select") { store.send(.select) }
            .disabled(!store.state(store.navigationTarget).isConnected)
        } else {
            ZStack {
                Circle().fill(Color(.secondarySystemGroupedBackground))
                VStack(spacing: 8) {
                    remoteButton("Up", icon: "chevron.up", action: .up, size: directionSize)
                    HStack(spacing: 12) {
                        remoteButton("Left", icon: "chevron.left", action: .left, size: directionSize)
                        Button { store.send(.select) } label: {
                            Text("OK").font(.title3.weight(.semibold)).minimumScaleFactor(0.7)
                                .frame(width: selectSize, height: selectSize).contentShape(Circle())
                                .background(Color.accentColor.opacity(0.12), in: Circle())
                        }
                            .disabled(!store.state(store.navigationTarget).isConnected).accessibilityLabel("Select")
                        remoteButton("Right", icon: "chevron.right", action: .right, size: directionSize)
                    }
                    remoteButton("Down", icon: "chevron.down", action: .down, size: directionSize)
                }
            }.frame(width: size, height: size)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("remoteDirectionPad")
        }
    }

    private func remoteButton(_ name: String, icon: String, action: RemoteAction, size: CGFloat) -> some View {
        Button { store.send(action) } label: {
            Image(systemName: icon).font(.system(size: 22))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
            .disabled(!store.state(store.navigationTarget).isConnected).accessibilityLabel(name)
    }
    private func labeledAction(_ title: String, icon: String, action: RemoteAction) -> some View {
        Button { store.send(action) } label: {
            VStack(spacing: 8) { Image(systemName: icon).font(.title3); Text(title).font(.caption) }
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .disabled(!store.state(store.navigationTarget).isConnected)
        .accessibilityLabel(title)
        .accessibilityIdentifier(navigationActionID(action))
    }

    private var remoteActionSize: CGFloat { remoteLayout == .expandedAppleTVRemote ? 76 : 64 }
    private var remoteHorizontalGap: CGFloat { remoteLayout == .expandedAppleTVRemote ? 36 : 20 }
    private var remoteVerticalGap: CGFloat { remoteLayout == .expandedAppleTVRemote ? 24 : 16 }
    private var rockerHeight: CGFloat { remoteActionSize * 2 + remoteVerticalGap }

    private var appleTVRemoteButtons: some View {
        VStack(spacing: remoteVerticalGap) {
            HStack(spacing: remoteHorizontalGap) {
                circularAction("Back", symbol: "chevron.left", action: .back)
                homeButton(circular: true)
            }
            HStack(spacing: remoteHorizontalGap) {
                VStack(spacing: remoteVerticalGap) {
                    circularAction("Play / pause", symbol: "playpause", action: .playPause)
                    circularAction("Toggle mute", symbol: "speaker.slash", action: .mute, target: .samsung)
                }
                VStack(spacing: 0) {
                    rockerButton("Volume up", symbol: "plus", action: .volumeUp)
                    rockerButton("Volume down", symbol: "minus", action: .volumeDown)
                }
                .frame(width: remoteActionSize, height: rockerHeight)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("remoteVolumeRocker")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appleTVRemoteButtons")
    }

    private func circularAction(_ title: String, symbol: String, action: RemoteAction, target: DeviceKind? = nil) -> some View {
        Button { store.send(action, to: target) } label: {
            Image(systemName: symbol).font(.system(size: remoteLayout == .expandedAppleTVRemote ? 28 : 24))
                .frame(width: remoteActionSize, height: remoteActionSize)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
                .contentShape(Circle())
        }
        .disabled(!store.state(target ?? store.navigationTarget).isConnected)
        .accessibilityLabel(title)
        .accessibilityIdentifier(action == .mute ? "remoteMute" : navigationActionID(action))
    }

    @ViewBuilder private func homeButton(circular: Bool) -> some View {
        let button = RemoteHomeButton(binding: store.homeButtonBinding, kind: store.navigationTarget, circular: circular,
                                      size: remoteActionSize, iconSize: circular ? (remoteLayout == .expandedAppleTVRemote ? 28 : 24) : 22,
                                      onAction: { store.sendHomeGesture($1, binding: $0) })
        if circular { button.frame(width: remoteActionSize, height: remoteActionSize) }
        else { button.frame(maxWidth: .infinity, minHeight: 60) }
    }

    private func rockerButton(_ title: String, symbol: String, action: RemoteAction) -> some View {
        Button { store.send(action, to: .samsung) } label: {
            Image(systemName: symbol).font(.system(size: remoteLayout == .expandedAppleTVRemote ? 28 : 24))
                .frame(width: remoteActionSize, height: rockerHeight / 2)
                .contentShape(Rectangle())
        }
        .disabled(!store.state(.samsung).isConnected)
        .accessibilityLabel(title)
        .accessibilityIdentifier(action == .volumeUp ? "remoteVolumeUp" : "remoteVolumeDown")
    }

    private func navigationActionID(_ action: RemoteAction) -> String {
        switch action {
        case .back: "remoteBack"
        case .home: "remoteHome"
        case .playPause: "remotePlayPause"
        default: ""
        }
    }

    private var volumeControls: some View {
        VStack(spacing: 6) {
            HStack {
                Text("TV volume").font(.caption)
                Spacer()
            }
            HStack(spacing: 10) {
                volumeButton("Volume down", symbol: "minus", action: .volumeDown)
                volumeButton("Toggle mute", symbol: "speaker.slash", action: .mute)
                volumeButton("Volume up", symbol: "plus", action: .volumeUp)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("remoteVolumeControls")
    }
    private func volumeButton(_ title: String, symbol: String, action: RemoteAction) -> some View {
        Button { store.send(action, to: .samsung) } label: {
            Image(systemName: symbol).font(.system(size: 22))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!store.state(.samsung).isConnected)
        .accessibilityLabel(title)
        .accessibilityIdentifier(action == .volumeUp ? "remoteVolumeUp" : action == .volumeDown ? "remoteVolumeDown" : "remoteMute")
    }

    private var tools: some View {
        HStack(spacing: 8) {
            toolButton("Keyboard", icon: "keyboard", enabled: store.state(.appleTV).isConnected) { store.openKeyboard() }
            if store.navigationTarget == .appleTV {
                toolButton("Apps", icon: "square.grid.2x2", enabled: store.state(.appleTV).isConnected) { store.openApps() }
            } else {
                toolButton("Sources", icon: "rectangle.connected.to.line.below", enabled: store.state(.samsung).isConnected) { store.send(.source, to: .samsung) }
            }
            if remoteLayout == .standard {
                toolButton("Power", icon: "power", enlarged: false) { store.sheet = .power }
            }
        }.font(.caption).buttonStyle(.borderless).frame(minHeight: 44)
    }

    private func toolButton(_ title: String, icon: String, enabled: Bool = true, enlarged: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(enlarged ? .system(size: toolFontSize) : .caption)
                .frame(maxWidth: .infinity, minHeight: enlarged ? toolButtonHeight : 44)
                .contentShape(Rectangle())
        }.disabled(!enabled)
    }

    @ViewBuilder
    private var connectionIndicators: some View {
        if store.selected(.appleTV) != nil || store.selected(.samsung) != nil {
            HStack(alignment: .top, spacing: 16) {
                connectionIndicator(.appleTV)
                connectionIndicator(.samsung)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func connectionIndicator(_ kind: DeviceKind) -> some View {
        if let device = store.selected(kind) {
            let state = store.state(kind)
            Group {
                if state.isConnected {
                    connectionLabel(kind, device: device, state: state)
                } else {
                    Button {
                        guard store.selected(kind)?.id == device.id else { return }
                        let currentState = store.state(kind)
                        switch currentState {
                        case .connected: return
                        case .awaitingPin, .trustRequired: store.connectionAction(kind)
                        default: store.connect(kind)
                        }
                    } label: {
                        connectionLabel(kind, device: device, state: state)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(connectionHint(state))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(kind.title), \(device.name)")
            .accessibilityValue(state.title)
            .accessibilityIdentifier(kind == .appleTV ? "appleRemoteConnection" : "samsungRemoteConnection")
        }
    }

    private func connectionLabel(_ kind: DeviceKind, device: RemoteDevice, state: DeviceConnectionState) -> some View {
        HStack(spacing: 6) {
            Text(device.name)
                .font(.caption).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(.primary)
            Image(systemName: kind == .appleTV ? "appletv" : "tv")
                .font(.system(size: 16)).foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Circle()
                .fill(state.isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            if connectionPending(state) {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 16, height: 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier(kind == .appleTV ? "appleRemoteConnecting" : "samsungRemoteConnecting")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private func connectionPending(_ state: DeviceConnectionState) -> Bool {
        switch state {
        case .connecting, .awaitingApproval: true
        default: false
        }
    }

    private func connectionHint(_ state: DeviceConnectionState) -> String {
        switch state {
        case .awaitingPin: "Tap to enter the pairing code."
        case .trustRequired: "Tap to review this TV’s certificate."
        case .connecting, .awaitingApproval: "Tap to restart connecting."
        default: "Tap to reconnect."
        }
    }
}
