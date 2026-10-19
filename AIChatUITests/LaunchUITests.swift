import XCTest

/// Поток первого запуска: сплэш → онбординг → пейвол → главный экран.
/// Экраны пока — заглушки (5.3); сценарии экранов добавляются вместе с ними.
@MainActor
final class LaunchUITests: XCTestCase {
    func testFirstLaunchGoesThroughOnboardingAndPaywall() {
        let app = XCUIApplication()
        app.launchArguments = ["-mockData", "-mockFree", "-resetOnboarding"]
        app.launch()

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        continueButton.tap()

        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()

        XCTAssertTrue(app.staticTexts["Your AI tools, ready to go"].waitForExistence(timeout: 5))

        // Повторный запуск — сразу главный экран.
        app.terminate()
        app.launchArguments = ["-mockData", "-mockFree"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your AI tools, ready to go"].waitForExistence(timeout: 10))
    }
}
