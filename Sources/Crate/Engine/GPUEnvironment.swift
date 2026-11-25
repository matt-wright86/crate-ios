// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Settings for the libraries the guest's 3D runs on (virglrenderer, ANGLE,
/// MoltenVK), which read them from the environment when a VM first starts
/// one. Set at launch, before any VM.
enum GPUEnvironment {
    /// MoltenVK's setting that keeps a failed submission from ending the
    /// device for good.
    static let resumeLostDevice = "MVK_CONFIG_RESUME_LOST_DEVICE"

    static func prepare() {
        // iOS refuses GPU work from an app in the background. A guest that
        // was drawing when crate left the front (a browser, a 3D page) had a
        // submission refused; MoltenVK then marked its device lost, ANGLE its
        // context, and every GL call after failed: back in crate the VM's
        // screen was black, with the VM still running behind it. On an iPhone
        // with a WebGL page open in Firefox, leaving crate for ten seconds
        // did it every time without this, and never with it: MoltenVK logs
        // the failure and carries on, so drawing picks up when crate is in
        // front again. Not overwritten if it's already set, so a launch can
        // still turn it off.
        setenv(resumeLostDevice, "1", 0)
    }
}
