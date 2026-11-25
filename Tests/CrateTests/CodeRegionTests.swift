// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

final class CodeRegionTests: XCTestCase {
    private let key = SettingsKey.codeRegionMB
    private var saved: Any?

    override func setUp() {
        saved = UserDefaults.standard.object(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.set(saved, forKey: key)
    }

    /// crate uses at most 128 MiB of the region for each of a VM's 4 CPUs
    /// (crate.h, crate_config_set_jit_region): more is claimed for nothing,
    /// and from iOS 26 counts against the memory limit all the same.
    func testTheLargestRegionIsWhatAVMsCPUsCanUse() throws {
        let cpus = try CatalogTests.catalog().images[0].machine(memoryGB: 4, diskGB: 32).cpuCount
        XCTAssertEqual(CodeRegion.choices.max(), cpus * 128)
        XCTAssertEqual(CodeRegion.standard, CodeRegion.choices.max())
        XCTAssertEqual(CodeRegion.choices, CodeRegion.choices.sorted())
        XCTAssertTrue(CodeRegion.choices.contains(CodeRegion.minimumFallback))
    }

    func testTheSizeChosenIsTheDefaultUntilOneIs() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(CodeRegion.chosen, CodeRegion.standard)
        UserDefaults.standard.set(256, forKey: key)
        XCTAssertEqual(CodeRegion.chosen, 256)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: key), 256)
    }

    /// 768 and 1024 MB were offered once, and the default was 1024.
    func testALargerSizeFromAnEarlierCrateIsBroughtDown() {
        for earlier in [768, 1024] {
            UserDefaults.standard.set(earlier, forKey: key)
            XCTAssertEqual(CodeRegion.chosen, CodeRegion.standard)
            // Saved too, so Settings shows a size it offers.
            XCTAssertEqual(UserDefaults.standard.integer(forKey: key), CodeRegion.standard)
        }
    }
}
