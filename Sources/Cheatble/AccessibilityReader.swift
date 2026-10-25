import AppKit
import ApplicationServices
import Carbon
import CheatbleCore

enum AXRead {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    static func children(_ element: AXUIElement, limit: Int = 2000) -> [AXUIElement] {
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count) == .success,
              count > 0 else { return [] }
        var result: CFArray?
        guard AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0,
                                            min(count, limit), &result) == .success else { return [] }
        return (result as? [AXUIElement]) ?? []
    }
    static func text(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        guard point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}

/// Reads menus only. No key posting, event taps, AppleScript, or leaf menu actions.
final class AccessibilityMenuReader {
    private let queue = DispatchQueue(label: "app.cheatble.menu-reader", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0
    private let catalog: Catalog
    init(catalog: Catalog) { self.catalog = catalog }

    func cancel() {
        lock.lock(); generation += 1; lock.unlock()
    }
    private func current(_ value: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == value
    }

    func read(pid: pid_t, scope: String, deep: Bool = false, supplementalEntries: [ShortcutEntry] = [],
              completion: @escaping (ShortcutSnapshot) -> Void) {
        lock.lock(); generation += 1; let request = generation; lock.unlock()
        queue.async { [weak self] in
            guard let self, self.current(request) else { return }
            let matchingCatalog = (try? Catalog(entries: ShortcutMerger.merge([self.catalog.entries, supplementalEntries]))) ?? self.catalog
            let result = self.collect(pid: pid, scope: scope, deep: deep, request: request, matchingCatalog: matchingCatalog)
            DispatchQueue.main.async {
                guard self.current(request) else { return }
                completion(result)
            }
        }
    }

    private func collect(pid: pid_t, scope: String, deep: Bool, request: Int, matchingCatalog: Catalog) -> ShortcutSnapshot {
        guard AXIsProcessTrusted() else {
            return .init(entries: [], state: .unavailable, message: "앱 메뉴를 보려면 손쉬운 사용 권한이 필요합니다.")
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let menuBar = AXRead.element(application, kAXMenuBarAttribute) else {
            return .init(entries: [], state: .unavailable, message: "이 앱의 메뉴를 읽을 수 없습니다. 기본 목록이나 직접 추가를 사용해 주세요.")
        }
        AXUIElementSetMessagingTimeout(menuBar, 0.15)
        let deadline = Date().addingTimeInterval(deep ? 6 : 2)
        var entries: [ShortcutEntry] = []
        var visited = Set<CFHashCode>()
        var nodes = 0
        var partial = false
        var openedMenu: AXUIElement?
        // Cancellation closes only a menu this operation successfully opened.
        func closeMenu(_ top: AXUIElement) -> Bool {
            for menu in AXRead.children(top, limit: 10) where AXRead.text(menu, kAXRoleAttribute) == kAXMenuRole {
                if AXUIElementPerformAction(menu, kAXCancelAction as CFString) == .success { return true }
            }
            return AXUIElementPerformAction(top, kAXCancelAction as CFString) == .success
        }
        defer { if let openedMenu { _ = closeMenu(openedMenu) } }

        func allowed() -> Bool {
            let ok = self.current(request) && Date() < deadline && nodes < 3000
            if !ok { partial = true }
            return ok
        }
        func visit(_ element: AXUIElement, path: [String], depth: Int) {
            guard allowed(), depth <= 12 else { partial = true; return }
            let hash = CFHash(element)
            guard visited.insert(hash).inserted else { return }
            nodes += 1
            AXUIElementSetMessagingTimeout(element, 0.15)
            let title = AXRead.text(element, kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let role = AXRead.text(element, kAXRoleAttribute) ?? ""
            var nextPath = path
            if !title.isEmpty, role != kAXMenuRole { nextPath.append(title) }
            if role == kAXMenuItemRole, !title.isEmpty, let chord = Self.chord(element) {
                let known = matchingCatalog.match(scope: scope, menuTitle: title)
                let action = known?.actionID ?? "menu:" + nextPath.map { "\($0.utf8.count):\($0)" }.joined()
                let enabled = (AXRead.value(element, kAXEnabledAttribute) as? NSNumber)?.boolValue
                let detail = known.map { "\($0.title)" + ($0.detail.map { " · \($0)" } ?? "") }
                entries.append(ShortcutEntry(scope: scope, actionID: action, title: title,
                    category: known?.category ?? path.first ?? "앱 메뉴", sequence: [chord],
                    source: .menu, enabled: enabled, detail: detail,
                    aliases: (known?.aliases ?? []) + (known.map { [$0.title] } ?? []), menuPath: nextPath))
            }
            let remaining = 3000 - nodes
            guard remaining > 0 else { partial = true; return }
            var count: CFIndex = 0
            if AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count) == .success,
               count > remaining { partial = true }
            for child in AXRead.children(element, limit: remaining) {
                guard allowed() else { break }
                visit(child, path: nextPath, depth: depth + 1)
            }
        }

        let topMenus = AXRead.children(menuBar, limit: 40)
        for top in topMenus {
            guard allowed() else { break }
            if deep {
                // The user explicitly requested this scan. Only menu-bar items may be opened;
                // never AXPress a command leaf or synthesize keystrokes.
                let stillFrontmost = (AXRead.value(application, kAXFrontmostAttribute) as? NSNumber)?.boolValue == true
                guard stillFrontmost else { partial = true; break }
                if AXRead.text(top, kAXRoleAttribute) == kAXMenuBarItemRole,
                   AXUIElementPerformAction(top, kAXPressAction as CFString) == .success {
                    openedMenu = top
                }
            }
            visit(top, path: [], depth: 0)
            if let opened = openedMenu {
                if closeMenu(opened) { openedMenu = nil }
                else { partial = true; break }
            }
        }
        let merged = ShortcutMerger.merge([entries])
        if merged.isEmpty {
            return .init(entries: [], state: .unavailable,
                         message: "표시할 메뉴 단축키가 없습니다. ‘메뉴 더 읽기’ 또는 직접 추가를 사용해 주세요.")
        }
        return .init(entries: merged, state: partial ? .partial : .ready,
                     message: partial ? "일부 메뉴만 읽었습니다. 목록을 새로고침하거나 직접 보완할 수 있습니다." : nil)
    }

    private static func chord(_ element: AXUIElement) -> KeyChord? {
        let character = AXRead.text(element, kAXMenuItemCmdCharAttribute) ?? ""
        let code = (AXRead.value(element, kAXMenuItemCmdVirtualKeyAttribute) as? NSNumber)?.intValue
        let glyph = (AXRead.value(element, kAXMenuItemCmdGlyphAttribute) as? NSNumber)?.intValue
        let specialKeys: [Int: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            76: "Return", 115: "Home", 116: "PageUp", 117: "ForwardDelete",
            119: "End", 121: "PageDown", 123: "Left", 124: "Right", 125: "Down", 126: "Up",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
        ]
        // A virtual key attribute alone can be 0 on items with no shortcut.
        guard !character.isEmpty || (glyph ?? 0) > 0 || (code.map { specialKeys[$0] != nil } ?? false) else { return nil }
        let key: String
        if let code, let special = specialKeys[code] { key = special }
        else if character == " " { key = "Space" }
        else if !character.isEmpty, character.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            key = character
        } else { return nil }
        guard let mask = (AXRead.value(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue else { return nil }
        return KeyChord(modifiers: Modifier.accessibilityMask(mask), key: key)
    }
}
