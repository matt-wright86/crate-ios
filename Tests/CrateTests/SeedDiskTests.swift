// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

final class SeedDiskTests: XCTestCase {
    private func seed(user: String = "matt", adminGroup: String = "sudo", vendorData: String? = nil) -> SeedDisk {
        SeedDisk(user: user, password: "hunter2", hostname: "debian", timeZone: "America/Chicago",
                 adminGroup: adminGroup, vendorData: vendorData)
    }

    // MARK: - The password's hash

    /// Against glibc's crypt, as `openssl passwd -6 -salt SALT PASSWORD` gives it.
    func testPasswordHashIsGlibcsSHA512Crypt() {
        // The specification's own example.
        XCTAssertEqual(SHA512Crypt.hash("Hello world!", salt: "saltstring"),
                       "$6$saltstring$svn8UoSVapNtMuq1ukKS4tPQd8iKwSMHWjl/O817G3uBnIFNjnQJuesI68u4OTLiBFdcbYEdFCoEOfaS35inz1")
        // Longer than one SHA-512 digest, which takes the loops round more than once.
        let long = "The quick brown fox jumps over the lazy dog, then does it again, and again, and once more."
        XCTAssertEqual(SHA512Crypt.hash(long, salt: "0123456789abcdef"),
                       "$6$0123456789abcdef$m7RyqSgxC5BQlpgbWVd1Gx65rXoUbtC1ZfRfOu89mnXuvUDXoQILqszHDYc.Fb.U5E5V0LhB1YNvOHnyZs32O.")
        // Hashed as UTF-8.
        XCTAssertEqual(SHA512Crypt.hash("pässwörd✓", salt: "Zx9./AbC"),
                       "$6$Zx9./AbC$oSyeEb4JdxE64CXbpyBqNUSdEIJqKJw2q.st1VHbOXkdRzN8U0.sOvDMQWELfPckrcgpjrCyPpqHlBQniLMun.")
    }

    func testSaltIsCutToSixteenCharacters() {
        XCTAssertEqual(SHA512Crypt.hash("hunter2", salt: "0123456789abcdefTOOLONG"),
                       SHA512Crypt.hash("hunter2", salt: "0123456789abcdef"))
    }

    func testEachHashGetsASaltOfItsOwn() {
        let first = SHA512Crypt.hash("hunter2"), second = SHA512Crypt.hash("hunter2")
        XCTAssertNotEqual(first, second)
        let salt = first.split(separator: "$")[1]
        XCTAssertEqual(salt.count, 16)
        XCTAssertEqual(SHA512Crypt.hash("hunter2", salt: String(salt)), first)
    }

    // MARK: - Names

    func testUserNamesLinuxAccepts() {
        for name in ["matt", "m", "_svc", "a-b_c9", String(repeating: "a", count: 32)] {
            XCTAssertTrue(SeedDisk.isValid(user: name), name)
        }
        for name in ["", "Matt", "9lives", "-dash", "has space", "ünï", String(repeating: "a", count: 33), "root"] {
            XCTAssertFalse(SeedDisk.isValid(user: name), name)
        }
    }

    /// Accounts the images have already: cloud-init would change one of them
    /// instead of making the owner's, and the desktop needs the display
    /// manager's and polkit's as they are.
    func testNamesOfSystemAccountsAreRefused() {
        for name in ["root", "daemon", "nobody", "gdm", "sddm", "lightdm", "polkitd", "sshd", "games", "mail", "_apt"] {
            XCTAssertFalse(SeedDisk.isValid(user: name), name)
        }
    }

    func testHostnames() {
        for name in ["debian", "a", "my-vm-2", "9"] {
            XCTAssertTrue(SeedDisk.isValid(hostname: name), name)
        }
        for name in ["", "-vm", "vm-", "My-VM", "has.dot", "under_score", String(repeating: "a", count: 64)] {
            XCTAssertFalse(SeedDisk.isValid(hostname: name), name)
        }
    }

    // MARK: - What cloud-init reads

    func testUserDataMakesTheAccountWithItsPasswordHashed() throws {
        let lines = seed().userData.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(lines.first, "#cloud-config")
        for line in ["hostname: debian", "- name: matt", "sudo: ALL=(ALL) ALL", "lock_passwd: false",
                     "ssh_pwauth: true", "timezone: America/Chicago"] {
            XCTAssertTrue(lines.contains(line), "no \"\(line)\"")
        }
        // Never the password itself: its hash, which the password and salt give again.
        XCTAssertFalse(seed().userData.contains("hunter2"))
        let passwd = try XCTUnwrap(lines.first { $0.hasPrefix("passwd: ") })
        let hash = passwd.dropFirst("passwd: ".count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let salt = String(hash.split(separator: "$")[1])
        XCTAssertEqual(SHA512Crypt.hash("hunter2", salt: salt), hash)
    }

    /// sudo's rule alone leaves the desktop's password prompts asking for an
    /// administrator the VM doesn't have (oneamendez/crate-ios#9): polkit goes
    /// by the group.
    func testTheAccountJoinsTheGroupPolkitTakesForAdministrators() {
        for group in ["sudo", "wheel"] {
            let lines = seed(adminGroup: group).userData.split(separator: "\n").map(String.init)
            let name = lines.firstIndex(of: "  - name: matt"), groups = lines.firstIndex(of: "    groups: [\(group)]")
            XCTAssertNotNil(groups, "no groups: [\(group)]")
            // Among the account's own settings, not the file's.
            if let name, let groups { XCTAssertGreaterThan(groups, name) }
            XCTAssertTrue(lines.contains("    sudo: ALL=(ALL) ALL"))
        }
    }

    func testMetaDataNamesTheInstance() {
        let instance = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        XCTAssertEqual(seed().metaData(instance: instance),
                       "instance-id: 11111111-2222-3333-4444-555555555555\nlocal-hostname: debian\n")
    }

    // MARK: - The disk

    func testSeedIsAFATDiskLabelledCIDATAHoldingTheFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seed-\(UUID().uuidString).img")
        defer { try? FileManager.default.removeItem(at: url) }
        let owner = seed(vendorData: "#cloud-config\nautologin: {{user}}\n")
        let instance = UUID()
        try owner.write(to: url, instance: instance)
        let image = try Data(contentsOf: url)

        XCTAssertEqual(image.count, 1 << 20)
        XCTAssertEqual(Array(image[510..<512]), [0x55, 0xAA], "no boot signature")
        // The label cloud-init's NoCloud looks for, and blkid reads.
        XCTAssertEqual(String(decoding: image[43..<54], as: UTF8.self), "CIDATA     ")
        XCTAssertEqual(String(decoding: image[54..<62], as: UTF8.self), "FAT12   ")
        // user-data up to the password's hash, whose salt is new each time it's made.
        let userData = try XCTUnwrap(owner.userData.components(separatedBy: "passwd:").first)
        for contents in [userData, owner.metaData(instance: instance), "#cloud-config\nautologin: matt\n"] {
            XCTAssertNotNil(image.range(of: Data(contents.utf8)), "the disk doesn't hold:\n\(contents)")
        }
        XCTAssertNil(image.range(of: Data("{{user}}".utf8)), "vendor-data still has its placeholder")
    }

    func testFilesLongerThanASectorAreWhole() {
        let big = Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        let image = FATImage.make(label: "CIDATA", files: [("user-data", big), ("meta-data", Data("m".utf8))])
        XCTAssertNotNil(image.range(of: big))
    }
}
