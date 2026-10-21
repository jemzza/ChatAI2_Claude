import SwiftUI
import UIKit

/// Тактильный отклик. `.sensoryFeedback` — только с iOS 17, поэтому UIKit-генераторы.
@MainActor
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

extension View {
    /// Отклик, когда `value` меняется на значение, для которого `feedback` что-то вернул.
    func haptic<Value: Equatable>(on value: Value,
                                  _ feedback: @escaping @MainActor (Value) -> (@MainActor () -> Void)?) -> some View {
        onChange(of: value) { newValue in feedback(newValue)?() }
    }
}

extension ToastMessage {
    /// Успешный тост — успех, ошибочный — ошибка.
    @MainActor
    static func haptic(for toast: ToastMessage?) -> (@MainActor () -> Void)? {
        switch toast?.kind {
        case .success: Haptics.success
        case .failure: Haptics.error
        case nil: nil
        }
    }
}
