enum RemoteLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case expandedAppleTVRemote
    // Preserve the legacy Stacked stored value for existing installations.
    case appleTVRemote = "stackedVolume"
    case standard

    static let defaultLayout: Self = .expandedAppleTVRemote
    static let storageKey = "RoomRemote.remoteLayout.v1"
    static let touchpadStorageKey = "RoomRemote.useTouchpad.v1"

    var id: String { rawValue }

    var usesAppleTVButtons: Bool { self != .standard }

    var title: String {
        switch self {
        case .standard: "Alternate"
        case .appleTVRemote: "Apple TV remote"
        case .expandedAppleTVRemote: "Expanded Apple TV remote"
        }
    }
}
