import Foundation

public enum AppScope {
    public static func isValid(_ value: String) -> Bool {
        value.count <= 255 && value.contains(".") && !value.hasPrefix("process.") &&
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }
}

public struct AppShortcutPack: Codable, Equatable {
    public var schemaVersion = 1
    public var bundleIdentifier: String
    public var appName: String
    public var shortcuts: [Item]

    public struct Item: Codable, Equatable {
        public var id: String
        public var title: String
        public var category: String
        public var keys: String
        public var detail: String?
        public var aliases: [String]?
        public var sourceURL: String?
        public init(id: String, title: String, category: String, keys: String,
                    detail: String? = nil, aliases: [String]? = nil, sourceURL: String? = nil) {
            self.id = id; self.title = title; self.category = category; self.keys = keys
            self.detail = detail; self.aliases = aliases; self.sourceURL = sourceURL
        }
    }
    public init(bundleIdentifier: String, appName: String, shortcuts: [Item]) {
        self.bundleIdentifier = bundleIdentifier; self.appName = appName; self.shortcuts = shortcuts
    }
    public func entries() throws -> [ShortcutEntry] {
        guard schemaVersion == 1 else { throw PackError.version }
        guard AppScope.isValid(bundleIdentifier), !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              appName.count <= 120, !shortcuts.isEmpty, shortcuts.count <= 1000,
              Set(shortcuts.map(\.id)).count == shortcuts.count else { throw PackError.invalid }
        return try shortcuts.map { item in
            guard !item.id.isEmpty, item.id.count <= 160,
                  item.id.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
                  item.title.count <= 300, item.category.count <= 120 else { throw PackError.invalid }
            if let source = item.sourceURL {
                guard let url = URL(string: source), ["http", "https"].contains(url.scheme ?? ""), url.host != nil
                else { throw PackError.invalid }
            }
            let entry = ShortcutEntry(scope: bundleIdentifier, actionID: item.id,
                title: item.title, category: item.category, sequence: try KeySequence.parse(item.keys),
                source: .pack, detail: item.detail, aliases: item.aliases ?? [], sourceURL: item.sourceURL)
            guard entry.isValid else { throw PackError.invalid }
            return entry
        }
    }
    public static func read(_ url: URL) throws -> AppShortcutPack {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_000_000 else { throw PackError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= 1_000_000 else { throw PackError.tooLarge }
        let pack = try JSONDecoder().decode(Self.self, from: data)
        _ = try pack.entries()
        return pack
    }
    public static var example: AppShortcutPack {
        AppShortcutPack(bundleIdentifier: "com.example.app", appName: "앱 이름",
            shortcuts: [.init(id: "example.action", title: "실제 동작 이름으로 교체",
                              category: "기본", keys: "Command+Shift+K",
                              detail: "형식 예시입니다. 공식 문서에서 확인한 실제 단축키로 교체하세요.")])
    }
}

public enum PackError: LocalizedError {
    case version, invalid, tooLarge
    public var errorDescription: String? {
        switch self {
        case .version: return "지원하지 않는 단축키 팩 버전입니다."
        case .invalid: return "단축키 팩의 앱 ID, 이름, 동작 ID, 키 조합 또는 출처를 확인해 주세요."
        case .tooLarge: return "단축키 팩은 1MB, 항목 1,000개 이하여야 합니다."
        }
    }
}

public struct AppPackStorage {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static func bundled() -> Loaded {
        guard let directory = Bundle.main.url(forResource: "Packs", withExtension: nil)
                ?? Bundle.module.url(forResource: "Packs", withExtension: nil) else {
            return Loaded(issues: ["내장 단축키 팩을 찾을 수 없습니다."])
        }
        return AppPackStorage(directory: directory).load()
    }
    /// User packs replace the bundled pack for that scope; manual library edits remain higher priority.
    public static func merge(bundled: Loaded, installed: Loaded) -> Loaded {
        var packs = Dictionary(uniqueKeysWithValues: bundled.packs.map { ($0.bundleIdentifier, $0) })
        for pack in installed.packs { packs[pack.bundleIdentifier] = pack }
        return Loaded(packs: packs.values.sorted { $0.bundleIdentifier < $1.bundleIdentifier },
                      issues: bundled.issues + installed.issues)
    }
    public static var standard: AppPackStorage {
        AppPackStorage(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cheatble/Packs", isDirectory: true))
    }
    @discardableResult
    public func install(_ pack: AppShortcutPack) throws -> URL {
        _ = try pack.entries()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pack)
        guard data.count <= 1_000_000 else { throw PackError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(pack.bundleIdentifier + ".json")
        try data.write(to: destination, options: .atomic)
        return destination
    }
    public struct Loaded {
        public var packs: [AppShortcutPack] = []
        public var issues: [String] = []
    }
    public func load() -> Loaded {
        var result = Loaded()
        guard FileManager.default.fileExists(atPath: directory.path) else { return result }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            if files.count > 128 { result.issues.append("단축키 팩은 128개까지 읽습니다.") }
            var totalSize = 0
            var scopes = Set<String>()
            for file in files.prefix(128) {
                do {
                    totalSize += try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard totalSize <= 10_000_000 else { result.issues.append("팩 전체 크기가 10MB를 넘었습니다."); break }
                    let pack = try AppShortcutPack.read(file)
                    guard scopes.insert(pack.bundleIdentifier).inserted else {
                        result.issues.append("\(file.lastPathComponent): 같은 앱의 팩이 중복되어 있습니다.")
                        continue
                    }
                    result.packs.append(pack)
                } catch { result.issues.append("\(file.lastPathComponent): \(error.localizedDescription)") }
            }
        } catch { result.issues.append(error.localizedDescription) }
        return result
    }
}

public struct AppShortcutRequest: Codable {
    public var schemaVersion = 1
    public var bundleIdentifier: String
    public var appName: String
    public var appVersion: String?
    public var createdAt = Date()
    public init(bundleIdentifier: String, appName: String, appVersion: String?) {
        self.bundleIdentifier = bundleIdentifier; self.appName = appName; self.appVersion = appVersion
    }
    public func prompt(executablePath: String) -> String {
        """
        Cheatble에 \(appName)의 macOS 단축키를 추가해줘.
        앱 번들 ID: \(bundleIdentifier)
        앱 버전: \(appVersion ?? "확인 필요")
        공식 문서나 실제 앱 메뉴에서 확인한 내용으로 한국어 단축키 팩을 만들어줘. 확인되지 않은 키는 추측하지 마.
        팩 형식은 아래 실행 파일의 --pack-example 옵션으로 확인할 수 있어.
        실행 파일: \(executablePath)
        완성한 JSON 파일은 이 실행 파일에 --install-pack <JSON 파일 경로>로 설치해줘.
        서버나 API 키 없이 로컬 파일로 추가하고, 내가 직접 수정한 기존 항목은 유지해줘.
        """
    }
}
