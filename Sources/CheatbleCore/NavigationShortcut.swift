import Foundation

public enum NavigationAction: String, CaseIterable, Identifiable {
    case activeApp, system, savedApps
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .activeApp: return "현재 앱 자동 전환"
        case .system: return "macOS 단축키"
        case .savedApps: return "저장된 앱 선택"
        }
    }
    public var defaultsKey: String { "navigation.\(rawValue).shortcut" }
    public var enabledKey: String { "navigation.\(rawValue).enabled" }
    public var standard: ToggleShortcut {
        let key: String
        switch self {
        case .activeApp: key = "J"
        case .system: key = "K"
        case .savedApps: key = ";"
        }
        return try! ToggleShortcut.parse("Control+Option+Command+" + key)
    }
    public func load(from defaults: UserDefaults) -> ToggleShortcut {
        guard let text = defaults.string(forKey: defaultsKey),
              let shortcut = try? ToggleShortcut.parse(text) else { return standard }
        return shortcut
    }
    public func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) == nil || defaults.bool(forKey: enabledKey)
    }
}
