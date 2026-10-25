import AppKit
import ApplicationServices
import Combine
import CheatbleCore

final class AppModel: ObservableObject {
    let catalog: Catalog
    let defaults: UserDefaults
    let storage: LibraryStorage
    let packStorage: AppPackStorage
    private let packObserver: AppPackObserver
    private let reader: AccessibilityMenuReader
    let tracker = ActiveAppTracker()
    @Published var preferences: PanelPreferences { didSet { preferences.clamped().save(to: defaults) } }
    @Published private(set) var library: LibraryDocument
    @Published private(set) var activeApp: ActiveAppContext?
    @Published private(set) var hasPermission = AXIsProcessTrusted()
    @Published private(set) var isLoading = false
    @Published private(set) var snapshot: ShortcutSnapshot?
    @Published var query = ""
    @Published var modifiers: Set<Modifier> = []
    @Published var favoritesOnly = false
    @Published var showLearned = false
    @Published var isAppPickerPresented = false
    @Published var error: String?
    @Published private(set) var storageNeedsRecovery = false
    @Published private(set) var toggleShortcut: ToggleShortcut
    @Published private(set) var toggleShortcutEnabled: Bool
    @Published private(set) var toggleShortcutRegistered = false
    @Published private(set) var toggleShortcutError: String?
    @Published private(set) var navigationShortcuts: [NavigationAction: ToggleShortcut]
    @Published private(set) var navigationEnabled: [NavigationAction: Bool]
    @Published private(set) var navigationRegistered: Set<NavigationAction> = []
    @Published private(set) var navigationErrors: [NavigationAction: String] = [:]
    @Published private(set) var packs: [AppShortcutPack] = []
    @Published private(set) var packIssues: [String] = []
    @Published private(set) var requestCopied = false
    @Published private(set) var packEntries: [ShortcutEntry] = []
    var onToggleShortcutChange: ((ToggleShortcut?) throws -> Void)?
    var onNavigationShortcutChange: ((NavigationAction, ToggleShortcut?) throws -> Void)?
    var openShortcutSettings: (() -> Void)?
    var hidePanel: (() -> Void)?
    var openSettings: (() -> Void)?
    var openEditor: ((ShortcutEntry?) -> Void)?
    var openPackImport: (() -> Void)?
    var onWindowFrame: ((CGRect?) -> Void)?
    var releaseSearchFocus: (() -> Void)?
    private var permissionTimer: Timer?
    private var refreshWork: DispatchWorkItem?
    private var menuCache: [String: ShortcutSnapshot] = [:]
    private var revision = 0
    private var deepScanInFlight = false
    private var iconCache: [String: NSImage] = [:]
    private var nameCache: [String: String] = [:]
    private let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    init(catalog: Catalog, defaults: UserDefaults = .standard, storageURL: URL? = nil) {
        self.catalog = catalog; self.defaults = defaults
        reader = AccessibilityMenuReader(catalog: catalog)
        preferences = PanelPreferences.load(from: defaults)
        toggleShortcut = ToggleShortcut.load(from: defaults)
        toggleShortcutEnabled = defaults.object(forKey: "toggle.enabled") == nil || defaults.bool(forKey: "toggle.enabled")
        navigationShortcuts = Dictionary(uniqueKeysWithValues: NavigationAction.allCases.map { ($0, $0.load(from: defaults)) })
        navigationEnabled = Dictionary(uniqueKeysWithValues: NavigationAction.allCases.map { ($0, $0.isEnabled(in: defaults)) })
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storage = LibraryStorage(url: storageURL ?? base.appendingPathComponent("Cheatble/library.json"))
        packStorage = AppPackStorage(directory: storage.url.deletingLastPathComponent().appendingPathComponent("Packs"))
        packObserver = AppPackObserver(storage: packStorage)
        do { library = try storage.load() }
        catch {
            library = LibraryDocument()
            storageNeedsRecovery = true
            self.error = "저장된 목록을 읽지 못했습니다. 원본은 보존했습니다. 설정에서 복구할 수 있습니다.\n\(error.localizedDescription)"
        }
        // Global shortcuts are registered before the asynchronous observer starts.
        // Include every installed and bundled pack in that first conflict check.
        packs = packObserver.initialValue.packs
        packEntries = packs.flatMap { (try? $0.entries()) ?? [] }
        packIssues = packObserver.initialValue.issues
    }

