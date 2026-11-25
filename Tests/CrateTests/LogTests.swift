// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

/// A run of alike lines mustn't fill the log. On an iPhone a lost GPU context
/// had virglrenderer fail 11,000 times a second, each logged twice: 480 MB in
/// five minutes.
final class LogSquelchTests: XCTestCase {
    private func fence(_ n: Int) -> String { "crate warning: virtio-gpu: fence \(n): create_fence: 12" }

    func testLinesAreOfAKindWhenOnlyTheirNumbersDiffer() {
        XCTAssertEqual(LogSquelch.kind(of: fence(294955)), LogSquelch.kind(of: fence(3314123)))
        XCTAssertEqual(LogSquelch.kind(of: fence(1)), "crate warning: virtio-gpu: fence #: create_fence: #")
        XCTAssertNotEqual(LogSquelch.kind(of: "virglrenderer: Map failed for element buffer"),
                          LogSquelch.kind(of: "virglrenderer: Failed to create fence sync object"))
        XCTAssertEqual(LogSquelch.kind(of: "no numbers here"), "no numbers here")
    }

    func testTheFirstFewOfAKindGoInAndTheRestAreCounted() {
        let squelch = LogSquelch(burst: 3, window: 5)
        var written: [String] = []
        for n in 0..<10 { written += squelch.admit(fence(n), at: Double(n) * 0.1) }
        XCTAssertEqual(written, [fence(0), fence(1), fence(2)])
        // The window over, the next line says what was counted, then goes in itself.
        XCTAssertEqual(squelch.admit(fence(10), at: 6),
                       ["(7 more like: crate warning: virtio-gpu: fence #: create_fence: #)", fence(10)])
    }

    func testOneKindBeingCountedDoesntHoldAnotherBack() {
        let squelch = LogSquelch(burst: 2, window: 5)
        for n in 0..<100 { _ = squelch.admit(fence(n), at: 0.5) }
        XCTAssertEqual(squelch.admit("crate warning: virgl: eglMakeCurrent(0x9): EGL error 0x300e", at: 0.6),
                       ["crate warning: virgl: eglMakeCurrent(0x9): EGL error 0x300e"])
    }

    func testALineThatComesNowAndThenAlwaysGoesIn() {
        let squelch = LogSquelch()
        for tick in 0..<720 {   // an hour of the memory log's line, one every 5 s
            let line = "memory: footprint \(3800 + tick) MiB, available 2300 MiB"
            XCTAssertEqual(squelch.admit(line, at: Double(tick) * 5), [line])
        }
    }

    func testStoppingSaysWhatWasStillBeingCounted() {
        let squelch = LogSquelch(burst: 1, window: 5)
        for n in 0..<50 { _ = squelch.admit(fence(n), at: 1) }
        XCTAssertEqual(squelch.flush(), ["(49 more like: crate warning: virtio-gpu: fence #: create_fence: #)"])
        XCTAssertEqual(squelch.flush(), [])
        XCTAssertEqual(squelch.admit(fence(50), at: 1.5), [fence(50)])
    }

    /// The flood as it was: two kinds, 11,000 of each a second, for a minute.
    func testAFloodComesToAFewLinesAndEveryLineIsAccountedFor() {
        let squelch = LogSquelch()
        var written: [String] = []
        let perSecond = 11_000, seconds = 60
        for second in 0..<seconds {
            for i in 0..<perSecond {
                let now = Double(second) + Double(i) / Double(perSecond)
                written += squelch.admit(fence(second * perSecond + i), at: now)
                written += squelch.admit("crate warning: virglrenderer: Failed to create fence sync object", at: now)
            }
        }
        written += squelch.flush()
        XCTAssertLessThan(written.count, 200, "a minute's flood wrote \(written.count) lines")
        // What went in, and what the notes say was counted, come to all of them.
        let counted = written.compactMap { line -> Int? in
            guard line.hasPrefix("("), let end = line.firstIndex(of: " ") else { return nil }
            return Int(line[line.index(after: line.startIndex)..<end])
        }
        XCTAssertEqual(written.count - counted.count + counted.reduce(0, +), 2 * perSecond * seconds)
    }
}

/// A log that reached its limit keeps how the launch began and what came
/// last, in whole lines.
final class AppLogTrimTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString).log")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    private func line(_ n: Int) -> String { String(format: "[%7.3f] line %06d of the log", Double(n), n) }

    private func writeLog(lines: Int) throws {
        try Data((0..<lines).map { line($0) + "\n" }.joined().utf8).write(to: url)
    }

    private func size() throws -> Int {
        try Data(contentsOf: url).count
    }

    func testALogOverItsLimitLosesItsMiddle() throws {
        try writeLog(lines: 10_000)   // 339 KB
        let left = AppLog.trim(url, over: 100_000, keepingFirst: 20_000, last: 30_000)
        XCTAssertEqual(left, try size(), "what trim says is left isn't what the file holds")
        XCTAssertLessThanOrEqual(try size(), 20_000 + 30_000 + 100)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, line(0))
        XCTAssertEqual(lines.last, line(9_999))
        // One note where the middle was, and around it only whole lines, in order.
        let notes = lines.filter { $0.hasPrefix("[ log ]") }
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("taken out here"), notes[0])
        let kept = lines.filter { !$0.hasPrefix("[ log ]") }
        let numbers = Dictionary(uniqueKeysWithValues: (0..<10_000).map { (line($0), $0) })
        let order = kept.compactMap { numbers[$0] }
        XCTAssertEqual(order.count, kept.count, "a line was cut partway")
        XCTAssertEqual(order, order.sorted())
        // The start and the end, each unbroken, with only the middle gone.
        let gap = try XCTUnwrap(order.indices.dropLast().first { order[$0 + 1] != order[$0] + 1 })
        XCTAssertEqual(Array(order[...gap]), Array(0...gap))
        XCTAssertEqual(Array(order[(gap + 1)...]), Array((10_000 - (order.count - gap - 1))..<10_000))
    }

    func testALogWithinItsLimitIsLeftAlone() throws {
        try writeLog(lines: 100)
        let before = try Data(contentsOf: url)
        AppLog.trim(url, over: 100_000, keepingFirst: 20_000, last: 30_000)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    /// A size remembered from before the first trim would have the second cut
    /// where the file no longer reaches, and lose its end.
    func testTrimmingTwiceLeavesWhatTheFirstLeft() throws {
        try writeLog(lines: 10_000)
        AppLog.trim(url, over: 100_000, keepingFirst: 20_000, last: 30_000)
        let once = try Data(contentsOf: url)
        XCTAssertLessThan(once.count, 100_000)
        XCTAssertEqual(AppLog.trim(url, over: 100_000, keepingFirst: 20_000, last: 30_000), once.count)
        XCTAssertEqual(try Data(contentsOf: url), once)
    }

    func testALogThatGrowsBackIsTrimmedAgainAndKeepsItsNewEnd() throws {
        try writeLog(lines: 10_000)
        AppLog.trim(url, over: 100_000, keepingFirst: 20_000, last: 30_000)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((10_000..<13_000).map { line($0) + "\n" }.joined().utf8))
        try handle.close()
        AppLog.trim(url, over: 100_000, keepingFirst: 20_000, last: 30_000)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, line(0))
        XCTAssertEqual(lines.last, line(12_999))
        XCTAssertLessThan(try size(), 100_000)
    }

    func testTheLimitLeavesRoomToGrowBeforeTheNextTrim() {
        XCTAssertLessThan(AppLog.keptFromStart + AppLog.keptFromEnd, AppLog.limit / 2 + 1)
    }
}
