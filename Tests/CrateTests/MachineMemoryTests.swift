// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

/// What a VM is given of the memory iOS still lets crate have.
final class MachineMemoryTests: XCTestCase {
    private func memory(askedGB: Int, available: Int) -> Int? {
        MachineRunner.Settings.memory(askedGB: askedGB, available: available)
    }

    func testAVMGetsWhatItAskedForWhenThatFits() {
        XCTAssertEqual(memory(askedGB: 4, available: 6000), 4096)
        XCTAssertEqual(memory(askedGB: 2, available: 4000), 2048)
    }

    /// 768 MiB stays for the app: the display's frames, the GPU, the network.
    func testAVMIsHeldToWhatFitsBesideTheApp() {
        XCTAssertEqual(memory(askedGB: 6, available: 6000), 5232)
        XCTAssertEqual(memory(askedGB: 4, available: 3000), 2232)
        XCTAssertEqual(memory(askedGB: 2, available: 2001), 1232)   // in whole 2 MiB, as crate takes it
    }

    func testAVMIsNeverGivenLessThanADesktopStartsIn() {
        XCTAssertEqual(memory(askedGB: 4, available: 1793), 1024)
        XCTAssertEqual(memory(askedGB: 4, available: 1500), 1024)
        XCTAssertEqual(memory(askedGB: 4, available: 1025), 1024)
    }

    /// It used to get 1024 MiB all the same, and iOS closed crate as the
    /// guest filled it.
    func testAVMIsntStartedWithMoreThanIOSAllows() {
        XCTAssertNil(memory(askedGB: 4, available: 1024))
        XCTAssertNil(memory(askedGB: 4, available: 874))
        XCTAssertNil(memory(askedGB: 2, available: 1))
    }

    /// The Simulator reports no limit.
    func testWithNoLimitReportedAVMGetsWhatItAskedFor() {
        XCTAssertEqual(memory(askedGB: 8, available: 0), 8192)
    }

    func testWhateverIsAvailableAVMFitsInItOrDoesntStart() {
        for askedGB in [2, 4, 6, 8, 10, 12] {
            for available in stride(from: 1, through: 14000, by: 37) {
                guard let given = memory(askedGB: askedGB, available: available) else {
                    XCTAssertLessThanOrEqual(available, MachineRunner.Settings.leastMemoryMiB)
                    continue
                }
                XCTAssertLessThan(given, available, "asked \(askedGB) GB with \(available) MiB available")
                XCTAssertLessThanOrEqual(given, askedGB * 1024)
                XCTAssertGreaterThanOrEqual(given, MachineRunner.Settings.leastMemoryMiB)
                XCTAssertEqual(given % 2, 0)
            }
        }
    }
}
