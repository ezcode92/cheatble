import Foundation
import Testing
import CoreGraphics
@testable import CheatbleCore

@Suite(.serialized)
final class CheatbleCoreTests {
    private var temporaryDirectories: [URL] = []
    deinit { temporaryDirectories.forEach { try? FileManager.default.removeItem(at: $0) } }
    private func entry(_ action: String = "copy", scope: String = "macOS", source: ShortcutSource = .builtin,
                       keys: String = "Command+C") throws -> ShortcutEntry {
        ShortcutEntry(scope: scope, actionID: action, title: "복사", category: "기본",
                      sequence: try KeySequence.parse(keys), source: source, aliases: ["Copy"])
    }
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cheatble-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("library.json")
    }

    @Test func testBundledCatalogWorksWithoutAppOrPermission() throws {
        let catalog = try Catalog.bundled()
        #expect(catalog.entries.count == 126)
        #expect(catalog.shortcuts(for: "macOS", osMajor: 13).count == 68)
        #expect(catalog.shortcuts(for: "macOS", osMajor: 15).count == 68)
        #expect(catalog.shortcuts(for: "com.apple.finder", osMajor: 15).count == 26)
        #expect(catalog.shortcuts(for: "com.apple.Safari", osMajor: 15).count == 16)
        #expect(catalog.shortcuts(for: "com.apple.Terminal", osMajor: 15).count == 16)
        #expect(catalog.shortcuts(for: "unknown", osMajor: 15).isEmpty)
        #expect(catalog.entries.allSatisfy { $0.source == .builtin && $0.sourceURL?.hasPrefix("https://support.apple.com/") == true })
        for entry in catalog.entries {
            #expect(try KeySequence.parse(KeySequence.editable(entry.sequence)) == entry.sequence)
        }
    }
    @Test func testAXModifierMaskUsesImplicitCommand() {
        #expect(Modifier.accessibilityMask(0) == [.command])
        #expect(Modifier.accessibilityMask(1) == [.shift, .command])
        #expect(Modifier.accessibilityMask(7) == [.control, .option, .shift, .command])
        #expect(Modifier.accessibilityMask(8) == [])
        #expect(Modifier.accessibilityMask(12) == [.control])
    }
    @Test func testSequencesAndArrowKeysRoundTrip() throws {
        let sequence = try KeySequence.parse("⌘⇧4 → Space")
        #expect(sequence.count == 2)
        #expect(sequence[0].modifiers == [.shift, .command])
        #expect(sequence[1].key == "Space")
        #expect(try KeySequence.parse("Control+→").first?.key == "Right")
        #expect(try KeySequence.parse("⌃→").count == 1)
        for input in ["Fn+Q", "Command+Plus", "Control+Option+F12", "Command+Shift+4 → Space", "⌘←"] {
            let parsed = try KeySequence.parse(input)
            #expect(try KeySequence.parse(KeySequence.editable(parsed)) == parsed)
        }
    }
    @Test func testInvalidKeyInputRejected() {
        for input in ["", "Command", "Command+", "A+B", "F21", "nonsense", "Command+K → ", "\n", "⌘++"] {
            #expect(throws: (any Error).self) { try KeySequence.parse(input) }
        }
        #expect(throws: (any Error).self) { try KeySequence.parse(Array(repeating: "A", count: 9).joined(separator: " → ")) }
    }
    @Test func testMergePriorityAndDistinctActionsWithSameKey() throws {
        let builtin = try entry()
        let live = try entry(source: .menu, keys: "Control+C")
        let user = try entry(source: .user, keys: "Command+Option+C")
        let other = try entry("another", keys: "Command+C")
        let otherApp = try entry(scope: "com.apple.finder")
        let merged = ShortcutMerger.merge([[user, other], [live, otherApp], [builtin]])
        #expect(merged.count == 3)
        #expect(merged.first == user)
        #expect(ShortcutMerger.merge([[builtin], [live]]).first == live)
    }
    @Test func testIdentityUsesScopeAndStableActionRatherThanTitleOrKey() throws {
        let original = try entry()
        var renamed = original
        renamed.title = "Copy"; renamed.sequence = try KeySequence.parse("Control+C")
        #expect(original.id == renamed.id)
        #expect(ShortcutEntry.identity(scope: "a", actionID: "bc") != ShortcutEntry.identity(scope: "ab", actionID: "c"))
    }
    @Test func testCatalogOnlyMatchesUniqueExplicitAliasesWithinScope() throws {
        let copy = try entry()
        var other = try entry("second")
        other.aliases = ["Copy"]; other.title = "다른 동작"
        #expect(try Catalog(entries: [copy]).match(scope: "macOS", menuTitle: " Copy… ")?.id == copy.id)
        #expect(try Catalog(entries: [copy]).match(scope: "another.app", menuTitle: "Copy") == nil)
        #expect(try Catalog(entries: [copy, other]).match(scope: "macOS", menuTitle: "Copy") == nil)
        #expect(throws: (any Error).self) { try Catalog(entries: [copy, copy]) }
    }
    @Test func testSearchModifiersFavoritesAndLearnedCompose() throws {
        let first = try entry()
        var second = try entry("other", keys: "Command+Shift+V")
        second.title = "스타일 붙여넣기"; second.detail = "현재 서식"; second.menuPath = ["Edit"]; second.aliases = ["Paste"]
        var filter = ShortcutFilter()
        filter.query = "copy"
        #expect(filter.apply([first, second], favorites: [], learned: []).map(\.id) == [first.id])
        filter.query = "서식 Edit"; filter.modifiers = [.shift, .command]
        #expect(filter.apply([first, second], favorites: [], learned: []).map(\.id) == [second.id])
        filter.favoritesOnly = true
        #expect(filter.apply([first, second], favorites: [], learned: []).isEmpty)
        #expect(filter.apply([first, second], favorites: [second.id], learned: [second.id]).isEmpty)
        filter.showLearned = true
        #expect(filter.apply([first, second], favorites: [second.id], learned: [second.id]).count == 1)
    }
    @Test func testOSVersionGating() throws {
        var scoped = try entry()
        scoped.minimumOS = 14; scoped.maximumOS = 15
        let catalog = try Catalog(entries: [scoped])
        #expect(catalog.shortcuts(for: "macOS", osMajor: 13).isEmpty)
        #expect(catalog.shortcuts(for: "macOS", osMajor: 15).count == 1)
        #expect(catalog.shortcuts(for: "macOS", osMajor: 16).isEmpty)
        scoped.minimumOS = 16
        #expect(!(scoped.isValid))
    }
    @Test func testJSONRoundTripAndImportPriority() throws {
        let storage = LibraryStorage(url: try temporaryURL())
        #expect(try storage.load() == LibraryDocument())
        var document = LibraryDocument()
        let original = try entry(source: .user)
        document.entries = [original]; document.favorites = [original.id]; document.learned = [original.id]
        document.collapsedGroups = ["macOS|기본"]
        try storage.save(document)
        #expect(try storage.load() == document)
        var imported = LibraryDocument()
        imported.entries = [try entry(source: .user, keys: "Control+C")]
        imported.favorites = ["new"]
        let merged = try document.merging(imported)
        #expect(merged.entries.count == 1)
        #expect(merged.entries[0].sequence == imported.entries[0].sequence)
        #expect(merged.favorites == [original.id, "new"])
        #expect(merged.learned == document.learned)
    }
    @Test func testCorruptJSONIsPreserved() throws {
        let url = try temporaryURL()
        let bytes = Data("{malformed original".utf8)
        try bytes.write(to: url)
        #expect(throws: (any Error).self) { try LibraryStorage(url: url).load() }
        #expect(try Data(contentsOf: url) == bytes)
    }
    @Test func testInvalidImportAndSaveDoNotReplaceGoodFile() throws {
        let url = try temporaryURL()
        let storage = LibraryStorage(url: url)
        try storage.save(LibraryDocument())
        let original = try Data(contentsOf: url)
        var invalid = LibraryDocument()
        invalid.schemaVersion = 2
        #expect(throws: (any Error).self) { try storage.save(invalid) }
        #expect(try Data(contentsOf: url) == original)
        invalid.schemaVersion = 1
        invalid.entries = [try entry(source: .builtin)]
        #expect(throws: (any Error).self) { try invalid.validated() }
        invalid.entries = [try entry(source: .user), try entry(source: .user)]
        #expect(throws: (any Error).self) { try invalid.validated() }
        invalid.entries = [try entry(source: .user)]
        invalid.entries[0].sequence[0].key = "not a key"
        #expect(throws: (any Error).self) { try invalid.validated() }
        invalid.entries = [try entry(source: .user)]
        invalid.entries[0].id = "forged"
        #expect(throws: (any Error).self) { try invalid.validated() }
    }
    @Test func testInvalidUserScopeCannotReplaceSavedLibrary() throws {
        let url = try temporaryURL()
        let storage = LibraryStorage(url: url)
        var good = LibraryDocument()
        good.entries = [try entry(source: .user), try entry(scope: "com.example.app", source: .user)]
        try storage.save(good)
        let bytes = try Data(contentsOf: url)
        for scope in ["Safari", "", "process.123", "../invalid", "com.example app"] {
            var invalid = LibraryDocument()
            invalid.entries = [try entry(scope: scope, source: .user)]
            #expect(throws: (any Error).self) { try storage.save(invalid) }
            #expect(try Data(contentsOf: url) == bytes)
            let importURL = url.deletingLastPathComponent().appendingPathComponent("import.json")
            try JSONEncoder().encode(invalid).write(to: importURL)
            #expect(throws: (any Error).self) { try LibraryStorage.read(importURL) }
        }
        #expect(try storage.load() == good)
    }

    @Test func testOversizedImportRejected() throws {
        let url = try temporaryURL()
        try Data(repeating: 32, count: 5_000_001).write(to: url)
        #expect(throws: (any Error).self) { try LibraryStorage.read(url) }
    }
    @Test func testPanelAnchorsAndClampsWithinNegativeCoordinateDisplay() {
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let frame = PanelGeometry.frame(in: screen, requestedSize: CGSize(width: 360, height: 640))
        #expect(frame.maxX == -16)
        #expect(frame.maxY == 864)
        #expect(screen.contains(frame))
        let oversized = PanelGeometry.frame(in: screen, requestedSize: CGSize(width: 5000, height: 5000))
        #expect(screen.contains(oversized))
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 150)
        #expect(tiny.contains(PanelGeometry.frame(in: tiny, requestedSize: CGSize(width: 360, height: 640))))
    }
    @Test func testActiveWindowScreenSelectionAndCoordinateConversion() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                       CGRect(x: -1000, y: 0, width: 1000, height: 800)]
        #expect(PanelGeometry.screenIndex(for: CGRect(x: -800, y: 20, width: 500, height: 500), screens: screens) == 1)
        #expect(PanelGeometry.screenIndex(for: CGRect(x: -100, y: 20, width: 200, height: 500), screens: screens, fallback: 1) == 1)
        #expect(PanelGeometry.screenIndex(for: nil, screens: screens, fallback: 1) == 1)
        #expect(PanelGeometry.screenIndex(for: CGRect(x: 9000, y: 0, width: 200, height: 100), screens: screens, fallback: 1) == 1)
        #expect(PanelGeometry.screenIndex(for: nil, screens: []) == nil)
        #expect(PanelGeometry.fromAccessibility(CGRect(x: -800, y: 100, width: 400, height: 200), primaryScreenTop: 800) == CGRect(x: -800, y: 500, width: 400, height: 200))
    }
    @Test func testPreferencesPersistAndClamp() {
        let name = "app.cheatble.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var preferences = PanelPreferences()
        preferences.width = 9999; preferences.height = -1; preferences.backgroundOpacity = 0
        preferences.selectedTab = "macOS"
        preferences.save(to: defaults)
        let loaded = PanelPreferences.load(from: defaults)
        #expect(loaded.width == 2400)
        #expect(loaded.height == 320)
        #expect(loaded.backgroundOpacity == 0.2)
        #expect(loaded.selectedTab == "macOS")
        preferences.width = .nan; preferences.height = .infinity; preferences.backgroundOpacity = .nan
        preferences.selectedTab = "invalid"
        #expect(preferences.clamped() == PanelPreferences())
    }
    @Test func testToggleShortcutValidationAndPersistence() throws {
        #expect(ToggleShortcut.standard.keyCode == 36)
        #expect(ToggleShortcut.standard.chord.modifiers == [.control, .option, .command])
        #expect(try ToggleShortcut.parse("⌃⌥⌘Return") == ToggleShortcut.standard)
        #expect(try ToggleShortcut.parse("Control+Option+K").keyCode == 40)
        let name = "app.cheatble.hotkey-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ToggleShortcut.load(from: defaults) == .standard)
        let custom = try ToggleShortcut.parse("Control+Option+Command+F19")
        custom.save(to: defaults)
        #expect(ToggleShortcut.load(from: defaults) == custom)
        defaults.set("invalid", forKey: "toggle.shortcut")
        #expect(ToggleShortcut.load(from: defaults) == .standard)
    }
    @Test func testToggleShortcutRejectsTypingKeysAndSequences() {
        for input in ["Space", "Option+K", "Shift+Option+K", "Command+C", "Fn+Control+K",
                      "Control+Option+K → Space", "Control+Option+가"] {
            #expect(throws: (any Error).self) { try ToggleShortcut.parse(input) }
        }
    }
    @Test func testManualPlacementPersistsAndStaysOnScreen() {
        let screen = CGRect(x: -1440, y: -100, width: 1440, height: 900)
        let moved = PanelGeometry.frame(in: screen, requestedSize: CGSize(width: 640, height: 500), origin: CGPoint(x: -1200, y: 80))
        #expect(moved.origin == CGPoint(x: -1200, y: 80))
        #expect(screen.contains(PanelGeometry.frame(in: screen, requestedSize: CGSize(width: 3000, height: 3000), origin: CGPoint(x: 9000, y: -9000))))
        let name = "app.cheatble.position-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var preferences = PanelPreferences()
        preferences.position = moved.origin; preferences.width = 960
        preferences.save(to: defaults)
        #expect(PanelPreferences.load(from: defaults).position == moved.origin)
        #expect(PanelPreferences.load(from: defaults).width == 960)
        preferences.position = nil; preferences.save(to: defaults)
        #expect(PanelPreferences.load(from: defaults).position == nil)
        preferences.position = CGPoint(x: CGFloat.nan, y: 1)
        #expect(preferences.clamped().position == nil)
    }
    @Test func testResponsiveColumnsAtBoundaries() {
        for width in [280.0, 360, 595] { #expect(PanelGeometry.columnCount(for: width) == 1) }
        for width in [596.0, 640, 887] { #expect(PanelGeometry.columnCount(for: width) == 2) }
        for width in [888.0, 960, 2400] { #expect(PanelGeometry.columnCount(for: width) == 3) }
    }
    @Test func testNavigationShortcutPersistenceAndDefaults() throws {
        let name = "app.cheatble.navigation-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(NavigationAction.allCases.map { $0.standard.chord.key } == ["J", "K", ";"])
        #expect(Set(NavigationAction.allCases.map { $0.standard.chord } + [ToggleShortcut.standard.chord]).count == 4)
        for action in NavigationAction.allCases {
            #expect(action.load(from: defaults) == action.standard)
            #expect(action.isEnabled(in: defaults))
        }
        defaults.set("Control+Option+F17", forKey: NavigationAction.system.defaultsKey)
        defaults.set(false, forKey: NavigationAction.system.enabledKey)
        #expect(try NavigationAction.system.load(from: defaults) == ToggleShortcut.parse("Control+Option+F17"))
        #expect(!NavigationAction.system.isEnabled(in: defaults))
        #expect(NavigationAction.activeApp.load(from: defaults) == NavigationAction.activeApp.standard)
    }
}
