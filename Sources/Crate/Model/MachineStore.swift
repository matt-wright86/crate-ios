// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation

/// The installed VMs.
///
/// Persisted to UserDefaults as JSON; each VM's files are in its own folder
/// (GuestFiles), which also holds a copy of its entry (GuestFiles.record), so
/// a list that can't be read is rebuilt from the folders rather than taken
/// for empty.
@Observable
final class MachineStore {
    private(set) var machines: [Machine] {
        didSet { save() }
    }

    /// False while showing a made-up list (`--empty`, `--samples`), which
    /// must never replace the real one.
    @ObservationIgnored private var persists = true

    private static let machinesKey = "machines"
    /// Folders found beside a list that couldn't be read whole, with no
    /// record to say whose they are: never taken for strays, as one may hold
    /// the VM of an entry that was lost.
    private static let keptFoldersKey = "machines.keptFolders"

    init() {
        let defaults = UserDefaults.standard
        // From when a starred VM booted at launch.
        defaults.removeObject(forKey: "defaultMachineID")
        let (saved, readable) = Self.load(defaults.data(forKey: Self.machinesKey))
        // v0.1 started with the sample VMs, which have no image and no files.
        machines = saved.filter { $0.imageID != nil || GuestFiles(for: $0).exists }
        for machine in saved where !machines.contains(machine) {
            AppLog.write("store: removed \(machine.name), which has no files")
        }
        recoverFromFolders()
        // Only a list read whole says which folders are strays: after one
        // that wasn't, a folder without a record may be a lost entry's VM
        // from before records were kept, so it's kept from then on.
        if !readable { keepUnclaimedFolders() }
        removeStrayFiles()
        save()
    }

    /// The saved list, and whether all of it could be read. What can't be is
    /// kept aside, so a newer crate's list or a damaged one loses nothing.
    private static func load(_ data: Data?) -> (machines: [Machine], readable: Bool) {
        guard let data else { return ([], true) }
        guard let entries = try? JSONDecoder().decode([Lossy<Machine>].self, from: data) else {
            setAside(data, reason: "isn't a list")
            return ([], false)
        }
        let machines = entries.compactMap(\.value)
        let unread = entries.count - machines.count
        if unread > 0 {
            setAside(data, reason: "has \(unread) \(unread == 1 ? "entry" : "entries") it can't read")
            return (machines, false)
        }
        return (machines, true)
    }

    private static func setAside(_ data: Data, reason: String) {
        let url = URL.applicationSupportDirectory
            .appendingPathComponent("machines-unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
        try? data.write(to: url, options: .atomic)
        AppLog.write("store: the saved list \(reason); kept it as \(url.lastPathComponent)")
    }

    func add(_ machine: Machine) {
        machines.append(machine)
    }

    /// Saves a change to `machine`'s settings.
    func update(_ machine: Machine) {
        guard let index = machines.firstIndex(where: { $0.id == machine.id }) else { return }
        machines[index] = machine
    }

    /// Removes `machine` from the list and its files from the iPhone.
    func delete(_ machine: Machine) {
        let files = GuestFiles(for: machine)
        // Its record first: a folder that still has one is put back in the
        // list at the next launch, should crate close before the rest.
        try? FileManager.default.removeItem(at: files.record)
        machines.removeAll { $0.id == machine.id }
        files.remove()
    }

    /// Its card's preview was saved: the card loads it again.
    func previewSaved(_ machine: Machine) {
        guard let index = machines.firstIndex(where: { $0.id == machine.id }) else { return }
        machines[index].previewDate = .now
    }

    func markStarted(_ machine: Machine) {
        guard let index = machines.firstIndex(where: { $0.id == machine.id }) else { return }
        machines[index].lastStarted = .now
    }

    func isInstalled(_ image: CatalogImage) -> Bool {
        machines.contains { $0.imageID == image.id }
    }

    /// Puts the sample VMs back, for previewing the UI (`--samples`). Not
    /// saved: the real list is there again at the next launch.
    func restoreSamples() {
        persists = false
        machines = Machine.samples.map { var copy = $0; copy.id = UUID(); return copy }
    }

    /// An empty list, for previewing the UI (`--empty`). Not saved: the VMs
    /// and their files are there again at the next launch.
    func removeAll() {
        persists = false
        machines = []
    }

    // MARK: - VM folders

    private static var folders: [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: GuestFiles.root,
                                                               includingPropertiesForKeys: nil)) ?? []
        return all.filter { UUID(uuidString: $0.lastPathComponent) != nil }
    }

    /// Puts back in the list a VM whose folder has its record but the list
    /// doesn't name: one a damaged or unreadable list lost.
    private func recoverFromFolders() {
        let known = Set(machines.map(\.id.uuidString))
        for folder in Self.folders where !known.contains(folder.lastPathComponent) {
            guard let data = try? Data(contentsOf: GuestFiles.record(in: folder)),
                  let machine = try? JSONDecoder().decode(Machine.self, from: data),
                  machine.id.uuidString == folder.lastPathComponent else { continue }
            machines.append(machine)
            AppLog.write("store: recovered \(machine.name) (\(machine.id)) from its folder")
        }
    }

    private func keepUnclaimedFolders() {
        let known = Set(machines.map(\.id.uuidString))
        var kept = Set(UserDefaults.standard.stringArray(forKey: Self.keptFoldersKey) ?? [])
        for folder in Self.folders where !known.contains(folder.lastPathComponent)
            && !FileManager.default.fileExists(atPath: GuestFiles.record(in: folder).path) {
            kept.insert(folder.lastPathComponent)
        }
        UserDefaults.standard.set(Array(kept).sorted(), forKey: Self.keptFoldersKey)
    }

    /// Deletes VM folders no VM in the list names and that hold no record:
    /// what an install that was stopped partway (crate closed or suspended)
    /// left behind. A folder with a record it couldn't read stays, as does
    /// one kept after an unreadable list.
    private func removeStrayFiles() {
        let known = Set(machines.map(\.id.uuidString))
        let kept = Set(UserDefaults.standard.stringArray(forKey: Self.keptFoldersKey) ?? [])
        for folder in Self.folders where !known.contains(folder.lastPathComponent) {
            if kept.contains(folder.lastPathComponent) {
                AppLog.write("store: kept \(folder.lastPathComponent), found beside an unreadable list")
                continue
            }
            guard !FileManager.default.fileExists(atPath: GuestFiles.record(in: folder).path) else {
                AppLog.write("store: kept \(folder.lastPathComponent), whose record this crate can't read")
                continue
            }
            try? FileManager.default.removeItem(at: folder)
            AppLog.write("store: removed \(folder.lastPathComponent), which no VM names")
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        if persists, let data = try? encoder.encode(machines) {
            UserDefaults.standard.set(data, forKey: Self.machinesKey)
        }
        // Records even for a made-up list: a VM installed while one shows is
        // then found by its folder at the next launch.
        for machine in machines {
            let files = GuestFiles(for: machine)
            guard files.exists, let data = try? encoder.encode(machine) else { continue }
            try? data.write(to: files.record, options: .atomic)
        }
    }
}

/// A list entry that decodes to nil instead of failing the whole list.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
