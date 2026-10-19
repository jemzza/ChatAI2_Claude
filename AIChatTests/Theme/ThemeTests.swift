import SwiftUI
import Testing
import UIKit
@testable import AIChat

@MainActor
struct ThemeTests {
    /// Шрифты из `UIAppFonts` зарегистрированы в приложении-хосте тестов.
    @Test(arguments: ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"])
    func interIsRegistered(name: String) {
        #expect(UIFont(name: name, size: 16) != nil)
    }

    /// Цвета токенов есть в каталоге и совпадают с Figma.
    @Test(arguments: [("Background", "0B070E"), ("Surface", "1F191F"), ("TextSecondary", "606060"),
                      ("GradientStart", "98C6F7"), ("GradientEnd", "EB5B92")])
    func colorMatchesFigma(name: String, hex: String) throws {
        let color = try #require(UIColor(named: name))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let actual = String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()),
                            Int((blue * 255).rounded()))
        #expect(actual == hex)
    }
}
