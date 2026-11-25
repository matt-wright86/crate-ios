// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

/// The list of VMs, read at launch: a list it can't read, or one that names
/// nothing, must never cost a VM its disk. Each test has a list and a VMs
/// folder of its own.
final class MachineStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""
    private var folder: URL!
    private var appRoot: URL!

    private let vm = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let other = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    override func setUp() {
        suite = "crate-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        appRoot = GuestFiles.root
        GuestFiles.root = folder.appendingPathComponent("VMs", isDirectory: true)
        try? FileManager.default.createDirectory(at: GuestFiles.root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        GuestFiles.root = appRoot
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: - What's on the iPhone

    private func entry(_ id: UUID) -> String {
        """
        {"id": "\(id.uuidString)", "distributionID": "debian", "version": "13", "cpuCount": 4, "memoryGB": 4,
         "diskGB": 32, "diskUsedGB": 3.5, "desktop": "Xfce", "display": "1280 × 800", "architecture": "arm64",
         "imageID": "debian-xfce"}
        """
    }

    private func machine(_ id: UUID) throws -> Machine {
        try JSONDecoder().decode(Machine.self, from: Data(entry(id).utf8))
    }

    /// A VM's folder as an install leaves it, without its record.
    private func makeFiles(_ id: UUID) throws {
        let files = GuestFiles(for: try machine(id))
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        for url in [files.kernel, files.initrd, files.disk] {
            try Data("x".utf8).write(to: url)
        }
    }

    private func save(list: String) {
        defaults.set(Data(list.utf8), forKey: "machines")
    }

    private func hasDisk(_ id: UUID) throws -> Bool {
        FileManager.default.fileExists(atPath: GuestFiles(for: try machine(id)).disk.path)
    }

    private func hasRecord(_ id: UUID) throws -> Bool {
        FileManager.default.fileExists(atPath: GuestFiles(for: try machine(id)).record.path)
    }

    private func store() -> MachineStore {
        MachineStore(defaults: defaults)
    }

    // MARK: - An ordinary launch

    func testAListedVMIsShownAndItsFolderGetsItsRecord() throws {
        try makeFiles(vm)
        save(list: "[\(entry(vm))]")
        XCTAssertEqual(store().machines.map(\.id), [vm])
        XCTAssertTrue(try hasDisk(vm))
        XCTAssertTrue(try hasRecord(vm))
    }

    func testAFolderAnInstallLeftPartwayIsRemoved() throws {
        try makeFiles(vm)
        try makeFiles(other)
        save(list: "[\(entry(vm))]")
        XCTAssertEqual(store().machines.map(\.id), [vm])
        XCTAssertTrue(try hasDisk(vm))
        XCTAssertFalse(try hasDisk(other), "the stray folder is still there")
    }

    func testANewInstallNeedsNoListToStartFrom() {
        XCTAssertTrue(store().machines.isEmpty)
    }

    // MARK: - A list that can't be read

    /// Every VM's disk used to go: the list read as empty, so every folder
    /// looked like a stray.
    func testAListThatIsntJSONCostsNoVMItsDisk() throws {
        try makeFiles(vm)
        save(list: "not json")
        _ = store()
        XCTAssertTrue(try hasDisk(vm))
        // The next launch reads the list the last one saved, and still keeps it.
        _ = store()
        XCTAssertTrue(try hasDisk(vm), "kept once, then taken for a stray")
    }

    /// As a field this crate requires and an earlier one never saved would be.
    func testAnEntryThatCantBeReadCostsNoVMItsDisk() throws {
        try makeFiles(vm)
        try makeFiles(other)
        save(list: "[{\"id\": \"\(vm.uuidString)\", \"distributionID\": \"debian\"}, \(entry(other))]")
        XCTAssertEqual(store().machines.map(\.id), [other], "the entry that reads isn't listed")
        XCTAssertTrue(try hasDisk(vm))
        XCTAssertTrue(try hasDisk(other))
    }

    func testAListThatCantBeReadIsKeptAside() throws {
        save(list: "not json")
        _ = store()
        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix("machines-unreadable-") }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent(kept[0]), encoding: .utf8), "not json")
    }

    func testAVMTheListLostIsPutBackFromItsFolder() throws {
        try makeFiles(vm)
        save(list: "[\(entry(vm))]")
        _ = store()                       // writes the folder's record
        save(list: "not json")
        XCTAssertEqual(store().machines.map(\.id), [vm])
        XCTAssertTrue(try hasDisk(vm))
        // And it's in the list again for the launch after.
        defaults.removeObject(forKey: "machines.keptFolders")
        XCTAssertEqual(store().machines.map(\.id), [vm])
    }

    func testAVMIsPutBackWhenTheListIsGoneAltogether() throws {
        try makeFiles(vm)
        save(list: "[\(entry(vm))]")
        _ = store()
        defaults.removeObject(forKey: "machines")
        XCTAssertEqual(store().machines.map(\.id), [vm])
        XCTAssertTrue(try hasDisk(vm))
    }

    // MARK: - Lists made up for previewing the UI

    /// --empty and --samples used to save their list, and the next ordinary
    /// launch removed every VM as a stray.
    func testAnEmptyListForPreviewingIsntSaved() throws {
        try makeFiles(vm)
        save(list: "[\(entry(vm))]")
        let previewing = store()
        previewing.removeAll()
        XCTAssertTrue(previewing.machines.isEmpty)
        XCTAssertEqual(store().machines.map(\.id), [vm])
        XCTAssertTrue(try hasDisk(vm))
    }

    func testTheSampleVMsArentSaved() throws {
        try makeFiles(vm)
        save(list: "[\(entry(vm))]")
        let previewing = store()
        previewing.restoreSamples()
        XCTAssertEqual(previewing.machines.count, Machine.samples.count)
        XCTAssertEqual(store().machines.map(\.id), [vm])
        XCTAssertTrue(try hasDisk(vm))
    }

    // MARK: - Changes

    func testAnAddedVMIsSavedWithItsRecord() throws {
        let first = store()
        try makeFiles(vm)                 // as an install does, then adds it
        first.add(try machine(vm))
        XCTAssertTrue(try hasRecord(vm))
        XCTAssertEqual(store().machines.map(\.id), [vm])
    }

    func testADeletedVMIsGoneAndStaysGone() throws {
        try makeFiles(vm)
        save(list: "[\(entry(vm))]")
        let first = store()
        first.delete(try machine(vm))
        XCTAssertTrue(first.machines.isEmpty)
        XCTAssertFalse(try hasDisk(vm))
        XCTAssertTrue(store().machines.isEmpty)
    }

    func testAChangeToAVMsSettingsReachesItsRecord() throws {
        try makeFiles(vm)
        save(list: "[\(entry(vm))]")
        let first = store()
        var changed = try machine(vm)
        changed.memoryGB = 8
        first.update(changed)
        let record = try Data(contentsOf: GuestFiles(for: changed).record)
        XCTAssertEqual(try JSONDecoder().decode(Machine.self, from: record).memoryGB, 8)
        XCTAssertEqual(store().machines.first?.memoryGB, 8)
    }
}
