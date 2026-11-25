// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Keeps a run of alike lines from filling the log: the first few of a kind go
/// in, the rest are counted, and a note says how many there were.
///
/// The engine can say one thing thousands of times a second. When a VM's GPU
/// context was lost on an iPhone, virglrenderer failed to make a fence 11,000
/// times a second, and crate logged every one: 480 MB in five minutes, until
/// crate was closed. Lines are of a kind when only their numbers differ
/// ("fence 294955: create_fence: 12" and "fence 294956: create_fence: 12").
final class LogSquelch: @unchecked Sendable {
    /// How many of a kind go in per window, and how long a window is.
    let burst: Int
    let window: TimeInterval

    private struct Run {
        var began: TimeInterval
        var passed = 1
        var counted = 0
    }

    private let lock = NSLock()
    private var runs: [String: Run] = [:]
    private var swept: TimeInterval = 0

    init(burst: Int = 5, window: TimeInterval = 5) {
        self.burst = burst
        self.window = window
    }

    /// What to write for `line`, arriving at `now` (seconds on any clock that
    /// doesn't go back): the line itself, or nothing while its kind is being
    /// counted; before either, a note for each kind whose window has ended
    /// with lines counted.
    func admit(_ line: String, at now: TimeInterval) -> [String] {
        let kind = Self.kind(of: line)
        return lock.withLock {
            var out: [String] = []
            // Not on every line: a flood is when this is called most.
            if now - swept >= 1 {
                swept = now
                out = endRuns { now - $0.began >= window }
            }
            if var run = runs[kind] {
                if run.passed < burst {
                    run.passed += 1
                    out.append(line)
                } else {
                    run.counted += 1
                }
                runs[kind] = run
            } else {
                runs[kind] = Run(began: now)
                out.append(line)
            }
            return out
        }
    }

    /// A note for every kind still being counted, as when the VM stops: after
    /// that nothing may arrive to end their windows.
    func flush() -> [String] {
        lock.withLock { endRuns { _ in true } }
    }

    /// Forgets the runs `ended` picks, and returns a note for each that had
    /// lines counted, in the kinds' order so the log reads the same each time.
    private func endRuns(where ended: (Run) -> Bool) -> [String] {
        var notes: [String] = []
        for (kind, run) in runs.sorted(by: { $0.key < $1.key }) where ended(run) {
            if run.counted > 0 {
                notes.append("(\(run.counted) more like: \(kind))")
            }
            runs[kind] = nil
        }
        return notes
    }

    /// The line with each number in it replaced by "#".
    static func kind(of line: String) -> String {
        var kind = ""
        kind.reserveCapacity(line.utf8.count)
        var inNumber = false
        for character in line {
            if character.isASCII, character.isNumber {
                if !inNumber { kind.append("#") }
                inNumber = true
            } else {
                kind.append(character)
                inNumber = false
            }
        }
        return kind
    }
}
