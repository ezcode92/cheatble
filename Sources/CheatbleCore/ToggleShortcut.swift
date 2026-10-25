import Foundation

public struct ToggleShortcut: Equatable {
    public let chord: KeyChord
    public var keyCode: UInt32 { Self.keyCodes[chord.key]! }
    public static let standard = ToggleShortcut(chord: KeyChord(modifiers: [.control, .option, .command], key: "Return"))
    private init(chord: KeyChord) { self.chord = chord }

    public static func parse(_ text: String) throws -> ToggleShortcut {
        let sequence = try KeySequence.parse(text)
        guard sequence.count == 1, let chord = sequence.first,
              chord.modifiers.count >= 2,
              chord.modifiers.contains(.control) || chord.modifiers.contains(.command),
              !chord.modifiers.contains(.function),
              keyCodes[chord.key] != nil else { throw ValidationError.invalid }
        return ToggleShortcut(chord: chord)
    }
    public static func load(from defaults: UserDefaults) -> ToggleShortcut {
        guard let text = defaults.string(forKey: "toggle.shortcut"),
              let shortcut = try? parse(text) else { return .standard }
        return shortcut
    }
    public func save(to defaults: UserDefaults) {
        defaults.set(KeySequence.editable([chord]), forKey: "toggle.shortcut")
    }
    public enum ValidationError: LocalizedError {
        case invalid
        public var errorDescription: String? {
            "Control 또는 Command를 포함해 보조 키를 두 개 이상 선택하세요. 예: Control+Option+Command+Return. 연속 입력과 Fn 조합은 사용할 수 없습니다."
        }
    }
    // Physical keys on the standard Mac keyboard. Text entry is not intercepted.
    private static let keyCodes: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
        "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35,
        "Return": 36, "L": 37, "J": 38, "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "N": 45, "M": 46, ".": 47, "Tab": 48, "Space": 49, "\u{60}": 50,
        "Delete": 51, "Escape": 53, "Home": 115, "PageUp": 116, "ForwardDelete": 117,
        "End": 119, "PageDown": 121, "Left": 123, "Right": 124, "Down": 125, "Up": 126,
        "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97, "F7": 98,
        "F8": 100, "F9": 101, "F10": 109, "F11": 103, "F12": 111, "F13": 105,
        "F14": 107, "F15": 113, "F16": 106, "F17": 64, "F18": 79, "F19": 80, "F20": 90
    ]
}
