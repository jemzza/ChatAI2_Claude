import XCTest

/// Общие шаги UI-тестов. Все запуски — с фейками (`-mockData`): без сети и Apphud.
@MainActor
extension XCUIApplication {
    static func launchMain(_ extra: [String] = [], premium: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mockData", "-skipOnboarding", premium ? "-mockPremium" : "-mockFree"] + extra
        app.launch()
        return app
    }

    /// Текст, начинающийся с `prefix` (многострочные заголовки).
    func text(startingWith prefix: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Новый чат: «Ask anything…» на главном.
    func openNewChat() {
        let ask = buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ask anything")).firstMatch
        XCTAssertTrue(ask.waitForExistence(timeout: 10))
        ask.tap()
    }

    /// Ввод в поле чата и отправка.
    func send(_ message: String) {
        let field = textFields["How can I help you?"].exists ? textFields["How can I help you?"]
            : textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(message)
        buttons["Send"].tap()
    }
}
