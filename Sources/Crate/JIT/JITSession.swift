// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation

/// Whether this launch of crate has JIT, and the code region it claimed.
///
/// JIT on iOS is a property of the process, not a setting: it is on when a
/// debugger has attached to crate, which sets `CS_DEBUGGED` and relaxes iOS's
/// rule against writing code and then running it. Only builds signed for
/// development can be attached to (`get-task-allow`), which is why crate can't
/// come from the App Store. The flag dies with the process, so every launch
/// starts without it until something attaches again.
///
/// Since iOS 26 attaching isn't enough: the pages code runs from must also be
/// authorized by the debugger. crate asks once per launch, for the size chosen
/// in Settings, by stopping on `brk #0x69` (the convention StikDebug's
/// legacy.js answers, as does the built-in enabler), and keeps that region
/// until it quits. A later VM gets the same region.
@MainActor @Observable
final class JITSession {
    enum State: Equatable {
        case checking
        case off(OffReason)
        case on(regionMB: Int)
        case failed(String)
    }

    enum OffReason: Equatable {
        /// Nothing has attached this launch. The usual case.
        case noDebugger
        /// Something attached and left without authorizing the code region:
        /// StikDebug with a script other than legacy.js does this.
        case debuggerLeft
        /// This build can never be attached to (no get-task-allow).
        case notEligible
    }

    private(set) var state = State.checking

    /// The region itself, for the engine, once claimed.
    private(set) var region: crate_code_region?

    var isOn: Bool {
        if case .on = state { return true }
        return pretending
    }

    /// Why JIT isn't on, when there's more to say than "nothing attached".
    var problem: String? {
        if let enablerError { return enablerError }
        switch state {
        case .off(.debuggerLeft):
            return "A debugger turned JIT on but left without authorizing crate's code region. If it was StikDebug, choose the legacy.js script for crate in StikDebug."
        case .off(.notEligible):
            return "This copy of crate can't use JIT: it wasn't signed for development, so nothing can attach to it."
        case .failed(let message):
            return message
        case .checking, .on, .off(.noDebugger):
            return nil
        }
    }

    /// What the last attempt to turn JIT on said went wrong, if it did.
    var enablerError: String?
    var isTurningOn = false
    /// What the built-in helper said stopped it, while turning on.
    var helperFailure: String?
    /// Turning on stopped because LocalDevVPN wasn't connected: it's tried
    /// again when crate is next in front (`cameToFront()`).
    var waitingForVPN = false
    /// How many times crate has come to the front, so a check of the tunnel
    /// can tell if crate came back from LocalDevVPN while it ran.
    var cameToFrontCount = 0
    /// Built-in StikJIT isn't set up yet: shows the Set Up JIT sheet.
    var showingSetup = false
    /// Whether Built-in StikJIT has a pairing, for Settings' Set Up JIT row.
    private(set) var isPaired = PairingFile.exists

    /// Re-reads `isPaired` after Set Up JIT may have changed it.
    func pairingChanged() {
        isPaired = PairingFile.exists
    }

    /// Checks at launch: when a debugger is already attached (crate was
    /// started from one), claims the region in the background.
    func start() {
        // Before Settings can show a size no longer offered.
        _ = CodeRegion.chosen
        Task { await check() }
    }

    /// Reads the flags and, if a debugger is attached, claims the region. Once
    /// a region is claimed it stays for the launch, so this does nothing more.
    func check() async {
        if case .on = state { return }
        state = .checking
        let sizeMB = CodeRegion.chosen
        let (state, region) = await Task.detached(priority: .userInitiated) {
            Self.claim(sizeMB: sizeMB)
        }.value
        self.state = state
        self.region = region
    }

    /// Whether a debugger is attached that can authorize the region: on iOS 26
    /// and later it has to still be there (traced), earlier CS_DEBUGGED is enough.
    nonisolated static var debuggerReady: Bool {
        var flags: UInt32 = 0
        guard crate_jit_cs_flags(&flags), flags & csDebugged != 0 else { return false }
        if #available(iOS 26, *) { return crate_jit_traced() }
        return true
    }

    // MARK: - Claiming

    nonisolated private static let csGetTaskAllow: UInt32 = 0x0000_0004
    nonisolated private static let csDebugged: UInt32 = 0x1000_0000

    /// Set while the region is being claimed and tested, so a launch that
    /// finds it set knows the last one died there and doesn't try again.
    nonisolated private static let claimingKey = "jit.claiming"

