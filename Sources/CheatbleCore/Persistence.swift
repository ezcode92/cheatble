import Foundation

public struct LibraryDocument: Codable, Equatable {
    public var schemaVersion = 1
    public var favorites: Set<String> = []
    public var learned: Set<String> = []
    public var collapsedGroups: Set<String> = []
    public var entries: [ShortcutEntry] = []
    public var apps: [SavedApp] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case schemaVersion, favorites, learned, collapsedGroups, entries, apps }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        favorites = try values.decode(Set<String>.self, forKey: .favorites)
        learned = try values.decode(Set<String>.self, forKey: .learned)
        collapsedGroups = try values.decode(Set<String>.self, forKey: .collapsedGroups)
        entries = try values.decode([ShortcutEntry].self, forKey: .entries)
        apps = try values.decodeIfPresent([SavedApp].self, forKey: .apps) ?? []
    }

    public func validated() throws -> LibraryDocument {
        guard schemaVersion == 1 else { throw LibraryError.unsupportedVersion }
        guard entries.count <= 10_000,
              entries.allSatisfy({ $0.isValid && $0.source == .user && ($0.scope == "macOS" || AppScope.isValid($0.scope)) }),
              Set(entries.map(\.id)).count == entries.count,
              apps.count <= 128, apps.allSatisfy(\.isValid),
              Set(apps.map(\.id)).count == apps.count,
              apps.reduce(0, { $0 + $1.entries.count }) <= 10_000 else { throw LibraryError.invalid }
        return self
    }
    public func merging(_ imported: LibraryDocument) throws -> LibraryDocument {
        _ = try imported.validated()
        var result = self
        result.favorites.formUnion(imported.favorites)
        result.learned.formUnion(imported.learned)
        result.collapsedGroups.formUnion(imported.collapsedGroups)
        result.entries = ShortcutMerger.merge([entries, imported.entries])
        for app in imported.apps {
            if let index = result.apps.firstIndex(where: { $0.id == app.id }) { result.apps[index] = app }
            else { result.apps.append(app) }
        }
        return try result.validated()
    }
    public mutating func rememberApp(bundleIdentifier: String, name: String, entries: [ShortcutEntry], partial: Bool = false) {
        let old = apps.first { $0.id == bundleIdentifier }
        let menuEntries = entries.filter { $0.source == .menu && $0.scope == bundleIdentifier }
        let merged = partial ? ShortcutMerger.merge([old?.entries ?? [], menuEntries]) : menuEntries
        let next = SavedApp(bundleIdentifier: bundleIdentifier, name: name, entries: merged)
        guard next.isValid, old?.entries != next.entries || old?.name != name else { return }
        apps.removeAll { $0.id == bundleIdentifier }
        apps.append(next)
        while apps.count > 128 || apps.reduce(0, { $0 + $1.entries.count }) > 10_000 {
            guard let oldest = apps.indices.min(by: { apps[$0].savedAt < apps[$1].savedAt }) else { break }
            apps.remove(at: oldest)
        }
    }
}

public enum LibraryError: LocalizedError {
    case unsupportedVersion, invalid, tooLarge
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "지원하지 않는 목록 버전입니다. 원본 파일은 변경하지 않았습니다."
        case .invalid: return "단축키 목록의 형식이나 중복 항목을 확인해 주세요."
        case .tooLarge: return "가져올 목록은 5MB 이하의 JSON 파일이어야 합니다."
        }
    }
}

public struct LibraryStorage {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> LibraryDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryDocument() }
        return try Self.read(url)
    }
    public static func read(_ url: URL) throws -> LibraryDocument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 5_000_000 else { throw LibraryError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= 5_000_000 else { throw LibraryError.tooLarge }
        return try JSONDecoder().decode(LibraryDocument.self, from: data).validated()
    }
    public func save(_ document: LibraryDocument) throws {
        _ = try document.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 5_000_000 else { throw LibraryError.tooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public struct PanelPreferences: Equatable {
    public var width: Double = 360
    public var height: Double = 640
    public var backgroundOpacity: Double = 0.85
    public var selectedTab = "app"
    public var position: CGPoint?
    public var savedScope: String? {
        guard selectedTab.hasPrefix("saved:") else { return nil }
        let scope = String(selectedTab.dropFirst(6))
        return AppScope.isValid(scope) ? scope : nil
    }
    public init() {}
    public func clamped() -> PanelPreferences {
        var result = self
        result.width = width.isFinite ? min(2400, max(240, width)) : 360
        result.height = height.isFinite ? max(320, min(1400, height)) : 640
        result.backgroundOpacity = backgroundOpacity.isFinite ? min(1, max(0.2, backgroundOpacity)) : 0.85
        result.selectedTab = selectedTab == "macOS" || savedScope != nil ? selectedTab : "app"
        if let position, !position.x.isFinite || !position.y.isFinite { result.position = nil }
        return result
    }
    public static func load(from defaults: UserDefaults) -> PanelPreferences {
        var p = PanelPreferences()
        if defaults.object(forKey: "panel.width") != nil { p.width = defaults.double(forKey: "panel.width") }
        if defaults.object(forKey: "panel.height") != nil { p.height = defaults.double(forKey: "panel.height") }
        if defaults.object(forKey: "panel.backgroundOpacity") != nil {
            p.backgroundOpacity = defaults.double(forKey: "panel.backgroundOpacity")
        }
        p.selectedTab = defaults.string(forKey: "panel.tab") ?? "app"
        if defaults.object(forKey: "panel.x") != nil, defaults.object(forKey: "panel.y") != nil {
            p.position = CGPoint(x: defaults.double(forKey: "panel.x"), y: defaults.double(forKey: "panel.y"))
        }
        return p.clamped()
    }
    public func save(to defaults: UserDefaults) {
        let p = clamped()
        defaults.set(p.width, forKey: "panel.width")
        defaults.set(p.height, forKey: "panel.height")
        defaults.set(p.backgroundOpacity, forKey: "panel.backgroundOpacity")
        defaults.set(p.selectedTab, forKey: "panel.tab")
        if let position = p.position {
            defaults.set(position.x, forKey: "panel.x"); defaults.set(position.y, forKey: "panel.y")
        } else {
            defaults.removeObject(forKey: "panel.x"); defaults.removeObject(forKey: "panel.y")
        }
    }
}
