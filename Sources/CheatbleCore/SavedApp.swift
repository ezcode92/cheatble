import Foundation

public struct SavedApp: Codable, Equatable, Identifiable {
    public var bundleIdentifier: String
    public var name: String
    public var savedAt: Date
    public var entries: [ShortcutEntry]
    public var id: String { bundleIdentifier }
    public init(bundleIdentifier: String, name: String, entries: [ShortcutEntry], savedAt: Date = Date()) {
        self.bundleIdentifier = bundleIdentifier; self.name = name; self.savedAt = savedAt
        self.entries = entries.map { value in var copy = value; copy.enabled = nil; return copy }
    }
    private enum CodingKeys: String, CodingKey { case bundleIdentifier, name, savedAt, entries }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Availability describes the live menu, never a saved or imported snapshot.
        self.init(bundleIdentifier: try values.decode(String.self, forKey: .bundleIdentifier),
                  name: try values.decode(String.self, forKey: .name),
                  entries: try values.decode([ShortcutEntry].self, forKey: .entries),
                  savedAt: try values.decode(Date.self, forKey: .savedAt))
    }
    public var isValid: Bool {
        AppScope.isValid(bundleIdentifier) && !name.isEmpty && name.count <= 300 &&
        entries.count <= 3000 && Set(entries.map(\.id)).count == entries.count &&
        entries.allSatisfy { $0.isValid && $0.scope == bundleIdentifier && $0.source == .menu }
    }
}
