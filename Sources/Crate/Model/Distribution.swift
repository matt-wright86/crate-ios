// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// The kind of operating system a VM runs. Only Linux installs today; the other
/// two are here so the UI has somewhere to put them when they arrive.
enum OSFamily: String, Codable, CaseIterable, Identifiable {
    case linux
    case macOS
    case windows

    var id: Self { self }

    var title: String {
        switch self {
        case .linux: "Linux"
        case .macOS: "macOS"
        case .windows: "Windows"
        }
    }
}

/// An operating system Crate knows how to install: what it is called and how it
/// is drawn. A ``Machine`` is one installed copy of one of these.
struct Distribution: Identifiable, Hashable {
    let id: String
    let name: String
    let family: OSFamily
    /// Tints a VM's screenshot area. A system colour, so it has dark and
    /// increased-contrast variants; not red (destructive actions) or blue (the
    /// accent, which means "tappable"): pink for Debian's red, indigo for
    /// Arch's blue, orange for Ubuntu's, teal for Omarchy.
    let color: Color
    /// The group polkit takes for administrators, which the owner's account
    /// joins so the desktop's password prompts accept their password: "sudo"
    /// on Debian and Ubuntu, "wheel" on Arch and what's built on it. sudo
    /// alone isn't enough, since polkit never reads sudoers.
    let adminGroup: String

    static let debian = Distribution(id: "debian", name: "Debian", family: .linux, color: .pink,
                                     adminGroup: "sudo")
    static let ubuntu = Distribution(id: "ubuntu", name: "Ubuntu", family: .linux, color: .orange,
                                     adminGroup: "sudo")
    static let arch = Distribution(id: "arch", name: "Arch Linux", family: .linux, color: .indigo,
                                   adminGroup: "wheel")
    static let omarchy = Distribution(id: "omarchy", name: "Omarchy", family: .linux, color: .teal,
                                      adminGroup: "wheel")

    static let all: [Distribution] = [.debian, .ubuntu, .arch, .omarchy]

    static func named(_ id: String) -> Distribution {
        all.first { $0.id == id } ?? .debian
    }
}
