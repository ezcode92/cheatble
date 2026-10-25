import Foundation
import Testing
@testable import CheatbleCore

struct AppPackTests {
    @Test func bundledPacksAreValidSourcedAndDistinct() throws {
        let loaded = AppPackStorage.bundled()
        #expect(loaded.issues.isEmpty)
        let counts = Dictionary(uniqueKeysWithValues: loaded.packs.map { ($0.bundleIdentifier, $0.shortcuts.count) })
        #expect(counts == ["web.google.search": 11, "org.tmux.tmux": 36, "com.cmuxterm.app": 42,
                           "com.apple.finder": 18, "com.apple.Safari": 15,
                           "com.microsoft.Excel": 40, "com.microsoft.Word": 36, "com.microsoft.Powerpoint": 40])
        let catalog = try Catalog.bundled()
        let entries = try loaded.packs.flatMap { try $0.entries() }
        #expect(entries.allSatisfy { $0.sourceURL?.hasPrefix("https://") == true && $0.source == .pack })
        #expect(ShortcutMerger.merge([catalog.entries, entries]).count == 364)
        for entry in entries { #expect(try KeySequence.parse(KeySequence.editable(entry.sequence)) == entry.sequence) }
        let tmux = entries.filter { $0.scope == "org.tmux.tmux" }
        #expect(tmux.allSatisfy { $0.sequence.count == 2 && $0.sequence[0] == KeyChord(modifiers: [.control], key: "B") })
        #expect(!entries.contains { $0.sequence == [ToggleShortcut.standard.chord] })
        #expect(!entries.contains { entry in NavigationAction.allCases.contains { entry.sequence == [$0.standard.chord] } })
    }

    @Test func malformedPackCannotOverwriteInstalledDataOrEscapeDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cheatble-pack-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = AppPackStorage(directory: directory)
        let original = AppShortcutPack.example
        let url = try storage.install(original)
        let bytes = try Data(contentsOf: url)
        var invalid = original
        invalid.shortcuts[0].keys = "Command+NotAKey"
        #expect(throws: (any Error).self) { try storage.install(invalid) }
        #expect(try Data(contentsOf: url) == bytes)
        for scope in ["../escape", "app/escape", "", "macOS", "process.123"] {
            invalid = original; invalid.bundleIdentifier = scope
            #expect(throws: (any Error).self) { try storage.install(invalid) }
        }
        invalid = original; invalid.shortcuts.append(original.shortcuts[0])
        #expect(throws: (any Error).self) { try invalid.entries() }
        invalid = original; invalid.shortcuts[0].sourceURL = "javascript:alert(1)"
        #expect(throws: (any Error).self) { try invalid.entries() }
        invalid = original; invalid.schemaVersion = 9
        #expect(throws: (any Error).self) { try invalid.entries() }
        #expect(try AppShortcutPack.read(url) == original)
    }

    @Test func badPackDoesNotHideValidPacksAndReplacementKeepsManualOverrides() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cheatble-pack-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = AppPackStorage(directory: directory)
        var pack = AppShortcutPack.example
        try storage.install(pack)
        try Data("{ broken".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let loaded = storage.load()
        #expect(loaded.packs == [pack])
        #expect(loaded.issues.count == 1)
        pack.shortcuts[0].keys = "Control+Option+X"
        try storage.install(pack)
        let merged = AppPackStorage.merge(bundled: loaded, installed: storage.load())
        #expect(merged.packs == [pack])
        let entry = try pack.entries()[0]
        var manual = entry
        manual.source = .user; manual.sequence = try KeySequence.parse("Command+Shift+V")
        #expect(ShortcutMerger.merge([[manual], [entry]]) == [manual])
    }

    @Test func oldLibrariesMigrateAndSavedMenusSurvivePartialReads() throws {
        let legacy = Data(#"{"schemaVersion":1,"favorites":["kept"],"learned":[],"collapsedGroups":[],"entries":[]}"#.utf8)
        var document = try JSONDecoder().decode(LibraryDocument.self, from: legacy).validated()
        #expect(document.apps.isEmpty && document.favorites == ["kept"])
        let scope = "com.example.app"
        var first = ShortcutEntry(scope: scope, actionID: "first", title: "첫 번째", category: "메뉴",
                                  sequence: try KeySequence.parse("Command+F"), source: .menu, enabled: false)
        var second = first; second.actionID = "second"; second.id = ShortcutEntry.identity(scope: scope, actionID: "second")
        document.rememberApp(bundleIdentifier: scope, name: "Example", entries: [first])
        #expect(document.apps[0].entries[0].enabled == nil)
        let before = document
        document.rememberApp(bundleIdentifier: scope, name: "Example", entries: [first])
        #expect(document == before)
        document.rememberApp(bundleIdentifier: scope, name: "Example", entries: [second], partial: true)
        #expect(document.apps[0].entries.count == 2)
        first.sequence = try KeySequence.parse("Command+Option+F")
        document.rememberApp(bundleIdentifier: scope, name: "Renamed", entries: [first])
        #expect(document.apps[0].entries.count == 1)
        #expect(document.apps[0].name == "Renamed")
        let roundTrip = try JSONDecoder().decode(LibraryDocument.self, from: JSONEncoder().encode(document)).validated()
        #expect(roundTrip == document)
        var invalid = document
        invalid.apps[0].entries[0].scope = "another.app"
        #expect(throws: (any Error).self) { try invalid.validated() }
    }

    @Test func importedSavedMenusDiscardTransientAvailability() throws {
        let scope = "com.example.app"
        let date = Date(timeIntervalSince1970: 12345)
        var app = SavedApp(bundleIdentifier: scope, name: "Example", entries: [
            ShortcutEntry(scope: scope, actionID: "copy", title: "복사", category: "편집",
                          sequence: try KeySequence.parse("Command+C"), source: .menu)
        ], savedAt: date)
        for enabled in [true, false] {
            app.entries[0].enabled = enabled
            var document = LibraryDocument()
            document.apps = [app]
            let restored = try JSONDecoder().decode(LibraryDocument.self, from: JSONEncoder().encode(document)).validated()
            #expect(restored.apps[0].entries[0].enabled == nil)
            #expect(restored.apps[0].entries[0].sequence == app.entries[0].sequence)
            #expect(restored.apps[0].savedAt == date && restored.apps[0].name == "Example")
        }
    }

    @Test func savedSelectionPersistsAndInvalidScopeFallsBack() {
        let name = "app.cheatble.saved-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var preferences = PanelPreferences()
        preferences.selectedTab = "saved:web.google.search"
        preferences.save(to: defaults)
        #expect(PanelPreferences.load(from: defaults).savedScope == "web.google.search")
        preferences.selectedTab = "saved:../../bad"
        #expect(preferences.clamped().selectedTab == "app")
    }

    @Test func requestsContainExactIdentityAndInstallationInstructions() throws {
        let request = AppShortcutRequest(bundleIdentifier: "com.example.app", appName: "Example", appVersion: "1.2")
        let restored = try JSONDecoder().decode(AppShortcutRequest.self, from: JSONEncoder().encode(request))
        let text = restored.prompt(executablePath: "/Applications/Cheatble.app/Contents/MacOS/Cheatble")
        #expect(text.contains("com.example.app") && text.contains("1.2"))
        #expect(text.contains("--pack-example") && text.contains("--install-pack"))
        #expect(text.contains("공식 문서") && text.contains("직접 수정한 기존 항목"))
    }
}
