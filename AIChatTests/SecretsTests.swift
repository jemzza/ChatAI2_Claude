import Foundation
import Testing
@testable import AIChat

/// Ключи из `Secrets.generated.swift` (генерирует `scripts/gen_secrets.py`).
/// Проверяем только форму; значения сводятся к `Bool` до `#expect`,
/// чтобы при падении ключ не попал в лог.
struct SecretsTests {
    /// Bearer-токен владельца — JWT: три части через точку, начинается с `eyJ`.
    @Test func nebulaTokenLooksLikeJWT() {
        let token = Secrets.nebulaAPIToken
        let hasPrefix = token.hasPrefix("eyJ")
        let hasThreeParts = token.split(separator: ".").count == 3
        let hasNoWhitespace = token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        #expect(hasPrefix)
        #expect(hasThreeParts)
        #expect(hasNoWhitespace)
    }

    @Test func apphudKeyHasExpectedShape() {
        let key = Secrets.apphudAPIKey
        let hasPrefix = key.hasPrefix("app_")
        let isLongEnough = key.count >= 20
        let hasNoWhitespace = key.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        #expect(hasPrefix)
        #expect(isLongEnough)
        #expect(hasNoWhitespace)
    }
}