    var scope: String { isSystem ? "macOS" : preferences.savedScope ?? activeApp?.bundleIdentifier ?? "unknown" }
    var isSystem: Bool { preferences.selectedTab == "macOS" }
    var isFollowingActiveApp: Bool { preferences.selectedTab == "app" }
    var title: String { isSystem ? "macOS 기본 단축키" : isFollowingActiveApp ? activeApp?.name ?? "현재 앱" : appName(for: scope) }
    var selectionLabel: String { isSystem ? "macOS 기본" : isFollowingActiveApp ? "현재 앱 · 자동 전환" : "저장된 앱" }
    var scopeHint: String? {
        switch scope {
        case "web.google.search": return "Google 검색 웹 · Safari 기준"
        case "org.tmux.tmux": return "기본 prefix: Ctrl+B → 놓고 다음 키"
        default: return nil
        }
    }
    var canRequestPack: Bool { AppScope.isValid(scope) }
    var allEntries: [ShortcutEntry] {
        shortcuts(for: scope, includeLiveMenu: isFollowingActiveApp)
    }
    func shortcuts(for scope: String, includeLiveMenu: Bool = false) -> [ShortcutEntry] {
        ShortcutMerger.merge([
            catalog.shortcuts(for: scope, osMajor: osMajor),
            packEntries.filter { $0.scope == scope && $0.supports(osMajor: osMajor) },
            library.apps.first { $0.id == scope }?.entries ?? [],
            includeLiveMenu ? (snapshot?.entries.filter { $0.scope == scope } ?? []) : [],
            library.entries.filter { $0.scope == scope && $0.supports(osMajor: osMajor) }
        ])
    }
    struct SavedChoice: Identifiable {
        let id: String
        let name: String
    }
    var savedApps: [SavedChoice] {
        let scopes = Set(catalog.entries.map(\.scope) + library.entries.map(\.scope) +
                         library.apps.map(\.id) + packs.map(\.bundleIdentifier))
        return scopes.filter(AppScope.isValid).map { SavedChoice(id: $0, name: appName(for: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var selectableSavedApps: [SavedChoice] {
        savedApps.filter { $0.id != activeApp?.bundleIdentifier }
    }
    func appName(for scope: String) -> String {
        if let name = library.apps.first(where: { $0.id == scope })?.name { return name }
        if let pack = packs.first(where: { $0.bundleIdentifier == scope }) { return pack.appName }
        if activeApp?.bundleIdentifier == scope { return activeApp?.name ?? scope }
        if let name = ["com.apple.finder": "Finder", "com.apple.Safari": "Safari", "com.apple.Terminal": "Terminal"][scope] { return name }
        if let cached = nameCache[scope] { return cached }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: scope)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? scope
        nameCache[scope] = name
        return name
    }
    func icon(for scope: String) -> NSImage? {
        if activeApp?.bundleIdentifier == scope { return activeApp?.icon }
        if let cached = iconCache[scope] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: scope).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? fallbackIcon(for: scope)
        iconCache[scope] = icon
        return icon
    }
    private func fallbackIcon(for scope: String) -> NSImage? {
        let symbols = ["org.tmux.tmux": "terminal", "com.cmuxterm.app": "rectangle.split.2x2",
                       "com.microsoft.Excel": "tablecells", "com.microsoft.Word": "doc.text",
                       "com.microsoft.Powerpoint": "rectangle.on.rectangle"]
        guard scope == "web.google.search" || symbols[scope] != nil else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: appName(for: scope))
        }
        return NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor(white: 0.24, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
            if scope == "web.google.search" {
                let text = NSAttributedString(string: "G", attributes: [.font: NSFont.systemFont(ofSize: 24, weight: .bold),
                    .foregroundColor: NSColor.white])
                text.draw(at: NSPoint(x: (32 - text.size().width) / 2, y: (32 - text.size().height) / 2))
            } else if let name = symbols[scope],
                      let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                        .withSymbolConfiguration(.init(paletteColors: [.white])) {
                symbol.draw(in: rect.insetBy(dx: 6, dy: 6))
            }
            return true
        }
    }
    var visibleEntries: [ShortcutEntry] {
        var filter = ShortcutFilter()
        filter.query = query; filter.modifiers = modifiers
        filter.favoritesOnly = favoritesOnly; filter.showLearned = showLearned
        return filter.apply(allEntries, favorites: library.favorites, learned: library.learned)
    }
    struct Group: Identifiable {
        var id: String
        var title: String
        var entries: [ShortcutEntry]
    }
    var groups: [Group] {
        let visible = visibleEntries
        var ordered: [String] = []
        var grouped: [String: [ShortcutEntry]] = [:]
        for entry in visible {
            let category = library.favorites.contains(entry.id) ? "즐겨찾기" : entry.category
            if grouped[category] == nil { ordered.append(category) }
            grouped[category, default: []].append(entry)
        }
        if let index = ordered.firstIndex(of: "즐겨찾기") {
            ordered.remove(at: index); ordered.insert("즐겨찾기", at: 0)
        }
        return ordered.map { Group(id: scope + "|" + $0, title: $0, entries: grouped[$0] ?? []) }
    }
    var learnedCount: Int { allEntries.filter { library.learned.contains($0.id) }.count }
    var statusText: String {
        if isSystem { return "기본값 기준 · 직접 수정 가능" }
        if !isFollowingActiveApp { return "저장된 목록 · 앱을 실행하지 않고 볼 수 있어요" }
        if isLoading { return "앱 메뉴를 읽고 있어요…" }
        if !hasPermission { return "내장 목록 · 메뉴 읽기 권한 필요" }
        if let message = snapshot?.message { return message }
        return "앱 메뉴 + 기본 목록"
    }

