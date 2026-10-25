import Foundation

public enum Modifier: String, Codable, CaseIterable, Hashable {
    case control, option, shift, command, function
    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        case .function: return "fn"
        }
    }
    public var name: String { rawValue.capitalized }

    /// AX command modifiers are NOT NSEvent modifier flags. Command is implicit.
    public static func accessibilityMask(_ mask: Int) -> [Modifier] {
        var result: [Modifier] = []
        if mask & 4 != 0 { result.append(.control) }
        if mask & 2 != 0 { result.append(.option) }
        if mask & 1 != 0 { result.append(.shift) }
        if mask & 8 == 0 { result.append(.command) }
        return result
    }
}

public struct KeyChord: Codable, Equatable, Hashable {
    public var modifiers: [Modifier]
    public var key: String
    public init(modifiers: [Modifier] = [], key: String) {
        self.modifiers = Modifier.allCases.filter { modifiers.contains($0) }
        self.key = Self.canonicalKey(key)
    }
    public var display: String { modifiers.map(\.symbol).joined() + Self.displayKey(key) }
    public static func canonicalKey(_ input: String) -> String {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases: [String: String] = [
            "space": "Space", "스페이스": "Space", "공백": "Space", "␣": "Space",
            "tab": "Tab", "⇥": "Tab", "\t": "Tab",
            "return": "Return", "enter": "Return", "⏎": "Return", "↩": "Return",
            "escape": "Escape", "esc": "Escape", "⎋": "Escape",
            "delete": "Delete", "backspace": "Delete", "⌫": "Delete",
            "forwarddelete": "ForwardDelete", "⌦": "ForwardDelete",
            "left": "Left", "←": "Left", "right": "Right", "→": "Right",
            "up": "Up", "↑": "Up", "down": "Down", "↓": "Down",
            "home": "Home", "↖": "Home", "end": "End", "↘": "End",
            "pageup": "PageUp", "⇞": "PageUp", "pagedown": "PageDown", "⇟": "PageDown"
        ]
        return aliases[key.lowercased()] ?? key.uppercased()
    }
    public static func displayKey(_ key: String) -> String {
        ["Space": "Space", "Return": "↩", "Tab": "⇥", "Escape": "esc",
         "Delete": "⌫", "ForwardDelete": "⌦", "Left": "←", "Right": "→",
         "Up": "↑", "Down": "↓", "Home": "↖", "End": "↘",
         "PageUp": "⇞", "PageDown": "⇟"][key] ?? key
    }
    public var isValid: Bool {
        let named = ["Space", "Tab", "Return", "Escape", "Delete", "ForwardDelete",
                     "Left", "Right", "Up", "Down", "Home", "End", "PageUp", "PageDown"]
        let functionKey = key.range(of: #"^F([1-9]|1[0-9]|20)$"#, options: .regularExpression) != nil
        return !key.isEmpty && key == Self.canonicalKey(key) &&
            (key.count == 1 || named.contains(key) || functionKey) &&
            key.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } &&
            modifiers == Modifier.allCases.filter { modifiers.contains($0) }
    }
}

public enum ShortcutParseError: LocalizedError {
    case invalid
    public var errorDescription: String? {
        "키 조합을 확인해 주세요. 예: ⌘⇧4 또는 Control+Option+K. 순서는 ‘ → ’로 구분합니다."
    }
}

public enum KeySequence {
    public static func parse(_ input: String) throws -> [KeyChord] {
        // The spaced separator keeps an arrow key distinct from a multi-step sequence.
        let steps = input.components(separatedBy: " → ")
        guard !steps.isEmpty, steps.count <= 8 else { throw ShortcutParseError.invalid }
        return try steps.map { step in
            var text = step.trimmingCharacters(in: .whitespacesAndNewlines)
            var modifiers: [Modifier] = []
            for modifier in Modifier.allCases {
                if modifier != .function, text.contains(modifier.symbol) {
                    modifiers.append(modifier)
                    text = text.replacingOccurrences(of: modifier.symbol, with: "")
                }
            }
            let tokens = text.components(separatedBy: "+")
            let names: [String: Modifier] = [
                "control": .control, "ctrl": .control, "option": .option, "alt": .option,
                "shift": .shift, "command": .command, "cmd": .command,
                "function": .function, "fn": .function
            ]
            var keyTokens: [String] = []
            for token in tokens {
                let trimmed = token.trimmingCharacters(in: .whitespaces)
                if let modifier = names[trimmed.lowercased()] { modifiers.append(modifier) }
                else { keyTokens.append(trimmed) }
            }
            // A literal + key is written as "Plus", including when modifiers are present.
            guard keyTokens.count == 1, !keyTokens[0].isEmpty else { throw ShortcutParseError.invalid }
            let key = keyTokens[0].lowercased() == "plus" ? "+" : keyTokens[0]
            let chord = KeyChord(modifiers: modifiers, key: key)
            let named = ["Space", "Tab", "Return", "Escape", "Delete", "ForwardDelete",
                         "Left", "Right", "Up", "Down", "Home", "End", "PageUp", "PageDown"]
            let isFunctionKey = key.uppercased().range(of: #"^F([1-9]|1[0-9]|20)$"#, options: .regularExpression) != nil
            guard chord.isValid,
                  chord.key.count == 1 || named.contains(chord.key) || isFunctionKey
            else { throw ShortcutParseError.invalid }
            return chord
        }
    }
    public static func display(_ sequence: [KeyChord]) -> String {
        sequence.map(\.display).joined(separator: " → ")
    }
    public static func editable(_ sequence: [KeyChord]) -> String {
        sequence.map { chord in
            (chord.modifiers.map(\.rawValue) + [chord.key == "+" ? "Plus" : chord.key]).joined(separator: "+")
        }.joined(separator: " → ")
    }
}

public enum ShortcutSource: String, Codable {
    case builtin, pack, menu, user
    public var label: String {
        switch self {
        case .builtin: return "기본값"
        case .pack: return "추가된 목록"
        case .menu: return "앱 메뉴"
        case .user: return "직접 수정"
        }
    }
    var priority: Int {
        switch self { case .builtin: return 0; case .pack: return 1; case .menu: return 2; case .user: return 3 }
    }
}

public struct ShortcutEntry: Identifiable, Codable, Equatable {
    public var id: String
    /// "macOS" or an exact application bundle identifier.
    public var scope: String
    public var actionID: String
    public var title: String
    public var category: String
    public var sequence: [KeyChord]
    public var source: ShortcutSource
    public var enabled: Bool?
    public var detail: String?
    public var aliases: [String]
    public var menuPath: [String]
    public var minimumOS: Int?
    public var maximumOS: Int?
    public var sourceURL: String?

