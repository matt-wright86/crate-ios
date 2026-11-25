// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

final class GPUEnvironmentTests: XCTestCase {
    /// Without it, a guest drawing as crate leaves the front loses its GPU
    /// context for good: the VM's screen is black on coming back. The tests
    /// run inside the app, which has launched, so it's set by now, before
    /// any VM could have started MoltenVK.
    func testALostDeviceIsResumedFromLaunch() {
        XCTAssertEqual(getenv(GPUEnvironment.resumeLostDevice).map { String(cString: $0) }, "1")
    }

    func testAValueAlreadySetIsLeftAlone() {
        setenv(GPUEnvironment.resumeLostDevice, "0", 1)
        defer { setenv(GPUEnvironment.resumeLostDevice, "1", 1) }
        GPUEnvironment.prepare()
        XCTAssertEqual(getenv(GPUEnvironment.resumeLostDevice).map { String(cString: $0) }, "0")
    }
}
