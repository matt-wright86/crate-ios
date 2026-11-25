// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

final class DiskSizeTests: XCTestCase {
    private let gib = Int64(1) << 30

    func testStopsStartAboveTheImageWithRoomToWrite() throws {
        // 3.5 GB of image is 4 GiB rounded up, and 8 GiB of room: 16 is the first stop that holds it.
        let debian = try CatalogTests.catalog().images[0]
        XCTAssertEqual(DiskSize.stops(for: debian, deviceBytes: nil).first, 16)
        // 8.1 GB is 8 GiB rounded up, and 8 GiB of room: 16 exactly.
        let arch = try CatalogTests.catalog().images[1]
        XCTAssertEqual(DiskSize.stops(for: arch, deviceBytes: nil).first, 16)
        XCTAssertEqual(DiskSize.stops(for: nil, deviceBytes: nil), DiskSize.allStops)
    }

    func testStopsEndAtWhatTheDeviceHolds() {
        XCTAssertEqual(DiskSize.stops(for: nil, deviceBytes: 64 * gib), [16, 24, 32, 48, 64])
        XCTAssertEqual(DiskSize.stops(for: nil, deviceBytes: 127 * gib).last, 96)
        // Smaller than any stop: the smallest is still offered.
        XCTAssertEqual(DiskSize.stops(for: nil, deviceBytes: 8 * gib), [16])
    }

    func testTheNearestStopToASizePickedForAnotherImage() {
        XCTAssertEqual(DiskSize.nearest(to: 32, in: [16, 24, 32, 48]), 32)
        XCTAssertEqual(DiskSize.nearest(to: 32, in: [48, 64]), 48)
        XCTAssertEqual(DiskSize.nearest(to: 100, in: [16, 96, 128]), 96)
        XCTAssertEqual(DiskSize.nearest(to: 32, in: []), DiskSize.standard)
    }

    func testWhatLinuxWritesAcrossANewDisk() {
        XCTAssertEqual(DiskSize.setAside(64), 1 << 30)
        XCTAssertEqual(DiskSize.setAside(32), 512 << 20)
    }
}