    public init(scope: String, actionID: String, title: String, category: String,
                sequence: [KeyChord], source: ShortcutSource = .builtin,
                enabled: Bool? = nil, detail: String? = nil, aliases: [String] = [],
                menuPath: [String] = [], minimumOS: Int? = nil, maximumOS: Int? = nil,
                sourceURL: String? = nil) {
        self.id = Self.identity(scope: scope, actionID: actionID)
        self.scope = scope; self.actionID = actionID; self.title = title
        self.category = category; self.sequence = sequence; self.source = source
        self.enabled = enabled; self.detail = detail; self.aliases = aliases
        self.menuPath = menuPath; self.minimumOS = minimumOS; self.maximumOS = maximumOS
        self.sourceURL = sourceURL
    }
    public static func identity(scope: String, actionID: String) -> String {
        // Length framing prevents separator collisions in arbitrary menu paths.
        "\(scope.utf8.count):\(scope)\(actionID)"
    }
    public func supports(osMajor: Int) -> Bool {
        (minimumOS.map { osMajor >= $0 } ?? true) && (maximumOS.map { osMajor <= $0 } ?? true)
    }
    public var isValid: Bool {
        !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !actionID.isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !(minimumOS != nil && maximumOS != nil && minimumOS! > maximumOS!) &&
        !sequence.isEmpty && sequence.count <= 8 &&
        sequence.allSatisfy(\.isValid) && id == Self.identity(scope: scope, actionID: actionID)
    }
}

public struct ShortcutSnapshot {
    public enum State: Equatable { case ready, partial, unavailable }
    public var entries: [ShortcutEntry]
    public var state: State
    public var message: String?
    public init(entries: [ShortcutEntry], state: State, message: String? = nil) {
        self.entries = entries; self.state = state; self.message = message
    }
}

public protocol ShortcutProvider {
    func shortcuts(for scope: String, osMajor: Int) -> [ShortcutEntry]
}

public enum ShortcutMerger {
    public static func merge(_ groups: [[ShortcutEntry]]) -> [ShortcutEntry] {
        var positions: [String: Int] = [:]
        var result: [ShortcutEntry] = []
        for entry in groups.flatMap({ $0 }) {
            if let position = positions[entry.id] {
                if entry.source.priority >= result[position].source.priority {
                    result[position] = entry
                }
            } else {
                positions[entry.id] = result.count
                result.append(entry)
            }
        }
        return result
    }
}

public struct ShortcutFilter {
    public var query = ""
    public var modifiers: Set<Modifier> = []
    public var favoritesOnly = false
    public var showLearned = false
    public init() {}
    public func apply(_ entries: [ShortcutEntry], favorites: Set<String>, learned: Set<String>) -> [ShortcutEntry] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return entries.filter { entry in
            guard showLearned || !learned.contains(entry.id),
                  !favoritesOnly || favorites.contains(entry.id),
                  modifiers.isEmpty || entry.sequence.contains(where: { modifiers.isSubset(of: Set($0.modifiers)) })
            else { return false }
            let haystack = ([entry.title, entry.category, entry.detail ?? "",
                            KeySequence.display(entry.sequence), KeySequence.editable(entry.sequence)] +
                           entry.aliases + entry.menuPath).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }.sorted { lhs, rhs in
            if favorites.contains(lhs.id) != favorites.contains(rhs.id) { return favorites.contains(lhs.id) }
            return false // Stable category/entry order is preserved below by the view.
        }
    }
}
