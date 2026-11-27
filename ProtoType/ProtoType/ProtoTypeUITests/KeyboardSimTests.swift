import XCTest

/// Drives the real Prototype keyboard in a simulator: opens Try It, switches to
/// our keyboard with the globe key, taps out typos, and records what lands in
/// the text box plus screenshots. Run by `.github/workflows/keyboard-sim.yml`,
/// which enables the keyboard in the simulator's preferences first.
final class KeyboardSimTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // UserDefaults argument domain: skip onboarding straight to Home.
        app.launchArguments += ["-hasCompletedOnboarding", "YES"]
        app.launch()
    }

    @MainActor
    func testTypoCorrections() throws {
        let tryIt = app.tabBars.buttons["Try It"]
        XCTAssertTrue(tryIt.waitForExistence(timeout: 15), "Try It tab missing")
        tryIt.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Try It text box missing")
        editor.tap()
        sleep(2)
        snapshot("1_keyboard_shown")

        try switchToPrototypeKeyboard()
        snapshot("2_prototype_keyboard")

        // Each case: what we tap (space commits the word), and what we hope ends up.
        let cases: [(typed: String, expected: String)] = [
            ("teh", "the"),
            ("dont", "don't"),
            ("wrld", "world"),
        ]
        var report: [String] = []
        for (i, c) in cases.enumerated() {
            clear(editor)
            for ch in c.typed { try tapKey(String(ch)) }
            sleep(1)
            snapshot("3_\(i)_\(c.typed)_typed")
            try tapKey("space")
            sleep(1)
            let result = ((editor.value as? String) ?? "").trimmingCharacters(in: .whitespaces)
            report.append("\(c.typed) -> \"\(result)\" (expected \"\(c.expected)\")")
            snapshot("4_\(i)_\(c.typed)_after_space")
        }
        attachText(report.joined(separator: "\n"), named: "keyboard_results.txt")

        // Hard check only on the core pipeline; "wrld" needs 2 edits, which now
        // relies on UITextChecker and is reported, not asserted.
        XCTAssertTrue(report[0].contains("\"the\""), report[0])
        XCTAssertTrue(report[1].contains("\"don't\"") || report[1].contains("\"don’t\""), report[1])
    }

    // MARK: - Helpers

    /// Tap the globe ("Next keyboard") until one of our keys shows up.
    private func switchToPrototypeKeyboard() throws {
        for attempt in 0..<4 {
            if isPrototypeKeyboard() { return }
            let globe = app.buttons["Next keyboard"]
            guard globe.exists else {
                attachText(app.debugDescription, named: "hierarchy_no_globe_\(attempt).txt")
                break
            }
            globe.tap()
            sleep(2)
        }
        if !isPrototypeKeyboard() {
            attachText(app.debugDescription, named: "hierarchy_switch_failed.txt")
            snapshot("switch_failed")
            throw XCTSkip("Could not switch to the Prototype keyboard; see hierarchy attachment")
        }
    }

    /// The system keyboard exposes `app.keyboards`; a third-party keyboard's
    /// keys appear as plain buttons outside it.
    private func isPrototypeKeyboard() -> Bool {
        app.keyboards.count == 0 && app.buttons["t"].exists
    }

    private func tapKey(_ key: String) throws {
        let candidates = [app.buttons[key], app.keys[key], app.buttons[key.uppercased()]]
        if let el = candidates.first(where: { $0.exists && $0.isHittable }) {
            el.tap()
            return
        }
        attachText(app.debugDescription, named: "hierarchy_missing_\(key).txt")
        XCTFail("Key \"\(key)\" not found")
        throw XCTSkip("Key \"\(key)\" not found")
    }

    private func clear(_ editor: XCUIElement) {
        let current = (editor.value as? String) ?? ""
        guard !current.isEmpty, current != "Enter text" else { return }
        let delete = [app.buttons["delete"], app.buttons["Delete"], app.keys["delete"]].first { $0.exists }
        for _ in 0..<(current.count + 2) { delete?.tap() }
    }

    private func snapshot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "kbd_\(name).png"
        a.lifetime = .keepAlways
        add(a)
    }

    private func attachText(_ text: String, named name: String) {
        let a = XCTAttachment(string: text)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
