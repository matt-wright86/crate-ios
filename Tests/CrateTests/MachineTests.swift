// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

final class MachineTests: XCTestCase {
    func testAVMSurvivesBeingSavedAndRead() throws {
        var machine = try CatalogTests.catalog().images[0].machine(memoryGB: 4, diskGB: 32)
        machine.lastStarted = Date(timeIntervalSinceReferenceDate: 800_000_000)
        machine.fullWidthInLandscape = false
        let read = try JSONDecoder().decode(Machine.self, from: JSONEncoder().encode(machine))
        XCTAssertEqual(read, machine)
    }

    /// What later versions added reads as nil in a list an earlier one saved.
    func testAVMSavedBeforeItsNewerSettingsStillReads() throws {
        let json = """
        {"id": "11111111-2222-3333-4444-555555555555", "distributionID": "debian", "version": "13",
         "cpuCount": 4, "memoryGB": 4, "diskGB": 32, "diskUsedGB": 3.5, "desktop": "Xfce",
         "display": "1280 × 800", "architecture": "arm64"}
        """
        let machine = try JSONDecoder().decode(Machine.self, from: Data(json.utf8))
        XCTAssertEqual(machine.id, UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        XCTAssertNil(machine.imageID)
        XCTAssertNil(machine.cmdline)
        XCTAssertNil(machine.previewDate)
        XCTAssertTrue(machine.isFullWidthInLandscape)
    }

    func testVersionLabel() {
        XCTAssertEqual(Machine.sampleDebian.versionLabel, "13.2 Trixie")
        XCTAssertEqual(Machine.sampleArch.versionLabel, "2026.11.01")
    }

    func testAnUnknownDistributionIsDrawnAsDebian() {
        XCTAssertEqual(Distribution.named("arch"), .arch)
        XCTAssertEqual(Distribution.named("ubuntu").name, "Ubuntu")
        XCTAssertEqual(Distribution.named("plan9"), .debian)
    }
}
