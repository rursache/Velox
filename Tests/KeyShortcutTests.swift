import Testing
import AppKit
import Carbon
@testable import Velox

@Suite("Key shortcut")
struct KeyShortcutTests {
    @Test func defaultIsOptionSpace() {
        #expect(KeyShortcut.optionSpace.keyCode == Constants.HotKey.spaceKeyCode)
        #expect(KeyShortcut.optionSpace.symbols == ["⌥", "Space"])
        #expect(Constants.Defaults.openShortcut == .optionSpace)
    }

    @Test func commandShiftASymbols() {
        let shortcut = KeyShortcut(
            keyCode: 0,
            carbonModifiers: UInt32(cmdKey) | UInt32(shiftKey)
        )
        #expect(shortcut.symbols == ["⇧", "⌘", "A"])
    }

    @Test func controlOptionSymbols() {
        let shortcut = KeyShortcut(
            keyCode: 49,
            carbonModifiers: UInt32(controlKey) | UInt32(optionKey)
        )
        #expect(shortcut.symbols == ["⌃", "⌥", "Space"])
    }

    @Test func namedSpecialKeys() {
        #expect(KeyShortcut.keyName(36) == "Return")
        #expect(KeyShortcut.keyName(48) == "Tab")
        #expect(KeyShortcut.keyName(123) == "←")
        #expect(KeyShortcut.keyName(12) == "Q")
    }

    @Test func capturesOptionSpaceEvent() throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .option,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: " ",
                charactersIgnoringModifiers: " ",
                isARepeat: false,
                keyCode: 49
            )
        )
        let shortcut = try #require(KeyShortcut.from(event: event))
        #expect(shortcut == .optionSpace)
    }

    @Test func rejectsUnmodifiedLetter() throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            )
        )
        #expect(KeyShortcut.from(event: event) == nil)
    }

    @Test func escapeIsNotAShortcut() throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
        )
        #expect(KeyShortcut.from(event: event) == nil)
    }
}
