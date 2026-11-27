import XCTest

/// Simulator checks for the account screens. Real Sign in with Apple and iCloud
/// sync need a signed build and an Apple ID, so those are left to TestFlight.
/// State is seeded through UserDefaults launch arguments (no test hooks in the app).
final class AccountFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingCanSkipAccount() {
        let app = launch(["-hasCompletedOnboarding", "NO"])

        app.buttons["Get Started"].tap()
        XCTAssertTrue(appleButton(in: app).waitForExistence(timeout: 5), "Sign in with Apple button missing")
        XCTAssertTrue(app.buttons["Continue without an account"].exists)
        XCTAssertFalse(app.buttons["Sign up with Email"].exists, "Fake email sign-up should be gone")
        snapshot(app, "1-onboarding-account")

        app.buttons["Continue without an account"].tap()
        XCTAssertTrue(app.staticTexts["Your languages"].waitForExistence(timeout: 5))
        snapshot(app, "2-onboarding-after-skip")
    }

    @MainActor
    func testSettingsShowsSignInWhenSignedOut() {
        let app = launch(["-hasCompletedOnboarding", "YES"])

        let button = appleButton(in: app)
        scrollTo(button, in: app)
        XCTAssertTrue(button.exists, "Account section should offer Sign in with Apple")
        snapshot(app, "3-settings-signed-out")
    }

    @MainActor
    func testDeleteAccountAsksForConfirmation() {
        let app = launch(["-hasCompletedOnboarding", "YES", "-appleUserID", "uitest-user"])

        let delete = app.buttons["Delete Account"]
        scrollTo(delete, in: app)
        XCTAssertTrue(app.buttons["Sign Out"].exists)
        snapshot(app, "4-settings-signed-in")

        delete.tap()
        let alert = app.alerts["Delete your account?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        snapshot(app, "5-delete-confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Cancel should keep the account")
    }

    @MainActor
    func testPaywallShowsTermsAndPrivacy() {
        let app = launch(["-hasCompletedOnboarding", "YES"])

        // The upgrade row sits below the Account section, so scroll to it first.
        let upgrade = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Upgrade to Premium'")).firstMatch
        scrollTo(upgrade, in: app)
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5))
        upgrade.tap()

        let terms = app.links["Terms of Use"].exists ? app.links["Terms of Use"] : app.buttons["Terms of Use"]
        XCTAssertTrue(terms.waitForExistence(timeout: 5), "Paywall needs a Terms of Use link")
        XCTAssertTrue(app.buttons["Privacy Policy"].exists)
        snapshot(app, "6-paywall-legal-links")
    }

    // MARK: - Helpers

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func appleButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Apple'")).firstMatch
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 6 {
            app.swipeUp()
            tries += 1
        }
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
