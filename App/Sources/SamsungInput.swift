import Foundation

/// A Samsung input reached through the TV's own source menu. Tested Tizen models ignore
/// direct HDMI keys but accept Source, arrows and Enter. Their menu keeps a fixed order
/// (SmartThings, Connected Devices, TV, HDMI 1…4, USB, Mobile), opens on the current
/// input, and Left stops at the first entry.
enum SamsungInput: Int, CaseIterable, Identifiable, Sendable {
    case tv, hdmi1, hdmi2, hdmi3, hdmi4

    var id: Int { rawValue }
    var title: String { self == .tv ? "TV" : "HDMI \(rawValue)" }

    /// Entries in the TV's source menu, so this many Lefts less one always reach the first.
    static let sourceMenuLength = 9
    /// TV's place in that menu, after SmartThings and Connected Devices.
    static let tvMenuIndex = 2

    enum Step: Equatable, Sendable {
        case key(RemoteAction)
        case pause(Duration)
    }

    /// Kept short so switching feels quick: the menu needs a moment to open, then
    /// key presses only need enough spacing for the TV not to drop any.
    static let menuOpenDelay: Duration = .milliseconds(800)
    static let leftSpacing: Duration = .milliseconds(100)
    static let rightSpacing: Duration = .milliseconds(150)

    /// Source, Left back to the first entry, Right to this input, then Enter.
    var steps: [Step] {
        var steps: [Step] = [.key(.source), .pause(Self.menuOpenDelay)]
        for _ in 1..<Self.sourceMenuLength { steps += [.key(.left), .pause(Self.leftSpacing)] }
        for _ in 0..<(Self.tvMenuIndex + rawValue) { steps += [.key(.right), .pause(Self.rightSpacing)] }
        steps.append(.key(.select))
        return steps
    }

    var keys: [RemoteAction] {
        steps.compactMap { if case .key(let action) = $0 { action } else { nil } }
    }
}
