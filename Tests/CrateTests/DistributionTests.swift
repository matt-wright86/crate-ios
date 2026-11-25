// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

final class DistributionTests: XCTestCase {
    /// The group polkit's own rules name on each: 40-debian-sudo.rules on
    /// Debian and Ubuntu, 50-default.rules everywhere else.
    func testEachDistributionsAdminGroup() {
        XCTAssertEqual(Distribution.debian.adminGroup, "sudo")
        XCTAssertEqual(Distribution.ubuntu.adminGroup, "sudo")
        XCTAssertEqual(Distribution.arch.adminGroup, "wheel")
        XCTAssertEqual(Distribution.omarchy.adminGroup, "wheel")
    }

    func testAnImagesAccountJoinsItsDistributionsGroup() throws {
        let catalog = try CatalogTests.catalog()
        XCTAssertEqual(catalog.images[0].distribution.adminGroup, "sudo")    // debian-xfce
        XCTAssertEqual(catalog.images[1].distribution.adminGroup, "wheel")   // arch-kde
    }
}
