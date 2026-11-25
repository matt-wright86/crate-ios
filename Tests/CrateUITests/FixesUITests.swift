// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest

/// What the fixes changed that shows in the UI.
final class FixesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// The code region stops at what a VM's CPUs can use, and a running VM
    /// keeps the screen on unless Settings says otherwise.
    func testSettingsOffersCodeRegionsUpTo512MBAndTheScreenSwitch() {
        let app = launch("--tab=settings")
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Code region'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20), "no Code region picker")
        picker.tap()
        for size in ["128 MB", "256 MB", "384 MB", "512 MB"] {
            XCTAssertTrue(app.buttons[size].waitForExistence(timeout: 5), "\(size) isn't offered")
        }
        for size in ["768 MB", "1024 MB"] {
            XCTAssertFalse(app.buttons[size].exists, "\(size) is still offered")
        }
        app.buttons["512 MB"].tap()

        let keepOn = app.switches.matching(NSPredicate(format: "label CONTAINS 'Keep the screen on'")).firstMatch
        for _ in 0..<6 where !keepOn.exists || !keepOn.isHittable { app.swipeUp() }
        XCTAssertTrue(keepOn.exists, "no Keep the screen on switch")
        XCTAssertEqual(keepOn.value as? String, "1", "Keep the screen on isn't on to begin with")
    }

    /// --samples shows its VMs without saving them over the real list
    /// (MachineStoreTests), so it's safe to launch with.
    func testTheSampleVMsShow() {
        let app = launch("--tab=home", "--samples", "--jit=on")
        XCTAssertTrue(app.staticTexts["Debian"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Arch Linux"].exists)
    }

    /// A whole install, through the UI: the account sheet refuses a system
    /// account's name, then Arch Linux with Xfce downloads (1.6 GB) and
    /// installs. Only when asked for:
    ///
    ///     TEST_RUNNER_CRATE_TEST_INSTALL=1 ./Scripts/test.sh "iPhone 17" \
    ///         -only-testing:CrateUITests/FixesUITests/testInstallingAVM
    func testInstallingAVM() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CRATE_TEST_INSTALL"] == "1",
                          "downloads 1.6 GB: set TEST_RUNNER_CRATE_TEST_INSTALL=1 to run it")
        let app = launch("--tab=install")
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Arch Linux' AND label CONTAINS 'Xfce'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 60), "the catalog has no Arch Linux Xfce row")
        row.tap()
        let begin = app.buttons["Install Arch Linux"]
        XCTAssertTrue(begin.waitForExistence(timeout: 10), "no Install Arch Linux button")
        begin.tap()

        let user = app.textFields["User Name"]
        XCTAssertTrue(user.waitForExistence(timeout: 10), "no account sheet")
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("hunter2")
        let install = app.navigationBars.buttons["Install"]
        user.tap()
        user.typeText("gdm")
        XCTAssertFalse(install.isEnabled, "gdm, the display manager's account, is accepted")
        user.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        user.typeText("matt")
        XCTAssertTrue(install.isEnabled, "matt isn't accepted")
        install.tap()

        let started = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Downloading Arch Linux'")).firstMatch
        XCTAssertTrue(started.waitForExistence(timeout: 60), "the install didn't start")
        XCTAssertTrue(app.staticTexts["Arch Linux is installed"].waitForExistence(timeout: 40 * 60),
                      "the install didn't finish in 40 minutes")
    }
}
