// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import UIKit
import XCTest
@testable import Crate

@MainActor
final class ScreenAwakeTests: XCTestCase {
    private var isKeptOn: Bool { UIApplication.shared.isIdleTimerDisabled }

    /// Runs `body` with neither an install nor a VM asking and the setting as
    /// it comes, and leaves it so.
    private func fromNothingAsking(_ body: () -> Void) {
        let defaults = UserDefaults.standard, key = SettingsKey.keepScreenOn
        let saved = defaults.object(forKey: key)
        func reset() {
            ScreenAwake.set(.install, false)
            ScreenAwake.set(.machine, false)
        }
        defaults.removeObject(forKey: key)
        reset()
        body()
        reset()
        defaults.set(saved, forKey: key)
        ScreenAwake.apply()
    }

    func testTheScreenMayLockWhenNothingAsks() {
        fromNothingAsking {
            XCTAssertFalse(isKeptOn)
        }
    }

    func testARunningVMKeepsTheScreenOn() {
        fromNothingAsking {
            ScreenAwake.set(.machine, true)
            XCTAssertTrue(isKeptOn)
            ScreenAwake.set(.machine, false)
            XCTAssertFalse(isKeptOn)
        }
    }

    /// An install's end used to let the screen lock whatever else was going on.
    func testTheScreenStaysOnUntilNeitherAnInstallNorAVMAsks() {
        fromNothingAsking {
            ScreenAwake.set(.install, true)
            ScreenAwake.set(.machine, true)
            ScreenAwake.set(.install, false)
            XCTAssertTrue(isKeptOn, "the install's end let the screen lock under a running VM")
            ScreenAwake.set(.install, true)
            ScreenAwake.set(.machine, false)
            XCTAssertTrue(isKeptOn, "the VM's stop let the screen lock under an install")
            ScreenAwake.set(.install, false)
            XCTAssertFalse(isKeptOn)
        }
    }

    func testSettingsCanLetTheScreenLockUnderAVMButNotUnderAnInstall() {
        fromNothingAsking {
            UserDefaults.standard.set(false, forKey: SettingsKey.keepScreenOn)
            ScreenAwake.set(.machine, true)
            XCTAssertFalse(isKeptOn)
            ScreenAwake.set(.install, true)
            XCTAssertTrue(isKeptOn)
        }
    }

    func testChangingTheSettingAppliesToAVMAlreadyRunning() {
        fromNothingAsking {
            ScreenAwake.set(.machine, true)
            UserDefaults.standard.set(false, forKey: SettingsKey.keepScreenOn)
            ScreenAwake.apply()
            XCTAssertFalse(isKeptOn)
            UserDefaults.standard.set(true, forKey: SettingsKey.keepScreenOn)
            ScreenAwake.apply()
            XCTAssertTrue(isKeptOn)
        }
    }
}
