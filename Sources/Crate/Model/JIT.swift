// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// How Crate gets JIT turned on for itself.
enum JITMethod: String, CaseIterable, Identifiable {
    case builtInStikJIT
    case stikDebug

    var id: Self { self }

    var title: String {
        switch self {
        case .builtInStikJIT: "Built-in StikJIT"
        case .stikDebug: "StikDebug"
        }
    }

    static let standard = Self.builtInStikJIT
}

/// The settings Crate keeps in UserDefaults, by key, so every `@AppStorage`
/// that reads one spells it the same way.
enum SettingsKey {
    static let jitMethod = "jit.method"
    static let jitAtLaunch = "jit.turnOnAtLaunch"
    static let codeRegionMB = "jit.codeRegionMB"
    static let installMemoryGB = "install.memoryGB"
    static let installDiskGB = "install.diskGB"
    /// Whether a running VM keeps the screen from locking. On unless turned off.
    static let keepScreenOn = "screen.keepOnWhileRunning"
    /// Settings > Logs: whether crate logs at all, and whether it logs its
    /// memory while a VM runs. Both on unless turned off.
    static let logsEnabled = "logs.enabled"
    static let logsTrackMemory = "logs.trackMemory"

    /// Debug builds: pretend JIT is on (see `JITSession.previewOn`).
    static let previewJIT = "preview.jitOn"
}

/// Sizes offered for the JIT code region, in MB. It is claimed once per launch,
/// so a change applies the next time crate opens. The default is the largest:
/// more room for translated code means less retranslating, up to what crate
/// uses. It gives each of a VM's CPUs an equal share of the region and uses at
/// most 128 MiB of each (crate.h, crate_config_set_jit_region), so a VM's 4
/// CPUs (CatalogImage.machine) use 512 MB and no more. A larger region holds
/// nothing in the rest, and from iOS 26, where the debugger makes every page
/// resident as it authorizes it, the rest counts against crate's memory limit
/// all the same: memory a VM then can't have.
enum CodeRegion {
    static let choices = [128, 256, 384, 512]
    static let standard = 512
    /// When the size chosen doesn't fit where the debugger can authorize it,
    /// crate takes the largest gap that does, down to this.
    static let minimumFallback = 256

    /// The size chosen in Settings. An earlier crate offered 768 and 1024 MB,
    /// which is put right here, so Settings shows what is claimed.
    static var chosen: Int {
        let defaults = UserDefaults.standard
        guard let stored = defaults.object(forKey: SettingsKey.codeRegionMB) as? Int else { return standard }
        if stored > standard {
            defaults.set(standard, forKey: SettingsKey.codeRegionMB)
            AppLog.write("jit: the code region was set to \(stored) MB, more than a VM uses; now \(standard) MB")
            return standard
        }
        return stored
    }
}