    nonisolated private static func claim(sizeMB: Int) -> (State, crate_code_region?) {
        var flags: UInt32 = 0
        guard crate_jit_cs_flags(&flags) else {
            AppLog.write("jit: csops failed, assuming no JIT")
            return (.off(.noDebugger), nil)
        }
        let traced = crate_jit_traced()
        AppLog.write("jit: flags=\(String(flags, radix: 16)) debugged=\(flags & csDebugged != 0) "
                     + "eligible=\(flags & csGetTaskAllow != 0) traced=\(traced)")
        guard flags & csDebugged != 0 else {
            return (.off(flags & csGetTaskAllow != 0 ? .noDebugger : .notEligible), nil)
        }
        let needsAuthorization: Bool
        if #available(iOS 26, *) { needsAuthorization = true } else { needsAuthorization = false }
        if needsAuthorization && !traced {
            return (.off(.debuggerLeft), nil)
        }

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: claimingKey) {
            defaults.set(false, forKey: claimingKey)
            AppLog.write("jit: the last launch died claiming its code region; not trying again")
            return (.failed("crate closed while claiming its code region last time, so this launch skipped it. Turn JIT on again to retry."), nil)
        }
        defaults.set(true, forKey: claimingKey)
        defaults.synchronize()
        defer {
            defaults.set(false, forKey: claimingKey)
        }

        let started = Date.now
        var region = crate_code_region()
        // Below 64 GiB iOS sometimes leaves no gap of the size chosen; less
        // than this isn't worth having.
        let minimumMB = min(sizeMB, CodeRegion.minimumFallback)
        if crate_code_region_map(sizeMB << 20, minimumMB << 20, needsAuthorization, &region) != CRATE_REGION_OK {
            let errorText = String(cString: strerror(errno))
            AppLog.write("jit: no room for \(sizeMB) MB below 64 GiB: iOS first offered "
                         + "\(String(crate_code_region_first_offer, radix: 16)), largest gap \(crate_code_region_largest_gap >> 20) MiB")
            return failure(needsAuthorization
                ? "iOS wouldn't map \(sizeMB) MB for code low enough for the debugger to authorize (\(errorText)). Close crate and open it again to retry."
                : "iOS wouldn't map \(sizeMB) MB for code (\(errorText)). Try a smaller code region.")
        }
        let claimedMB = region.size >> 20
        if claimedMB < sizeMB {
            AppLog.write("jit: no room for \(sizeMB) MB below 64 GiB (iOS first offered "
                         + "\(String(crate_code_region_first_offer, radix: 16))); taking the largest gap, \(claimedMB) MB")
        }
        // Logged before the step that can kill the process, so a crash there has an address.
        AppLog.write("jit: claiming \(claimedMB) MB at \(String(UInt(bitPattern: region.executable), radix: 16)) "
                     + "(iOS first offered \(String(crate_code_region_first_offer, radix: 16))), "
                     + "authorized=\(needsAuthorization)")
        let status = crate_code_region_finish(&region, needsAuthorization)
        let errorText = String(cString: strerror(errno))
        switch status {
        case CRATE_REGION_OK:
            break
        case CRATE_REGION_REFUSED:
            return failure("The debugger refused to authorize crate's code region. If it's StikDebug, choose the legacy.js script for crate.")
        case CRATE_REGION_REMAP_FAILED:
            return failure("iOS wouldn't map the code region a second time for writing.")
        default:
            return failure("iOS wouldn't make the code region writable (\(errorText)).")
        }
        let seconds = Date.now.timeIntervalSince(started)
        guard crate_code_region_test(&region) else {
            return failure("Code written into the region didn't run correctly.")
        }
        AppLog.write("jit: on, \(claimedMB) MB claimed and tested in \(String(format: "%.2f", seconds)) s, "
                     + "code at \(String(UInt(bitPattern: region.executable), radix: 16)), "
                     + "written at \(String(UInt(bitPattern: region.writable), radix: 16))")
        return (.on(regionMB: claimedMB), region)
    }

    nonisolated private static func failure(_ message: String) -> (State, crate_code_region?) {
        AppLog.write("jit: failed: \(message)")
        return (.failed(message), nil)
    }

    // MARK: - UI preview

    /// Debug builds only: pretend JIT is on, to see the screens that need it
    /// without a debugger. Set by the `--jit=on` launch argument.
    var pretending: Bool = JITSession.storedPretending {
        didSet { UserDefaults.standard.set(pretending, forKey: SettingsKey.previewJIT) }
    }

    private static var storedPretending: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: SettingsKey.previewJIT)
        #else
        false
        #endif
    }
}
