// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

/// A guest that suspends itself can't be woken: its screen stays black until
/// the VM is stopped. Every VM boots with systemd's sleep units masked.
final class BootCommandLineTests: XCTestCase {
    private typealias Settings = MachineRunner.Settings

    private func words(_ commandLine: String) -> [String] {
        commandLine.split(separator: " ").map(String.init)
    }

    func testACatalogImagesCommandLineKeepsItsOwnWordsFirst() throws {
        let image = try CatalogTests.catalog().images[0]
        let kept = Settings.keptAwake(image.cmdline)
        XCTAssertTrue(kept.hasPrefix(image.cmdline + " "), kept)
        XCTAssertEqual(Array(words(kept).prefix(3)), ["console=ttyAMA0", "root=/dev/vda", "rw"])
    }

    func testEveryWayToSleepIsMasked() {
        let kept = words(Settings.keptAwake("console=ttyAMA0 root=/dev/vda rw"))
        for unit in ["sleep.target", "suspend.target", "hibernate.target", "hybrid-sleep.target",
                     "suspend-then-hibernate.target"] {
            XCTAssertTrue(kept.contains("systemd.mask=\(unit)"), "\(unit) isn't masked")
        }
    }

    func testMasksAlreadyThereArentRepeated() {
        let once = Settings.keptAwake("console=ttyAMA0 root=/dev/vda rw")
        XCTAssertEqual(Settings.keptAwake(once), once)
        let partly = Settings.keptAwake("root=/dev/vda systemd.mask=suspend.target")
        XCTAssertEqual(words(partly).filter { $0 == "systemd.mask=suspend.target" }.count, 1)
        XCTAssertTrue(words(partly).contains("systemd.mask=sleep.target"))
    }

    /// The command line of a VM with none of its own, which masks other units already.
    func testTheDefaultCommandLineIsKeptAwakeToo() {
        let kept = words(Settings.keptAwake(Settings.commandLine))
        XCTAssertTrue(kept.contains("systemd.mask=suspend.target"))
        XCTAssertTrue(kept.contains("systemd.mask=apt-daily.timer"), "its own masks went")
        XCTAssertEqual(Set(kept).count, kept.count, "a word is there twice")
    }
}
