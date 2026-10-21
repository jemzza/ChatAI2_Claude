import XCTest

/// Сценарии чата из заметок к макету и CLAUDE.md («Поведение, которое нельзя сломать»).
@MainActor
final class ChatFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// С подпиской: «печатает», затем ответ; «Copy» показывает тост.
    func testPremiumUserGetsReplyAndCopies() {
        let app = XCUIApplication.launchMain(["-mockSlowReply"])
        app.openNewChat()
        app.send("Write a welcome email")

        XCTAssertTrue(app.otherElements["Generating a response"].waitForExistence(timeout: 3)
                      || app.staticTexts["Generating a response"].exists)
        XCTAssertTrue(app.text(startingWith: "Welcome to the team").waitForExistence(timeout: 10))

        app.buttons["Copy"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 3))
    }

    /// Без подписки «Send» открывает пейвол; после закрытия текст остаётся в поле.
    func testFreeUserSendOpensPaywallAndKeepsPrompt() {
        let app = XCUIApplication.launchMain(premium: false)
        app.openNewChat()
        app.send("Plan my trip")

        XCTAssertTrue(app.buttons["Unlock now"].waitForExistence(timeout: 5))
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()

        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3) || app.textFields.firstMatch.exists)
        let value = (app.textFields.firstMatch.value as? String) ?? (app.textViews.firstMatch.value as? String) ?? ""
        XCTAssertTrue(value.contains("Plan my trip"))
    }

    /// 429 — понятный текст и «Try again», без алертов на весь экран.
    func testRateLimitShowsErrorWithRetry() {
        let app = XCUIApplication.launchMain(["-mockError", "429"])
        app.openNewChat()
        app.send("Hi")

        XCTAssertTrue(app.text(startingWith: "Too many requests").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    /// Без сети сообщение ждёт и подписано.
    func testOfflineMessageIsQueued() {
        let app = XCUIApplication.launchMain(["-mockOffline"])
        app.openNewChat()
        app.send("Hello")

        XCTAssertTrue(app.staticTexts["Will send when online"].waitForExistence(timeout: 5))
    }
}
