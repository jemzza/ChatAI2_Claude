import XCTest

/// Переходы между экранами и основные элементы экранов видео, истории и настроек.
@MainActor
final class NavigationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testFreeUserSeesProButtonThatOpensPaywall() {
        let app = XCUIApplication.launchMain(premium: false)
        let pro = app.buttons["PRO"]
        XCTAssertTrue(pro.waitForExistence(timeout: 10))
        pro.tap()
        XCTAssertTrue(app.buttons["Unlock now"].waitForExistence(timeout: 5))
    }

    func testPremiumUserHasNoProButton() {
        let app = XCUIApplication.launchMain()
        XCTAssertTrue(app.text(startingWith: "Your AI tools").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["PRO"].exists)
    }

    /// Шаблоны → категория → превью шаблона с форматом и качеством; «Create» без фото неактивна.
    func testTemplatesToPreview() {
        let app = XCUIApplication.launchMain()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Turn Photo")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        XCTAssertTrue(app.buttons["Popular"].waitForExistence(timeout: 5))
        app.buttons["Dance"].tap()
        let template = app.buttons["Dense Snowflakes"]
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Clay Fool"].exists)
        template.tap()

        XCTAssertTrue(app.staticTexts["Dense Snowflakes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Create"].isEnabled)
        let format = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Format")).firstMatch
        format.tap()
        let portrait = app.staticTexts["Portrait · Stories"]
        XCTAssertTrue(portrait.waitForExistence(timeout: 3))
        // Выбор пункта меняет значение строки (а не просто закрывает список).
        portrait.tap()
        XCTAssertTrue(portrait.waitForNonExistence(timeout: 3))
        XCTAssertTrue(format.label.contains("9:16"), format.label)
    }

    /// История: чаты по группам, переименование через свайп.
    func testHistoryRenameChat() {
        let app = XCUIApplication.launchMain()
        let history = app.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Recipe for pancakes")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Rename"].tap()

        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.clearAndType("Pancakes v2")
        app.alerts.buttons["Save"].tap()

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pancakes v2")).firstMatch
            .waitForExistence(timeout: 5))
    }

    func testSettingsUpgradeOpensPaywall() {
        let app = XCUIApplication.launchMain(premium: false)
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        XCTAssertTrue(app.staticTexts["Clear cache"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Upgrade plan")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Unlock now"].waitForExistence(timeout: 5))
    }
}

extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
