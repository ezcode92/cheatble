import AppKit
import SwiftUI
import CheatbleCore
import Carbon
import UniformTypeIdentifiers
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var overlay: PanelController!
    private var settings: SettingsWindowController?
    private var editor: EditorWindowController?
    private var shortcutSettings: AppShortcutSettingsWindowController?
    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private let globalHotKey = GlobalHotKey()
    private let navigationHotKeys = Dictionary(uniqueKeysWithValues: NavigationAction.allCases.map { ($0, GlobalHotKey()) })
    private let smokeDirectory: URL?
    private var smokeDefaultsName: String?
    private let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

    init(smokeDirectory: URL?) { self.smokeDirectory = smokeDirectory }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = CheatbleStyle.appIcon
        do {
            let catalog = try Catalog.bundled()
            if let smokeDirectory {
                let name = "app.cheatble.smoke.\(UUID().uuidString)"
                smokeDefaultsName = name
                let defaults = UserDefaults(suiteName: name)!
                defaults.set("Control+Option+Command+F18", forKey: "toggle.shortcut")
                for (action, key) in zip(NavigationAction.allCases, ["F15", "F16", "F17"]) {
                    defaults.set("Control+Option+Command+" + key, forKey: action.defaultsKey)
                }
                model = AppModel(catalog: catalog, defaults: defaults,
                                 storageURL: smokeDirectory.appendingPathComponent("library.json"))
                model.preferences.selectedTab = "macOS"
            } else { model = AppModel(catalog: catalog) }
            overlay = PanelController(model: model)
            model.hidePanel = { [weak self] in self?.overlay.hide(); self?.updateToggleTitle() }
            model.openSettings = { [weak self] in self?.showSettings() }
            model.openEditor = { [weak self] entry in self?.showEditor(entry) }
            model.openShortcutSettings = { [weak self] in self?.showShortcutSettings() }
            model.openPackImport = { [weak self] in self?.importPack() }
            installMenus()
            globalHotKey.onPress = { [weak self] in self?.togglePanel() }
            model.onToggleShortcutChange = { [weak self] shortcut in
                guard let self else { return }
                try self.globalHotKey.register(shortcut)
                DispatchQueue.main.async { [weak self] in self?.updateToggleTitle() }
            }
            model.activateToggleShortcut()
            for action in NavigationAction.allCases {
                navigationHotKeys[action]?.onPress = { [weak self] in self?.navigate(action) }
            }
            model.onNavigationShortcutChange = { [weak self] action, shortcut in
                try self?.navigationHotKeys[action]?.register(shortcut)
            }
            model.activateNavigationShortcuts()
            model.start()
            overlay.show()
            if smokeDirectory != nil {
                // Run from a run-loop timer, not inside a main dispatch block: the smoke
                // harness pumps the run loop while waiting for asynchronous pack delivery.
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in self?.runSmokeTest() }
            }
        } catch {
            if let smokeDirectory {
                try? FileManager.default.createDirectory(at: smokeDirectory, withIntermediateDirectories: true)
                try? "\(error)".write(to: smokeDirectory.appendingPathComponent("error.txt"), atomically: true, encoding: .utf8)
            } else {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
            NSApp.terminate(nil)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        globalHotKey.stop()
        navigationHotKeys.values.forEach { $0.stop() }
        if let smokeDefaultsName { UserDefaults.standard.removePersistentDomain(forName: smokeDefaultsName) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let overlay else { return false }
        overlay.show()
        updateToggleTitle()
        return false
    }

    private func installMenus() {
        let main = NSMenu()
        let application = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Cheatble 설정…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Cheatble 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = appMenu; main.addItem(application)
        let edit = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "편집")
        for (title, selector, key) in [
            ("실행 취소", Selector(("undo:")), "z"), ("오려두기", #selector(NSText.cut(_:)), "x"),
            ("복사", #selector(NSText.copy(_:)), "c"), ("붙여넣기", #selector(NSText.paste(_:)), "v"),
            ("전체 선택", #selector(NSText.selectAll(_:)), "a")
        ] { editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        edit.submenu = editMenu; main.addItem(edit)
        NSApp.mainMenu = main

        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Cheatble")
        status.button?.toolTip = "Cheatble — 단축키 시트"
        let menu = NSMenu()
        let toggle = menu.addItem(withTitle: "시트 숨기기", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self; toggleItem = toggle
        menu.addItem(withTitle: "macOS 기본 단축키", action: #selector(showSystem), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "설정…", action: #selector(showSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "앱별 단축키 설정…", action: #selector(showShortcutSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cheatble 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        status.menu = menu; statusItem = status
    }
    @objc private func togglePanel() {
        if overlay.panel.isVisible { overlay.hide() } else { overlay.show() }
        updateToggleTitle()
    }
    private func updateToggleTitle() {
        let title = overlay.panel.isVisible ? "시트 숨기기" : "시트 보이기"
        toggleItem?.title = title + (model.toggleShortcutRegistered ? "  \(model.toggleShortcut.chord.display)" : "")
    }
    @objc private func showSystem() {
        model.selectTab("macOS"); overlay.show(); updateToggleTitle()
    }
    private func navigate(_ action: NavigationAction) {
        if action == .savedApps && model.isAppPickerPresented {
            model.isAppPickerPresented = false
            model.releaseSearchFocus?()
            return
        }
        model.releaseSearchFocus?()
        switch action {
        case .activeApp: model.selectTab("app")
        case .system: model.selectTab("macOS")
        case .savedApps:
            if let saved = model.defaults.string(forKey: "navigation.lastSavedScope"), AppScope.isValid(saved) {
                model.selectTab("saved:" + saved)
            }
        }
        overlay.show()
        if action == .savedApps { model.isAppPickerPresented = true }
        updateToggleTitle()
    }
    @objc private func showSettings() {
        if settings == nil { settings = SettingsWindowController(model: model) }
        settings?.present()
    }
    @objc private func addEntry() { showEditor(nil) }
    @objc private func showShortcutSettings() {
        shortcutSettings?.close()
        shortcutSettings = AppShortcutSettingsWindowController(model: model, scope: model.scope) { [weak self] entry, scope in
            self?.showEditor(entry, scope: scope)
        }
        shortcutSettings?.present()
    }
    private func showEditor(_ entry: ShortcutEntry?, scope: String? = nil) {
        editor?.close()
        editor = EditorWindowController(model: model, entry: entry, scope: scope)
        editor?.present()
    }
    private func importPack() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "추가할 앱의 Cheatble 단축키 목록을 선택하세요."
        if panel.runModal() == .OK, let url = panel.url { model.importPack(from: url) }
    }

    /// Captures only our own view, without Screen Recording or Accessibility permission.
    private func runSmokeTest() {
        guard let directory = smokeDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let panel = overlay.panel
            func capture(_ window: NSWindow, name: String) throws {
                let view = window.contentView!
                view.layoutSubtreeIfNeeded()
                var png: Data?
                window.effectiveAppearance.performAsCurrentDrawingAppearance {
                    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        png = bitmap.representation(using: .png, properties: [:])
                    }
                }
                if let png { try png.write(to: directory.appendingPathComponent(name + ".png")) }
            }
            try capture(panel, name: "overlay")
            let systemCount = model.allEntries.count
            model.query = "캡처"
            let searchCount = model.visibleEntries.count
            model.query = ""
            let entry = model.allEntries[0]
            model.toggleFavorite(entry)
            model.toggleLearned(entry)
            let persisted = try model.storage.load()
            var report: [String: Any] = [
                "catalogCount": model.catalog.entries.count, "macOSCount": systemCount,
                "searchCount": searchCount, "windowAlpha": panel.alphaValue,
                "backgroundOpacity": model.preferences.backgroundOpacity,
                "nonactivatingPanel": panel.styleMask.contains(.nonactivatingPanel),
                "activeAppDetected": model.activeApp != nil,
                "activeAppMatchesWorkspace": model.activeApp?.pid == frontmostPID,
                "accessibilityPermission": model.hasPermission,
                "didNotActivate": NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID,
                "didNotBecomeKey": !panel.isKeyWindow,
                "floating": panel.level == .floating,
                "persistedFavorite": persisted.favorites.contains(entry.id),
                "persistedLearned": persisted.learned.contains(entry.id),
                "learnedHidden": !model.visibleEntries.contains(where: { $0.id == entry.id }),
                "frame": NSStringFromRect(panel.frame), "bundlePath": Bundle.main.bundlePath
            ]
            // Reproduce startup registration before the pack observer has started.
            // Callbacks record registrations without reserving any system hot keys.
            let startupDirectory = directory.appendingPathComponent("startup-conflicts")
            let startupDefaultsName = "app.cheatble.startup-smoke.\(UUID())"
            let startupDefaults = UserDefaults(suiteName: startupDefaultsName)!
            defer { startupDefaults.removePersistentDomain(forName: startupDefaultsName) }
            let prefixText = "Control+Option+F19"
            let prefix = try ToggleShortcut.parse(prefixText)
            var fixture = AppShortcutPack.example
            fixture.shortcuts[0].keys = prefixText + " → X"
            try AppPackStorage(directory: startupDirectory.appendingPathComponent("Packs")).install(fixture)
            prefix.save(to: startupDefaults)
            let startupModel = AppModel(catalog: model.catalog, defaults: startupDefaults,
                                        storageURL: startupDirectory.appendingPathComponent("library.json"))
            var registrationCalls = 0
            var startupRegistration: ToggleShortcut?
            startupModel.onToggleShortcutChange = { shortcut in registrationCalls += 1; startupRegistration = shortcut }
            startupModel.activateToggleShortcut()
            report["startupPackPrefixConflictRejected"] = registrationCalls == 0 &&
                !startupModel.toggleShortcutRegistered && startupModel.toggleShortcutError != nil
            report["startupBundledPacksLoaded"] = startupModel.packs.count == 9 &&
                startupModel.packEntries.contains { $0.scope == "org.tmux.tmux" }
            let initialKey = "Control+Option+F20"
            let initialShortcut = try ToggleShortcut.parse(initialKey)
            let registered = startupModel.updateToggleShortcut(initialKey)
            report["packConflictKeepsPreviousShortcut"] = registered &&
                !startupModel.updateToggleShortcut(prefixText) && registrationCalls == 1 &&
                startupModel.toggleShortcut == initialShortcut &&
                startupModel.toggleShortcutRegistered
            var navigationCalls = 0
            var startupNavigation: [NavigationAction: ToggleShortcut] = [:]
            startupModel.onNavigationShortcutChange = { action, shortcut in
                navigationCalls += 1
                startupNavigation[action] = shortcut
            }
            let oldNavigation = startupModel.navigationShortcuts[.system]
            report["navigationPackPrefixConflictRejected"] =
                !startupModel.updateNavigationShortcut(.system, text: prefixText) && navigationCalls == 0 &&
                startupModel.navigationShortcuts[.system] == oldNavigation
            startupModel.start()
            defer { startupModel.stop() }
            func waitForPackUpdate(_ condition: () -> Bool) {
                let deadline = Date().addingTimeInterval(3)
                while !condition() && Date() < deadline {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                }
            }
            waitForPackUpdate { startupModel.navigationRegistered.count == 3 }
            fixture.shortcuts.append(.init(id: "conflict.toggle", title: "토글 충돌", category: "검증", keys: initialKey))
            fixture.shortcuts.append(.init(id: "conflict.system", title: "목록 충돌", category: "검증",
                keys: KeySequence.editable([oldNavigation!.chord])))
            let conflictURL = try startupModel.packStorage.install(fixture)
            startupModel.reloadPacks()
            waitForPackUpdate { startupModel.toggleShortcutError != nil && startupModel.navigationErrors[.system] != nil }
            report["hotReloadUnregistersConflictingKeys"] = !startupModel.toggleShortcutRegistered && startupRegistration == nil &&
                !startupModel.navigationRegistered.contains(.system) && startupNavigation[.system] == nil &&
                startupModel.toggleShortcutEnabled && startupModel.navigationEnabled[.system] == true
            try FileManager.default.removeItem(at: conflictURL)
            startupModel.reloadPacks()
            waitForPackUpdate { startupModel.toggleShortcutRegistered && startupModel.navigationRegistered.contains(.system) }
            report["removingPackRestoresConfiguredKeys"] = startupRegistration == initialShortcut &&
                startupNavigation[.system] == oldNavigation && startupModel.toggleShortcutError == nil &&
                startupModel.navigationErrors[.system] == nil && ToggleShortcut.load(from: startupDefaults) == initialShortcut
            var edited = entry
            edited.source = .user; edited.scope = "InvalidScope"
            let rejected = !startupModel.saveEntry(edited) && startupModel.error != nil
            edited.scope = entry.scope
            report["successfulSaveClearsError"] = rejected && startupModel.saveEntry(edited) && startupModel.error == nil
            startupModel.error = "이전 오류"
            report["unchangedSuccessfulSaveClearsError"] = startupModel.saveEntry(edited) && startupModel.error == nil
            // Feed Carbon hot-key notifications only to this app's event target.
            // This never posts keyboard input into another application.
            func sendHotKey(_ kind: UInt32, hotKey: GlobalHotKey? = nil) -> Bool {
                var event: EventRef?
                guard CreateEvent(nil, OSType(kEventClassKeyboard), kind, GetCurrentEventTime(), 0, &event) == noErr,
                      let event else { return false }
                defer { ReleaseEvent(event) }
                var identity = (hotKey ?? globalHotKey).identity
                guard SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identity) == noErr
                else { return false }
                return SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr
            }
            report["globalHotKeyRegistered"] = model.toggleShortcutRegistered
            report["globalHotKey"] = model.toggleShortcut.chord.display
            report["hotKeyHides"] = sendHotKey(UInt32(kEventHotKeyPressed)) && !panel.isVisible
            report["hotKeyRepeatIgnored"] = sendHotKey(UInt32(kEventHotKeyPressed)) && !panel.isVisible
            _ = sendHotKey(UInt32(kEventHotKeyReleased))
            report["hotKeyShows"] = sendHotKey(UInt32(kEventHotKeyPressed)) && panel.isVisible
            _ = sendHotKey(UInt32(kEventHotKeyReleased))
            let competing = GlobalHotKey()
            do {
                try competing.register(model.toggleShortcut)
                report["hotKeyDuplicateRejected"] = false
            } catch {
                report["hotKeyDuplicateRejected"] = true
            }
            competing.stop()
            let savedShortcut = model.toggleShortcut
            let alternate = try ToggleShortcut.parse("Control+Option+Command+F19")
            try competing.register(alternate)
            report["hotKeyFailedChangeKeepsOld"] =
                !model.updateToggleShortcut(KeySequence.editable([alternate.chord])) &&
                globalHotKey.shortcut == savedShortcut && model.toggleShortcut == savedShortcut &&
                ToggleShortcut.load(from: model.defaults) == savedShortcut
            competing.stop()
            let text = KeySequence.editable([savedShortcut.chord])
            report["hotKeyDisableWorks"] = model.updateToggleShortcut(text, enabled: false) && globalHotKey.shortcut == nil
            report["hotKeyReenableWorks"] = model.updateToggleShortcut(text) && globalHotKey.shortcut == savedShortcut
            report["navigationHotKeysRegistered"] = model.navigationRegistered.count == 3
            report["hotKeyIdentitiesAreDistinct"] = Set([globalHotKey.identity.id] + navigationHotKeys.values.map { $0.identity.id }).count == 4
            func pressNavigation(_ action: NavigationAction) -> Bool {
                let handled = sendHotKey(UInt32(kEventHotKeyPressed), hotKey: navigationHotKeys[action])
                _ = sendHotKey(UInt32(kEventHotKeyReleased), hotKey: navigationHotKeys[action])
                return handled
            }
            model.selectTab("saved:org.tmux.tmux")
            overlay.hide()
            report["navigationSelectsActiveApp"] = pressNavigation(.activeApp) && model.isFollowingActiveApp && panel.isVisible && !model.isAppPickerPresented
            report["navigationSelectsSystem"] = pressNavigation(.system) && model.isSystem && panel.isVisible && !model.isAppPickerPresented
            report["navigationOpensSavedPicker"] = pressNavigation(.savedApps) && model.scope == "org.tmux.tmux" && model.isAppPickerPresented && panel.isVisible
            report["navigationClosesSavedPicker"] = pressNavigation(.savedApps) && !model.isAppPickerPresented && panel.isVisible
            let activeKey = KeySequence.editable([model.navigationShortcuts[.activeApp]!.chord])
            let systemKey = KeySequence.editable([model.navigationShortcuts[.system]!.chord])
            report["internalHotKeyConflictsRejected"] = !model.updateToggleShortcut(activeKey) && model.toggleShortcut == savedShortcut &&
                !model.updateNavigationShortcut(.system, text: activeKey) && navigationHotKeys[.system]?.shortcut == model.navigationShortcuts[.system]
            _ = model.updateToggleShortcut(text)
            report["navigationCanDisableAndReenable"] = model.updateNavigationShortcut(.system, text: systemKey, enabled: false) &&
                navigationHotKeys[.system]?.shortcut == nil && model.navigationRegistered.count == 2 &&
                model.updateNavigationShortcut(.system, text: systemKey) && model.navigationRegistered.count == 3
            model.selectTab("macOS")
            report["navigationPreservesForegroundApp"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID
            model.preferences.width = 240; model.preferences.height = 360
            model.preferences.backgroundOpacity = 0.2
            overlay.place()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(panel, name: "overlay-small")
            model.query = "캡처"
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(panel, name: "keycaps-small")
            model.query = ""
            report["resizedWidth"] = panel.frame.width
            report["resizedHeight"] = panel.frame.height
            report["transparentWindowAlpha"] = panel.alphaValue
            // Resize the actual window as the drag handle does, then verify delegate persistence.
            let initialFrame = panel.frame
            panel.setFrame(CGRect(x: initialFrame.maxX - 340, y: initialFrame.maxY - 520,
                                  width: 340, height: 520), display: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let resizedPreferences = PanelPreferences.load(from: model.defaults)
            report["directResizePersists"] = resizedPreferences.width == 340 && resizedPreferences.height == 520 &&
                panel.frame.maxX == initialFrame.maxX && panel.frame.maxY == initialFrame.maxY
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let handles = descendants(panel.contentView!).compactMap { $0 as? ResizeHandle.ResizeView }
            report["visibleResizeHandle"] = handles.contains { $0.edge == .corner && $0.bounds.width >= 30 }
            report["resizeAcceptsFirstClick"] = handles.count == 3 && handles.allSatisfy { $0.acceptsFirstMouse(for: nil) }

            let dragHandles = descendants(panel.contentView!).compactMap { $0 as? MoveHandle.DragView }
            report["moveHandleAcceptsFirstClick"] = !dragHandles.isEmpty && dragHandles.allSatisfy { $0.acceptsFirstMouse(for: nil) }
            let visibleFrame = panel.screen!.visibleFrame
            panel.setFrameOrigin(CGPoint(x: visibleFrame.minX + 60, y: visibleFrame.minY + 60))
            panel.didDrag?(panel.frame)
            let movedOrigin = panel.frame.origin
            overlay.hide(); overlay.show()
            model.onWindowFrame?(nil)
            report["movedPositionPersists"] = PanelPreferences.load(from: model.defaults).position == movedOrigin && panel.frame.origin == movedOrigin
            model.preferences.backgroundOpacity = 0.85
            model.preferences.height = 640
            model.preferences.width = 640; overlay.place()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(panel, name: "overlay-2col")
            report["twoColumnsAtMediumWidth"] = PanelGeometry.columnCount(for: panel.frame.width) == 2
            model.preferences.width = 960; overlay.place()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(panel, name: "overlay-3col")
            report["threeColumnsAtWideWidth"] = PanelGeometry.columnCount(for: panel.frame.width) == 3
            model.preferences.position = nil
            report["bundledPackCount"] = model.packs.count
            report["bundledPackEntries"] = model.packEntries.count
            let expectedScopes = Set(["web.google.search", "org.tmux.tmux", "com.cmuxterm.app", "com.apple.finder", "com.apple.Safari", "com.microsoft.Excel", "com.microsoft.Word", "com.microsoft.Powerpoint"])
            report["requestedAppsSelectable"] = expectedScopes.isSubset(of: Set(model.savedApps.map(\.id)))
            model.preferences.width = 360; model.preferences.height = 640; model.preferences.backgroundOpacity = 0.85

            // Simulate activation notifications without activating other apps or posting input.
            // Invalid PIDs prevent the menu reader from querying a different real app as a fixture.
            let actualContext = model.activeApp
            let finderContext = ActiveAppContext(pid: -101, bundleIdentifier: "com.apple.finder", name: "Finder",
                                                 icon: model.icon(for: "com.apple.finder"))
            let safariContext = ActiveAppContext(pid: -102, bundleIdentifier: "com.apple.Safari", name: "Safari",
                                                 icon: model.icon(for: "com.apple.Safari"))
            model.selectTab("app")
            model.tracker.onAppChange?(finderContext)
            let followsFinder = model.scope == "com.apple.finder" && model.allEntries.count == 44
            model.query = "임시 검색"; model.modifiers = [.shift]
            model.tracker.onAppChange?(safariContext)
            report["activeSelectionFollowsAppChanges"] = followsFinder && model.scope == "com.apple.Safari" &&
                model.allEntries.count == 31 && model.title == "Safari" && model.query.isEmpty && model.modifiers.isEmpty
            report["pickerExcludesActiveApp"] = !model.selectableSavedApps.contains { $0.id == "com.apple.Safari" } &&
                model.selectableSavedApps.contains { $0.id == "com.apple.finder" }

            model.selectTab("saved:org.tmux.tmux")
            model.query = "패널"; model.modifiers = [.control]
            let pinnedIDs = model.visibleEntries.map(\.id)
            model.tracker.onAppChange?(finderContext)
            report["savedSelectionKeepsListAndFilters"] = model.scope == "org.tmux.tmux" && model.query == "패널" &&
                model.modifiers == [.control] && model.visibleEntries.map(\.id) == pinnedIDs && !pinnedIDs.isEmpty &&
                model.activeApp?.icon === finderContext.icon && model.activeApp?.bundleIdentifier == "com.apple.finder"
            model.selectTab("saved:com.apple.Safari")
            model.query = "탭"
            model.tracker.onAppChange?(safariContext)
            report["savedSelectionDoesNotBecomeAutomatic"] = model.preferences.selectedTab == "saved:com.apple.Safari" &&
                !model.isFollowingActiveApp && model.query == "탭"
            model.selectTab("macOS")
            model.query = "캡처"; model.modifiers = [.shift]
            let systemIDs = model.visibleEntries.map(\.id)
            model.tracker.onAppChange?(finderContext)
            model.tracker.onAppChange?(safariContext)
            report["systemSelectionKeepsListAndFilters"] = model.isSystem && model.query == "캡처" &&
                model.modifiers == [.shift] && model.visibleEntries.map(\.id) == systemIDs &&
                model.activeApp?.icon === safariContext.icon
            if let actualContext { model.tracker.onAppChange?(actualContext) }

            model.selectTab("saved:com.apple.Safari")
            model.query = "탭"
            if let context = model.activeApp { model.tracker.onAppChange?(context) }
            report["savedSelectionSurvivesActivation"] = model.scope == "com.apple.Safari" && model.query == "탭"
            report["savedSelectionPersists"] = PanelPreferences.load(from: model.defaults).savedScope == "com.apple.Safari"
            model.query = ""
            report["savedSafariCount"] = model.allEntries.count
            model.saveCurrentApp()
            report["activeAppCanBeSaved"] = model.activeApp.map { context in
                model.library.apps.contains { $0.id == context.bundleIdentifier }
            } ?? false
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(panel, name: "saved-app")
            model.selectTab("saved:org.tmux.tmux")
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(panel, name: "tmux")
            model.preferences.width = 280
            overlay.place()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(panel, name: "tmux-small")
            model.preferences.width = 360
            model.selectTab("saved:web.google.search")
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(panel, name: "google-search")
            let windowsBeforePicker = Set(NSApp.windows.map(ObjectIdentifier.init))
            model.isAppPickerPresented = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let pickerWindow = NSApp.windows.first {
                $0.isVisible && !windowsBeforePicker.contains(ObjectIdentifier($0)) && $0.contentView != nil
            }
            report["iconPickerOpens"] = pickerWindow != nil
            report["iconPickerDoesNotActivateApp"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID
            if let pickerWindow {
                try capture(pickerWindow, name: "app-picker")
                if let search = descendants(pickerWindow.contentView!).compactMap({ $0 as? AppPickerSearchField.Input }).first {
                    report["pickerGetsKeyboardFocus"] = pickerWindow.isKeyWindow && search.currentEditor() != nil &&
                        pickerWindow.firstResponder === search.currentEditor()
                    // Deliver events only to this picker window; never post input to the system.
                    func pressPickerKey(_ code: UInt16, _ characters: String) {
                        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: pickerWindow.windowNumber,
                            context: nil, characters: characters, charactersIgnoringModifiers: characters,
                            isARepeat: false, keyCode: code) { pickerWindow.sendEvent(event) }
                        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                    }
                    let choices = model.selectableSavedApps
                    for _ in choices { pressPickerKey(123, String(UnicodeScalar(NSLeftArrowFunctionKey)!)) }
                    report["pickerLeftStopsAtFirst"] = search.highlightedID == choices.first?.id
                    pressPickerKey(124, String(UnicodeScalar(NSRightArrowFunctionKey)!))
                    report["pickerRightMovesOne"] = choices.count > 1 && search.highlightedID == choices[1].id
                    pressPickerKey(125, String(UnicodeScalar(NSDownArrowFunctionKey)!))
                    report["pickerDownMovesRow"] = choices.count > 6 && search.highlightedID == choices[6].id
                    pressPickerKey(126, String(UnicodeScalar(NSUpArrowFunctionKey)!))
                    report["pickerUpMovesRow"] = choices.count > 1 && search.highlightedID == choices[1].id
                    try capture(pickerWindow, name: "app-picker-keyboard")
                    search.stringValue = "no-app-matches-this-query"
                    search.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: search))
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    pressPickerKey(36, "\r")
                    report["pickerEmptyReturnDoesNothing"] = search.highlightedID == nil && model.isAppPickerPresented
                    search.stringValue = "tmux"
                    search.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: search))
                    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                    try capture(pickerWindow, name: "app-picker-search")
                    report["pickerSearchUpdatesHighlight"] = search.highlightedID == "org.tmux.tmux"
                    pressPickerKey(36, "\r")
                    report["pickerReturnChoosesApp"] = !model.isAppPickerPresented && model.scope == "org.tmux.tmux"
                }
            }
            model.selectTab("saved:org.tmux.tmux")
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            report["iconPickerSelectionClosesAndPins"] = !model.isAppPickerPresented && model.scope == "org.tmux.tmux"
            report["pickerReopensAfterToggle"] = pressNavigation(.savedApps) && model.isAppPickerPresented
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let reopened = NSApp.windows.first(where: { window in
                window.isVisible && window.contentView.map { descendants($0).contains { $0 is AppPickerSearchField.Input } } == true
            }), let input = descendants(reopened.contentView!).compactMap({ $0 as? AppPickerSearchField.Input }).first {
                report["pickerRefocusesOnReopen"] = reopened.isKeyWindow && input.currentEditor() != nil &&
                    reopened.firstResponder === input.currentEditor()
                if let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: reopened.windowNumber,
                    context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                    isARepeat: false, keyCode: 53) { reopened.sendEvent(escape) }
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                report["pickerEscapeCloses"] = !model.isAppPickerPresented && model.scope == "org.tmux.tmux"
            }
            report["pickerReturnsKeyboardFocus"] = !panel.isKeyWindow && NSApp.keyWindow == nil &&
                NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID
            report["pickerKeyWindowAfterClose"] = NSApp.keyWindow.map { NSStringFromClass(type(of: $0)) } ?? "none"
            report["pickerPanelKeyAfterClose"] = panel.isKeyWindow
            report["pickerForegroundUnchanged"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID
            model.isAppPickerPresented = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            overlay.hide()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            report["hidingSheetDismissesPicker"] = !panel.isVisible && !model.isAppPickerPresented
            overlay.show()

            // Exercise CLI installation with isolated test storage.
            var pack = AppShortcutPack.example
            pack.appName = "추가한 앱"
            pack.shortcuts[0].title = "추가된 단축키"
            let packURL = directory.appendingPathComponent("incoming-pack.json")
            try JSONEncoder().encode(pack).write(to: packURL)
            let installer = Process()
            installer.executableURL = Bundle.main.executableURL
            installer.arguments = ["--install-pack", packURL.path, "--pack-directory", model.packStorage.directory.path]
            installer.standardOutput = FileHandle.nullDevice
            try installer.run(); installer.waitUntilExit()
            let deadline = Date().addingTimeInterval(5)
            while !model.packs.contains(where: { $0.bundleIdentifier == pack.bundleIdentifier }) && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            model.selectTab("saved:" + pack.bundleIdentifier)
            report["installedPackAutoReloads"] = installer.terminationStatus == 0 && model.allEntries.count == 1 &&
                model.savedApps.contains { $0.id == pack.bundleIdentifier }
            report["packInstallExitCode"] = installer.terminationStatus
            report["packsAfterInstall"] = model.packs.count
            report["packLoadIssues"] = model.packIssues
            report["requestTargetsSelection"] = model.additionRequest()?.bundleIdentifier == pack.bundleIdentifier &&
                model.additionRequest()?.prompt(executablePath: "Cheatble").contains("--install-pack") == true
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(panel, name: "added-app")
            model.selectTab("saved:com.example.unsupported")
            report["emptyAppCanRequestPack"] = model.allEntries.isEmpty && model.canRequestPack && model.additionRequest() != nil
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(panel, name: "empty-app")
            model.selectTab("macOS")
            let managementEntries = model.shortcuts(for: "org.tmux.tmux")
            report["managementScopeIndependentOfOverlay"] = managementEntries.count == 36 && model.isSystem
            let managementPreview = AppShortcutSettingsWindowController(model: model, scope: "org.tmux.tmux") { _, _ in }
            managementPreview.window?.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(managementPreview.window!, name: "app-shortcut-settings")
            managementPreview.close()
            for (scope, name, count) in [("com.microsoft.Excel", "excel", 40), ("com.microsoft.Word", "word", 36), ("com.microsoft.Powerpoint", "powerpoint", 40)] {
                model.selectTab("saved:" + scope)
                report[name + "ShortcutCount"] = model.allEntries.count
                guard model.allEntries.count == count else { throw NSError(domain: "Smoke.Office", code: 1) }
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                try capture(panel, name: name)
            }
            model.selectTab("macOS")
            let settingsPreview = SettingsWindowController(model: model)
            settingsPreview.window?.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(settingsPreview.window!, name: "settings")
            settingsPreview.close()
            let editorPreview = EditorWindowController(model: model, entry: entry)
            editorPreview.window?.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(editorPreview.window!, name: "editor")
            editorPreview.close()
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("report.json"))
        } catch {
            try? "\(error)".write(to: directory.appendingPathComponent("error.txt"), atomically: true, encoding: .utf8)
        }
        NSApp.terminate(nil)
    }
}

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--install-pack") {
    do {
        guard arguments.indices.contains(index + 1) else {
            throw NSError(domain: "Cheatble.CLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "사용법: Cheatble --install-pack <JSON 파일>"])
        }
        var storage = AppPackStorage.standard
        if let directoryIndex = arguments.firstIndex(of: "--pack-directory"),
           arguments.indices.contains(directoryIndex + 1) {
            storage = AppPackStorage(directory: URL(fileURLWithPath: arguments[directoryIndex + 1], isDirectory: true))
        }
        let pack = try AppShortcutPack.read(URL(fileURLWithPath: arguments[index + 1]))
        let destination = try storage.install(pack)
        print("\(pack.appName): \(pack.shortcuts.count) shortcuts installed at \(destination.path)")
        print("실행 중인 Cheatble에 2초 이내 자동 반영됩니다.")
    } catch { fputs("Pack installation failed: \(error.localizedDescription)\n", stderr); exit(1) }
} else if arguments.contains("--pack-example") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(AppShortcutPack.example), let text = String(data: data, encoding: .utf8) { print(text) }
} else if arguments.contains("--permission-status") {
    // Run via scripts/permission-status.py (LaunchServices). Direct shell execution
    // may inherit the terminal's TCC responsibility instead of the GUI app's.
    let status: [String: Any] = ["trusted": AXIsProcessTrusted(),
        "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
        "bundlePath": Bundle.main.bundlePath,
        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""]
    if let data = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text) }
} else if arguments.contains("--validate-bundle") {
    do {
        let catalog = try Catalog.bundled()
        let packs = AppPackStorage.bundled()
        guard packs.issues.isEmpty, packs.packs.count == 8 else {
            throw NSError(domain: "Cheatble.Resources", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "내장 팩 8개가 필요합니다. \(packs.issues.joined(separator: "; "))"])
        }
        let entries = try packs.packs.flatMap { try $0.entries() }
        let merged = ShortcutMerger.merge([catalog.entries, entries])
        print("Cheatble catalog: \(merged.count) entries; macOS: \(catalog.shortcuts(for: "macOS", osMajor: 15).count); packs: \(packs.packs.count)")
        for pack in packs.packs {
            print("\(pack.appName): \(merged.filter { $0.scope == pack.bundleIdentifier }.count)")
        }
    } catch { fputs("Catalog validation failed: \(error)\n", stderr); exit(1) }
} else {
    let smokeIndex = arguments.firstIndex(of: "--smoke-test")
    let directory = smokeIndex.flatMap { index in
        arguments.indices.contains(index + 1) ? URL(fileURLWithPath: arguments[index + 1], isDirectory: true) : nil
    }
    let delegate = AppDelegate(smokeDirectory: directory)
    let application = NSApplication.shared
    application.delegate = delegate
    application.run()
}
