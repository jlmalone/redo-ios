import SwiftUI

/// Toast notification view with Matrix theme
public struct ToastView: View {
    let message: String
    let type: ToastType
    @Binding var isShowing: Bool

    public init(message: String, type: ToastType = .info, isShowing: Binding<Bool>) {
        self.message = message
        self.type = type
        self._isShowing = isShowing
    }

    public var body: some View {
        VStack {
            Spacer()

            if isShowing {
                HStack(spacing: .matrixSpacingMedium) {
                    // Icon
                    Image(systemName: type.icon)
                        .foregroundColor(type.color)
                        .font(.title3)

                    // Message
                    Text(message)
                        .font(.matrixBody)
                        .foregroundColor(.matrixTextPrimary)
                        .lineLimit(3)

                    Spacer()

                    // Dismiss button
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            isShowing = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.matrixTextSecondary)
                    }
                }
                .padding()
                .background(Color.matrixBackgroundSecondary)
                .cornerRadius(.matrixCornerRadius)
                .matrixBorder(color: type.color)
                .shadow(color: type.color.opacity(0.3), radius: 10)
                .padding(.horizontal)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    // Auto-dismiss after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.spring(response: 0.3)) {
                            isShowing = false
                        }
                    }

                    // Haptic feedback
                    switch type {
                    case .success:
                        HapticManager.shared.success()
                    case .error:
                        HapticManager.shared.error()
                    case .warning:
                        HapticManager.shared.warning()
                    case .info:
                        HapticManager.shared.buttonTapped()
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isShowing)
    }
}

public enum ToastType {
    case success
    case error
    case warning
    case info

    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success:
            return .matrixSuccess
        case .error:
            return .matrixError
        case .warning:
            return .matrixAmber
        case .info:
            return .matrixCyan
        }
    }
}

// MARK: - View Extension

public extension View {
    func toast(message: String, type: ToastType = .info, isShowing: Binding<Bool>) -> some View {
        ZStack {
            self

            ToastView(message: message, type: type, isShowing: isShowing)
        }
    }
}

// MARK: - Toast Manager

@MainActor
public class ToastManager: ObservableObject {
    @Published public var message: String = ""
    @Published public var type: ToastType = .info
    @Published public var isShowing: Bool = false

    public static let shared = ToastManager()

    private init() {}

    public func show(_ message: String, type: ToastType = .info) {
        self.message = message
        self.type = type
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            isShowing = true
        }
    }

    public func hide() {
        withAnimation(.spring(response: 0.3)) {
            isShowing = false
        }
    }
}
