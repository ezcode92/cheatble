import Foundation

public struct Catalog: ShortcutProvider {
    public let entries: [ShortcutEntry]
    public init(entries: [ShortcutEntry]) throws {
        guard entries.allSatisfy(\.isValid), Set(entries.map(\.id)).count == entries.count else {
            throw CatalogError.invalid
        }
        self.entries = entries
    }
    public static func bundled() throws -> Catalog {
        // The installed .app owns its resources; never depend on a build-directory path.
        guard let url = Bundle.main.url(forResource: "Shortcuts", withExtension: "json")
                ?? Bundle.module.url(forResource: "Shortcuts", withExtension: "json") else {
            throw CatalogError.missing
        }
        return try Catalog(entries: JSONDecoder().decode([ShortcutEntry].self, from: Data(contentsOf: url)))
    }
    public func shortcuts(for scope: String, osMajor: Int) -> [ShortcutEntry] {
        entries.filter { $0.scope == scope && $0.supports(osMajor: osMajor) }
    }
    /// Only a unique explicit title alias maps a live menu item to a curated action.
    /// Identical key combinations alone never establish command identity.
    public func match(scope: String, menuTitle: String) -> ShortcutEntry? {
        let title = Self.normalizeTitle(menuTitle)
        let matches = entries.filter {
            $0.scope == scope && ([$0.title] + $0.aliases).contains { Self.normalizeTitle($0) == title }
        }
        return matches.count == 1 ? matches[0] : nil
    }
    public static func normalizeTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    public enum CatalogError: LocalizedError {
        case missing, invalid
        public var errorDescription: String? { "내장 단축키 목록을 읽을 수 없습니다. 앱을 다시 빌드해 주세요." }
    }
}
