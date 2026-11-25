// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import Crate

final class CatalogTests: XCTestCase {
    /// The shape of the images repository's catalog.json, with keys crate
    /// doesn't read (file, release, built, recipe) as it has them.
    static let json = """
    {
      "format": 1,
      "release": "2026.11.14-7",
      "images": [
        {
          "id": "debian-xfce", "name": "Debian", "version": "13", "desktop": "Xfce",
          "cmdline": "console=ttyAMA0 root=/dev/vda rw",
          "kernel": {"file": "debian-xfce-vmlinuz", "size": 37732288, "sha256": "0c57",
                     "url": "https://example.com/debian-xfce-vmlinuz"},
          "initrd": {"file": "debian-xfce-initrd.img", "size": 52080515, "sha256": "19a9",
                     "url": "https://example.com/debian-xfce-initrd.img"},
          "disk": {"size": 3489660928, "sha256": "9fa5", "compression": "xz", "parts": [
            {"file": "part00", "size": 610975732, "sha256": "b7b1", "url": "https://example.com/part00"}
          ]},
          "vendorData": "#cloud-config\\nautologin: {{user}}\\n",
          "release": "2026.11.14-4", "built": "2026-11-14", "recipe": "8d9c"
        },
        {
          "id": "arch-kde", "name": "Arch Linux", "version": "2026.11.14", "desktop": "KDE Plasma",
          "cmdline": "console=ttyAMA0 root=/dev/vda rw",
          "kernel": {"size": 10, "sha256": "aa", "url": "https://example.com/k"},
          "initrd": {"size": 20, "sha256": "bb", "url": "https://example.com/i"},
          "disk": {"size": 8100000000, "sha256": "cc", "compression": "xz", "parts": [
            {"size": 1000, "sha256": "dd", "url": "https://example.com/p0"},
            {"size": 2000, "sha256": "ee", "url": "https://example.com/p1"}
          ]}
        }
      ]
    }
    """

    static func catalog() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(json.utf8))
    }

    func testCatalogDecodes() throws {
        let catalog = try Self.catalog()
        XCTAssertEqual(catalog.release, "2026.11.14-7")
        XCTAssertEqual(catalog.images.map(\.id), ["debian-xfce", "arch-kde"])
        let debian = catalog.images[0]
        XCTAssertEqual(debian.name, "Debian")
        XCTAssertEqual(debian.desktop, "Xfce")
        XCTAssertEqual(debian.disk.compression, "xz")
        XCTAssertEqual(debian.disk.parts.count, 1)
        XCTAssertEqual(debian.vendorData, "#cloud-config\nautologin: {{user}}\n")
        XCTAssertNil(catalog.images[1].vendorData)
    }

    func testAnImagesDistributionIsItsIDsFirstWord() throws {
        let catalog = try Self.catalog()
        XCTAssertEqual(catalog.images[0].distributionID, "debian")
        XCTAssertEqual(catalog.images[0].distribution, .debian)
        XCTAssertEqual(catalog.images[1].distributionID, "arch")
        XCTAssertEqual(catalog.images[1].distribution, .arch)
    }

    func testSizes() throws {
        let catalog = try Self.catalog()
        XCTAssertEqual(catalog.images[0].downloadBytes, 37_732_288 + 52_080_515 + 610_975_732)
        XCTAssertEqual(catalog.images[0].installedBytes, 3_489_660_928 + 37_732_288 + 52_080_515)
        XCTAssertEqual(catalog.images[1].downloadBytes, 10 + 20 + 1000 + 2000)
    }

    func testTheVMAnImageBecomes() throws {
        let image = try Self.catalog().images[1]
        let machine = image.machine(memoryGB: 6, diskGB: 48)
        XCTAssertEqual(machine.distributionID, "arch")
        XCTAssertEqual(machine.name, "Arch Linux")
        XCTAssertEqual(machine.imageID, "arch-kde")
        XCTAssertEqual(machine.desktop, "KDE Plasma")
        XCTAssertEqual(machine.cmdline, "console=ttyAMA0 root=/dev/vda rw")
        XCTAssertEqual(machine.memoryGB, 6)
        XCTAssertEqual(machine.diskGB, 48)
        XCTAssertEqual(machine.diskUsedGB, 8.1, accuracy: 0.001)
        XCTAssertNil(machine.lastStarted)
    }
}
