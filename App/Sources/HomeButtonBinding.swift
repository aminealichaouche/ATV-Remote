/// A delayed tap must still belong to the TV, navigation target and connection
/// that received the first touch. This is transient, never saved or shared.
struct HomeButtonBinding: Equatable, Sendable {
    enum Gesture: Sendable { case singleTap, doubleTap, hold }
    let kind: DeviceKind
    let deviceID: String
    let epoch: UInt64

    func action(for gesture: Gesture) -> RemoteAction? {
        switch gesture {
        case .singleTap: .home
        case .doubleTap: kind == .appleTV ? .appSwitcher : nil
        case .hold: kind == .appleTV ? .controlCenter : nil
        }
    }
}
