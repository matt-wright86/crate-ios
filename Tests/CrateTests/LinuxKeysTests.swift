// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import UIKit
import XCTest
@testable import Crate

final class LinuxKeysTests: XCTestCase {
    func testLettersAndTheirShift() throws {
        let a = try XCTUnwrap(LinuxKeys.stroke(for: "a")), capital = try XCTUnwrap(LinuxKeys.stroke(for: "A"))
        XCTAssertEqual(a.code, 30)          // KEY_A
        XCTAssertFalse(a.shift)
        XCTAssertEqual(capital.code, 30)
        XCTAssertTrue(capital.shift)
        XCTAssertEqual(LinuxKeys.stroke(for: "q")?.code, 16)   // KEY_Q
        XCTAssertEqual(LinuxKeys.stroke(for: "z")?.code, 44)   // KEY_Z
    }

    func testDigitsAndPunctuation() {
        XCTAssertEqual(LinuxKeys.stroke(for: "1")?.code, 2)
        XCTAssertEqual(LinuxKeys.stroke(for: "0")?.code, 11)
        XCTAssertEqual(LinuxKeys.stroke(for: "!")?.code, 2)
        XCTAssertEqual(LinuxKeys.stroke(for: "!")?.shift, true)
        XCTAssertEqual(LinuxKeys.stroke(for: "/")?.code, 53)
        XCTAssertEqual(LinuxKeys.stroke(for: "?")?.shift, true)
        XCTAssertEqual(LinuxKeys.stroke(for: "\n")?.code, 28)  // KEY_ENTER
        XCTAssertEqual(LinuxKeys.stroke(for: " ")?.code, 57)   // KEY_SPACE
    }

    /// Everything a US keyboard prints.
    func testEveryPrintableASCIICharacterHasAKey() {
        for value in UInt8(0x20)...0x7E {
            let character = Character(UnicodeScalar(value))
            XCTAssertNotNil(LinuxKeys.stroke(for: character), "no key types \"\(character)\"")
        }
    }

    func testWhatAUSKeyboardCantTypeHasNoKey() {
        XCTAssertNil(LinuxKeys.stroke(for: "é"))
        XCTAssertNil(LinuxKeys.stroke(for: "€"))
        XCTAssertNil(LinuxKeys.stroke(for: "😀"))
    }

    func testHardwareKeys() {
        XCTAssertEqual(LinuxKeys.code(for: .keyboardA), 30)
        XCTAssertEqual(LinuxKeys.code(for: .keyboardZ), 44)
        XCTAssertEqual(LinuxKeys.code(for: .keyboard1), 2)
        XCTAssertEqual(LinuxKeys.code(for: .keyboard9), 10)
        XCTAssertEqual(LinuxKeys.code(for: .keyboard0), 11)
        XCTAssertEqual(LinuxKeys.code(for: .keyboardReturnOrEnter), 28)
        XCTAssertEqual(LinuxKeys.code(for: .keyboardEscape), 1)
        XCTAssertEqual(LinuxKeys.code(for: .keyboardF1), 59)
        XCTAssertEqual(LinuxKeys.code(for: .keyboardF12), 88)
        XCTAssertEqual(LinuxKeys.code(for: .keyboardUpArrow), 103)
        XCTAssertEqual(LinuxKeys.code(for: .keyboardLeftControl), 29)
        XCTAssertEqual(LinuxKeys.code(for: .keyboardLeftGUI), 125)   // Super
    }

    func testEveryModifierKeyIsAModifier() {
        let usages: [UIKeyboardHIDUsage] = [
            .keyboardLeftControl, .keyboardLeftShift, .keyboardLeftAlt, .keyboardLeftGUI,
            .keyboardRightControl, .keyboardRightShift, .keyboardRightAlt, .keyboardRightGUI,
        ]
        XCTAssertEqual(Set(usages.compactMap(LinuxKeys.code(for:))), LinuxKeys.modifiers)
        XCTAssertEqual(LinuxKeys.code(for: .keyboardLeftShift), LinuxKeys.leftShift)
    }
}