    func start() {
        packObserver.onChange = { [weak self] loaded in
            guard let self else { return }
            self.packs = loaded.packs
            self.packEntries = loaded.packs.flatMap { (try? $0.entries()) ?? [] }
            self.packIssues = loaded.issues
            self.nameCache.removeAll(); self.iconCache.removeAll()
            self.scheduleRefresh()
        }
        packObserver.start()
        tracker.onAppChange = { [weak self] context in
            guard let self else { return }
            self.reader.cancel(); self.revision += 1
            self.deepScanInFlight = false
            self.activeApp = context
            self.snapshot = self.menuCache[context.cacheKey]
            if self.isFollowingActiveApp { self.query = ""; self.modifiers = []; self.requestCopied = false }
            self.onWindowFrame?(nil)
            self.scheduleRefresh()
        }
        tracker.onWindowChange = { [weak self] frame in
            self?.activeApp?.accessibilityWindowFrame = frame
            self?.onWindowFrame?(frame)
            self?.scheduleRefresh()
        }
        tracker.onMenuChange = { [weak self] in self?.scheduleRefresh() }
        tracker.start()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = AXIsProcessTrusted()
            if granted != self.hasPermission {
                self.hasPermission = granted
                self.reader.cancel(); self.revision += 1
                self.deepScanInFlight = false
                if !granted { self.snapshot = nil; self.menuCache.removeAll(); self.isLoading = false }
                self.tracker.permissionsChanged()
                self.scheduleRefresh()
            }
        }
    }
    func stop() {
        packObserver.stop()
        permissionTimer?.invalidate(); refreshWork?.cancel(); reader.cancel(); tracker.stop()
    }
    func activateToggleShortcut() {
        do {
            try validateToggleShortcut(toggleShortcut, enabled: toggleShortcutEnabled)
            try onToggleShortcutChange?(toggleShortcutEnabled ? toggleShortcut : nil)
            toggleShortcutRegistered = toggleShortcutEnabled
            toggleShortcutError = nil
        } catch { toggleShortcutRegistered = false; toggleShortcutError = error.localizedDescription }
    }
    @discardableResult
    func updateToggleShortcut(_ text: String, enabled: Bool = true) -> Bool {
        do {
            let next = try ToggleShortcut.parse(text)
            try validateToggleShortcut(next, enabled: enabled)
            try onToggleShortcutChange?(enabled ? next : nil)
            toggleShortcut = next; toggleShortcutEnabled = enabled; toggleShortcutRegistered = enabled
            next.save(to: defaults); defaults.set(enabled, forKey: "toggle.enabled")
            toggleShortcutError = nil
            return true
        } catch { toggleShortcutError = error.localizedDescription; return false }
    }
    private func validateToggleShortcut(_ shortcut: ToggleShortcut, enabled: Bool) throws {
        guard enabled else { return }
        if let action = NavigationAction.allCases.first(where: {
            navigationEnabled[$0] == true && navigationShortcuts[$0] == shortcut
        }) { throw shortcutError("‘\(action.title)’에 이미 지정한 단축키입니다.") }
        try validateCatalogShortcut(shortcut)
    }
    private func validateCatalogShortcut(_ shortcut: ToggleShortcut) throws {
        if let conflict = (catalog.entries + packEntries + (snapshot?.entries ?? []) + library.entries + library.apps.flatMap(\.entries)).first(where: {
            $0.sequence.first == shortcut.chord
        }) {
            throw shortcutError("‘\(conflict.title)’에서 사용 중인 키 조합입니다. 다른 조합을 선택해 주세요.")
        }
    }
    private func shortcutError(_ message: String) -> NSError {
        NSError(domain: "Cheatble.Shortcut", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    func activateNavigationShortcuts() {
        for action in NavigationAction.allCases {
            _ = updateNavigationShortcut(action, text: KeySequence.editable([navigationShortcuts[action]!.chord]),
                                         enabled: navigationEnabled[action] == true)
        }
    }
    @discardableResult
    func updateNavigationShortcut(_ action: NavigationAction, text: String, enabled: Bool = true) -> Bool {
        do {
            let next = try ToggleShortcut.parse(text)
            if enabled {
                if toggleShortcutEnabled && toggleShortcut == next {
                    throw shortcutError("시트 열기·닫기에 이미 지정한 단축키입니다.")
                }
                if let other = NavigationAction.allCases.first(where: {
                    $0 != action && navigationEnabled[$0] == true && navigationShortcuts[$0] == next
                }) { throw shortcutError("‘\(other.title)’에 이미 지정한 단축키입니다.") }
                try validateCatalogShortcut(next)
            }
            try onNavigationShortcutChange?(action, enabled ? next : nil)
            navigationShortcuts[action] = next; navigationEnabled[action] = enabled
            if enabled { navigationRegistered.insert(action) } else { navigationRegistered.remove(action) }
            defaults.set(KeySequence.editable([next.chord]), forKey: action.defaultsKey)
            defaults.set(enabled, forKey: action.enabledKey)
            navigationErrors[action] = nil
            return true
        } catch { navigationErrors[action] = error.localizedDescription; return false }
    }
    func navigationHint(_ action: NavigationAction) -> String {
        navigationRegistered.contains(action) ? " · " + navigationShortcuts[action]!.chord.display : ""
    }
    func selectTab(_ tab: String) {
        preferences.selectedTab = tab
        if let saved = preferences.savedScope { defaults.set(saved, forKey: "navigation.lastSavedScope") }
        isAppPickerPresented = false
        query = ""; modifiers = []
        requestCopied = false
        releaseSearchFocus?()
    }
    func scheduleRefresh() {
        guard !deepScanInFlight else { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    func refresh(deep: Bool = false) {
        guard let context = activeApp, hasPermission else { isLoading = false; return }
        refreshWork?.cancel()
        deepScanInFlight = deep
        revision += 1
        let request = revision
        isLoading = true
        reader.read(pid: context.pid, scope: context.bundleIdentifier, deep: deep,
                    supplementalEntries: packEntries) { [weak self] result in
            guard let self, self.revision == request, self.activeApp?.pid == context.pid else { return }
            self.isLoading = false
            self.deepScanInFlight = false
            if result.entries.isEmpty, let cached = self.menuCache[context.cacheKey], !cached.entries.isEmpty {
                self.snapshot = .init(entries: cached.entries, state: .partial,
                                      message: "메뉴를 갱신하지 못해 이전에 읽은 목록을 표시합니다.")
            } else {
                self.snapshot = result
                if !result.entries.isEmpty {
                    if self.menuCache.count >= 32 { self.menuCache.removeAll() }
                    self.menuCache[context.cacheKey] = result
                    if AppScope.isValid(context.bundleIdentifier) {
                        self.commit {
                            $0.rememberApp(bundleIdentifier: context.bundleIdentifier, name: context.name,
                                entries: result.entries, partial: result.state == .partial)
                        }
                    }
                }
            }
        }
    }
    func saveCurrentApp() {
        guard let context = activeApp, AppScope.isValid(context.bundleIdentifier) else { return }
        commit {
            $0.rememberApp(bundleIdentifier: context.bundleIdentifier, name: context.name,
                           entries: snapshot?.entries ?? [], partial: true)
        }
    }
    func reloadPacks() { packObserver.refresh() }
    func importPack(from url: URL) {
        do {
            let pack = try AppShortcutPack.read(url)
            try packStorage.install(pack)
            reloadPacks()
            selectTab("saved:" + pack.bundleIdentifier)
        } catch { self.error = "단축키 팩을 가져오지 못했습니다.\n\(error.localizedDescription)" }
    }
    func openPacksFolder() {
        do {
            try FileManager.default.createDirectory(at: packStorage.directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(packStorage.directory)
        } catch { self.error = error.localizedDescription }
    }
    func additionRequest() -> AppShortcutRequest? {
        guard canRequestPack else { return nil }
        let version = NSWorkspace.shared.urlForApplication(withBundleIdentifier: scope)
            .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
        return AppShortcutRequest(bundleIdentifier: scope, appName: appName(for: scope), appVersion: version)
    }
    func copyAdditionRequest() {
        guard let request = additionRequest() else { return }
        do {
            let directory = storage.url.deletingLastPathComponent().appendingPathComponent("Requests")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(request).write(to: directory.appendingPathComponent(scope + ".json"), options: .atomic)
            let installed = "/Applications/Cheatble.app/Contents/MacOS/Cheatble"
            let executable = FileManager.default.isExecutableFile(atPath: installed) ? installed :
                Bundle.main.executableURL?.path ?? installed
            NSPasteboard.general.clearContents()
            requestCopied = NSPasteboard.general.setString(request.prompt(executablePath: executable), forType: .string)
        } catch { self.error = "추가 요청을 만들지 못했습니다.\n\(error.localizedDescription)" }
    }
    func requestPermission() {
        // Prompt only after an explicit user gesture, never during normal refresh.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    func toggleFavorite(_ entry: ShortcutEntry) {
        commit { document in
            if !document.favorites.insert(entry.id).inserted { document.favorites.remove(entry.id) }
        }
    }
    func toggleLearned(_ entry: ShortcutEntry) {
        commit { document in
            if !document.learned.insert(entry.id).inserted { document.learned.remove(entry.id) }
        }
    }
    func toggleGroup(_ id: String) {
        commit { document in
            if !document.collapsedGroups.insert(id).inserted { document.collapsedGroups.remove(id) }
        }
    }
    func resetLearned() { commit { $0.learned.removeAll() } }
    @discardableResult
    func saveEntry(_ entry: ShortcutEntry) -> Bool {
        guard entry.scope == "macOS" || AppScope.isValid(entry.scope) else {
            error = "대상은 macOS 또는 앱의 번들 ID를 입력해 주세요. 예: com.apple.Safari"
            return false
        }
        return commit { document in
            document.entries.removeAll { $0.id == entry.id }
            document.entries.append(entry)
        }
    }
    func removeEntry(_ entry: ShortcutEntry) {
        // A curated/menu entry reappears when its user override is removed.
        commit { $0.entries.removeAll { $0.id == entry.id } }
    }
    @discardableResult
    private func commit(_ change: (inout LibraryDocument) -> Void) -> Bool {
        guard !storageNeedsRecovery else {
            error = "기존 목록을 보존하기 위해 저장을 중지했습니다. 설정에서 복구해 주세요."
            return false
        }
        var next = library
        change(&next)
        guard next != library else { return true }
        do { try storage.save(next); library = next; return true }
        catch { self.error = "변경 사항을 저장하지 못했습니다.\n\(error.localizedDescription)"; return false }
    }
    func importLibrary(from url: URL) {
        do {
            let imported = try LibraryStorage.read(url)
            let merged = try library.merging(imported)
            commit { $0 = merged }
        } catch { self.error = "목록을 가져오지 못했습니다.\n\(error.localizedDescription)" }
    }
    func exportLibrary(to url: URL) {
        do { try LibraryStorage(url: url).save(library) }
        catch { self.error = "목록을 내보내지 못했습니다.\n\(error.localizedDescription)" }
    }
    func recoverLibrary() {
        do {
            if FileManager.default.fileExists(atPath: storage.url.path) {
                let backup = storage.url.deletingLastPathComponent().appendingPathComponent("library-backup-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: storage.url, to: backup)
            }
            try storage.save(library)
            storageNeedsRecovery = false; error = nil
        } catch { self.error = "원본 백업 또는 복구에 실패했습니다.\n\(error.localizedDescription)" }
    }
}
