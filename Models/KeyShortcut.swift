import AppKit
import Carbon

struct KeyShortcut: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let optionSpace = KeyShortcut(keyCode: Constants.HotKey.spaceKeyCode, carbonModifiers: UInt32(optionKey))

    var symbols: [String] {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(keyCode))
        return parts
    }

    static func from(event: NSEvent) -> KeyShortcut? {
        if event.keyCode == 53 { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasStrongModifier = flags.contains(.command)
            || flags.contains(.option)
            || flags.contains(.control)
        guard hasStrongModifier else { return nil }

        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return KeyShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36, 76: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 117: return "Fwd Del"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            return letterMap[keyCode] ?? "Key \(keyCode)"
        }
    }

    private static let letterMap: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9", 29: "0",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'",
        43: ",", 47: ".", 44: "/"
    ]
}

extension Notification.Name {
    static let veloxOpenShortcutDidChange = Constants.Notify.openShortcutDidChange
    static let veloxSuspendOpenHotKey = Constants.Notify.suspendOpenHotKey
    static let veloxResumeOpenHotKey = Constants.Notify.resumeOpenHotKey
    static let veloxCancelHotKeyCapture = Constants.Notify.cancelHotKeyCapture
}
