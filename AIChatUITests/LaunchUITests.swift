import XCTest

/// Дымовой тест: приложение запускается и показывает первый экран.
/// Сценарии экранов добавляются вместе с ними (раздел 7 плана).
@MainActor
final class LaunchUITests: XCTestCase {
    func testLaunchesWithMockData() {
        let app = XCUIApplication()
        app.launchArguments = ["-mockData"]
        app.launch()
        XCTAssertTrue(app.staticTexts["AI Chat"].waitForExistence(timeout: 10))
    }
}
