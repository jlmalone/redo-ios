import SwiftUI

/// Centralized haptic feedback manager
public class HapticManager {
    public static let shared = HapticManager()

    private init() {}

    // MARK: - Task Actions

    /// Haptic for task creation (success + light impact)
    public func taskCreated() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Haptic for task completion (success + medium impact)
    public func taskCompleted() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)

        // Add extra impact for satisfaction
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        }
    }

    /// Haptic for task deletion (warning)
    public func taskDeleted() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    /// Haptic for task archiving (light impact)
    public func taskArchived() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Haptic for task snoozed (light impact)
    public func taskSnoozed() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Haptic for task updated (light impact)
    public func taskUpdated() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - UI Interactions

    /// Haptic for button tap (light selection)
    public func buttonTapped() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Haptic for important button tap (medium impact)
    public func primaryButtonTapped() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Haptic for toggle/switch (selection)
    public func selectionChanged() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    // MARK: - Feedback States

    /// Haptic for error (error notification)
    public func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    /// Haptic for success (success notification)
    public func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Haptic for warning (warning notification)
    public func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    // MARK: - Special Effects

    /// Haptic for neon glow effect activation (soft impact)
    public func neonGlowActivated() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }

    /// Haptic for drag interaction
    public func dragStarted() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Haptic for drag ended
    public func dragEnded() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

// MARK: - SwiftUI View Extension

public extension View {
    /// Add haptic feedback to button tap
    func hapticFeedback(_ type: HapticType = .light) -> some View {
        self.simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    switch type {
                    case .light:
                        HapticManager.shared.buttonTapped()
                    case .medium:
                        HapticManager.shared.primaryButtonTapped()
                    case .selection:
                        HapticManager.shared.selectionChanged()
                    case .success:
                        HapticManager.shared.success()
                    case .warning:
                        HapticManager.shared.warning()
                    case .error:
                        HapticManager.shared.error()
                    }
                }
        )
    }
}

public enum HapticType {
    case light
    case medium
    case selection
    case success
    case warning
    case error
}
