// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest

/// crate opens on each of its tabs. Launched without `--empty` or `--samples`:
/// both replace the list of VMs.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    func testHome() {
        let app = launch("--tab=home")
        XCTAssertTrue(app.staticTexts["My VMs"].waitForExistence(timeout: 20))
    }

    func testInstall() {
        let app = launch("--tab=install")
        XCTAssertTrue(app.staticTexts["Install Vms"].waitForExistence(timeout: 20))
    }

    func testSettingsAndAcknowledgements() {
        let app = launch("--tab=settings")
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 20))
        let codeRegion = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Code region'")).firstMatch
        XCTAssertTrue(codeRegion.exists, "no Code region picker")
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label CONTAINS 'Turn on JIT'")).firstMatch.exists)

        let acknowledgements = app.buttons["Acknowledgements"]
        for _ in 0..<6 where !acknowledgements.exists || !acknowledgements.isHittable { app.swipeUp() }
        acknowledgements.tap()
        XCTAssertTrue(app.navigationBars["Acknowledgements"].waitForExistence(timeout: 10))
        // A project's row, which opens its license.
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10), "no projects are listed")
    }
}
