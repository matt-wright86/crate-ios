// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

final class FormatTests: XCTestCase {
    /// "5.8" where the Simulator's region writes it "5,8".
    private func decimal(_ whole: Int, _ tenths: Int) -> String {
        "\(whole)\(Locale.current.decimalSeparator ?? ".")\(tenths)"
    }

    func testBytesAreDecimalWithADecimalOnlyBelowTenGB() {
        XCTAssertEqual(Format.bytes(384_000_000), "384 MB")
        XCTAssertEqual(Format.bytes(999_400_000), "999 MB")
        XCTAssertEqual(Format.bytes(1_000_000_000), "\(decimal(1, 0)) GB")
        XCTAssertEqual(Format.bytes(5_800_000_000), "\(decimal(5, 8)) GB")
        XCTAssertEqual(Format.bytes(10_000_000_000), "10 GB")
        XCTAssertEqual(Format.bytes(107_400_000_000), "107 GB")
    }

    func testMemoryIsBinary() {
        let gib: UInt64 = 1 << 30
        XCTAssertEqual(Format.memory(8 * gib), "8 GB")
        XCTAssertEqual(Format.memory(4 * gib + gib / 2), "\(decimal(4, 5)) GB")
        XCTAssertEqual(Format.memory(512 << 20), "512 MB")
        XCTAssertEqual(Format.memory(5 * gib + gib / 4, decimals: 2), "\(decimal(5, 2))5 GB")
        XCTAssertEqual(Format.memory(8 * gib, decimals: 2), "\(decimal(8, 0))0 GB")
    }

    func testNoDateReadsAsNever() {
        XCTAssertEqual(Format.relative(nil), "Never")
    }
}
