// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import UIKit

/// Keeps the screen from locking while something runs that locking would
/// stop: iOS suspends crate soon after the screen locks, which ends an install
/// and freezes a running VM, and may close crate while it's suspended. An
/// install and a VM can both ask at once; the screen may lock again when
/// neither does.
@MainActor
enum ScreenAwake {
    enum Reason: String {
        case install
        /// Heeded only while Settings leaves "Keep the screen on" on.
        case machine
    }

    private static var asking: Set<Reason> = []

    static func set(_ reason: Reason, _ on: Bool) {
        if on { asking.insert(reason) } else { asking.remove(reason) }
        apply()
    }

    /// Also for Settings, when its switch changes while a VM runs.
    static func apply() {
        var heeded = asking
        if !heedsMachine { heeded.remove(.machine) }
        let awake = !heeded.isEmpty
        guard UIApplication.shared.isIdleTimerDisabled != awake else { return }
        UIApplication.shared.isIdleTimerDisabled = awake
        AppLog.write(awake
            ? "screen: staying on (\(heeded.map(\.rawValue).sorted().joined(separator: ", ")))"
            : "screen: may lock again")
    }

    private static var heedsMachine: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.keepScreenOn) as? Bool ?? true
    }
}
