import SwiftUI
import UIKit

/// Native recognizer dependencies suppress the single press after a double tap
/// or hold. Pending recognition is canceled when its captured TV/session changes.
struct RemoteHomeButton: UIViewRepresentable {
    let binding: HomeButtonBinding?
    let kind: DeviceKind
    let circular: Bool
    let size: CGFloat
    let iconSize: CGFloat
    let onAction: (HomeButtonBinding, HomeButtonBinding.Gesture) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> HomeUIKitButton {
        let button = HomeUIKitButton(type: .custom)
        let coordinator = context.coordinator
        coordinator.button = button
        coordinator.install(on: button)
        button.activate = { [weak coordinator] in coordinator?.activate(.singleTap) ?? false }
        updateUIView(button, context: context)
        return button
    }

    func updateUIView(_ button: HomeUIKitButton, context: Context) {
        context.coordinator.update(self)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: kind == .samsung ? "house" : "tv",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: iconSize))
        if !circular {
            configuration.title = "Home"
            configuration.imagePlacement = .top
            configuration.imagePadding = 8
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = .preferredFont(forTextStyle: .caption1)
                return result
            }
        }
        configuration.background.backgroundColor = .secondarySystemGroupedBackground
        configuration.background.cornerRadius = circular ? size / 2 : 18
        button.configuration = configuration
        button.isEnabled = binding != nil
        button.isAccessibilityElement = true
        button.accessibilityLabel = "Home"
        button.accessibilityIdentifier = "remoteHome"
        button.accessibilityHint = binding?.kind == .appleTV
            ? "Tap for apps. Double tap for app switcher. Hold for Control Center."
            : "Go to Home."
        button.accessibilityCustomActions = binding?.kind == .appleTV ? [
            UIAccessibilityCustomAction(name: "App switcher", target: context.coordinator, selector: #selector(Coordinator.accessibleSwitcher)),
            UIAccessibilityCustomAction(name: "Control Center", target: context.coordinator, selector: #selector(Coordinator.accessibleControlCenter))
        ] : nil
    }

    static func dismantleUIView(_ button: HomeUIKitButton, coordinator: Coordinator) {
        coordinator.cancelPending()
        for recognizer in button.gestureRecognizers ?? [] { button.removeGestureRecognizer(recognizer) }
        button.activate = nil
        button.accessibilityCustomActions = nil
        coordinator.button = nil
    }

    @MainActor final class HomeUIKitButton: UIButton {
        var activate: (() -> Bool)?
        override func accessibilityActivate() -> Bool { activate?() ?? false }
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: RemoteHomeButton
        weak var button: HomeUIKitButton?
        private var captured: HomeButtonBinding?
        private var single: UITapGestureRecognizer!
        private var double: UITapGestureRecognizer!
        private var hold: UILongPressGestureRecognizer!

        init(_ parent: RemoteHomeButton) { self.parent = parent }

        func install(on button: HomeUIKitButton) {
            single = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
            double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
            double.numberOfTapsRequired = 2
            hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
            hold.minimumPressDuration = 0.5
            single.require(toFail: double)
            single.require(toFail: hold)
            double.require(toFail: hold)
            let recognizers: [UIGestureRecognizer] = [single, double, hold]
            for recognizer in recognizers {
                recognizer.delegate = self
                button.addGestureRecognizer(recognizer)
            }
        }

        func update(_ value: RemoteHomeButton) {
            if parent.binding != value.binding { cancelPending() }
            parent = value
            let apple = value.binding?.kind == .appleTV
            single.isEnabled = value.binding != nil
            double.isEnabled = apple
            hold.isEnabled = apple
        }

        func cancelPending() {
            captured = nil
            let recognizers: [UIGestureRecognizer?] = [single, double, hold]
            for recognizer in recognizers.compactMap({ $0 }) { recognizer.isEnabled = false }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if captured == nil { captured = parent.binding }
            return captured != nil
        }

        private func emit(_ gesture: HomeButtonBinding.Gesture) {
            guard let captured, captured == parent.binding else { self.captured = nil; return }
            self.captured = nil
            parent.onAction(captured, gesture)
        }

        func activate(_ gesture: HomeButtonBinding.Gesture) -> Bool {
            guard button?.isEnabled == true, let binding = parent.binding,
                  binding.action(for: gesture) != nil else { return false }
            captured = binding
            emit(gesture)
            return true
        }

        @objc private func singleTapped(_ recognizer: UITapGestureRecognizer) {
            if recognizer.state == .ended { emit(.singleTap) }
        }
        @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            if recognizer.state == .ended { emit(.doubleTap) }
        }
        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { emit(.hold) }
        }
        @objc func accessibleSwitcher() -> Bool { activate(.doubleTap) }
        @objc func accessibleControlCenter() -> Bool { activate(.hold) }
    }
}
