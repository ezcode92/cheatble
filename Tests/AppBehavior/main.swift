import AppKit
import ApplicationServices
import CheatbleCore

// Compile the production reader/model with OS-boundary fakes. No windows,
// Accessibility permission, or real hot-key registrations are needed.
let nodes = (0..<6).map { ApplicationServices.AXUIElementCreateApplication(pid_t(700_000 + $0)) }
enum Fault { case none, count, children, vanishedChildren, shortChildren, title, role, character, modifiers, allMenus }
var fault = Fault.none
var missingOptionalValue = false
var omitSecondMenu = false
func nodeID(_ element: AXUIElement) -> Int {
    var pid: pid_t = 0
    _ = ApplicationServices.AXUIElementGetPid(element, &pid)
    return Int(pid) - 700_000
}
func AXIsProcessTrusted() -> Bool { true }
func AXUIElementCreateApplication(_ pid: pid_t) -> AXUIElement { nodes[0] }
@discardableResult
func AXUIElementSetMessagingTimeout(_ element: AXUIElement, _ timeout: Float) -> AXError { .success }
func childIDs(_ id: Int) -> [Int] {
    switch id {
    case 1: return omitSecondMenu ? [2] : [2, 3]
    case 2: return [4]
    case 3: return [5]
    default: return []
    }
}
func AXUIElementGetAttributeValueCount(_ element: AXUIElement, _ attribute: CFString,
                                     _ count: UnsafeMutablePointer<CFIndex>) -> AXError {
    if fault == .count && nodeID(element) == 3 { return .cannotComplete }
    let children = childIDs(nodeID(element))
    if children.isEmpty { return .attributeUnsupported }
    count.pointee = children.count
    return .success
}
func AXUIElementCopyAttributeValues(_ element: AXUIElement, _ attribute: CFString, _ index: CFIndex,
                                   _ maxValues: CFIndex, _ result: UnsafeMutablePointer<CFArray?>) -> AXError {
    let id = nodeID(element)
    if fault == .children && id == 3 || fault == .allMenus && id == 1 { return .cannotComplete }
    if fault == .vanishedChildren && id == 3 { return .noValue }
    let children = fault == .shortChildren && id == 3 ? [] : childIDs(id)
    result.pointee = Array(children.dropFirst(index).prefix(maxValues)).map { nodes[$0] } as CFArray
    return .success
}
func AXUIElementCopyAttributeValue(_ element: AXUIElement, _ attribute: CFString,
                                  _ result: UnsafeMutablePointer<CFTypeRef?>) -> AXError {
    let id = nodeID(element)
    let attribute = attribute as String
    if id == 5 && ((fault == .title && attribute == kAXTitleAttribute) ||
        (fault == .role && attribute == kAXRoleAttribute) ||
        (fault == .character && attribute == kAXMenuItemCmdCharAttribute) ||
        (fault == .modifiers && attribute == kAXMenuItemCmdModifiersAttribute)) { return .cannotComplete }
    switch attribute {
    case kAXMenuBarAttribute where id == 0: result.pointee = nodes[1]
    case kAXTitleAttribute: result.pointee = (["App", "Bar", "Edit", "Other", "Copy", "Paste"][id] as CFString)
    case kAXRoleAttribute: result.pointee = ((id >= 4 ? kAXMenuItemRole : kAXMenuBarItemRole) as CFString)
    case kAXMenuItemCmdCharAttribute where id >= 4: result.pointee = ((id == 4 ? "C" : "V") as CFString)
    case kAXMenuItemCmdModifiersAttribute where id >= 4: result.pointee = NSNumber(value: 0)
    case kAXEnabledAttribute: result.pointee = NSNumber(value: true)
    default: return missingOptionalValue ? .noValue : .attributeUnsupported
    }
    return .success
}

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    checks += 1
}
let emptyCatalog = try Catalog(entries: [])
let scope = "com.example.review"
let reader = AccessibilityMenuReader(catalog: emptyCatalog)
func readMenu() -> ShortcutSnapshot {
    var result: ShortcutSnapshot?
    reader.read(pid: 700_000, scope: scope) { result = $0 }
    let deadline = Date().addingTimeInterval(5)
    while result == nil && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    guard let result else { fatalError("Reader did not complete") }
    return result
}
let full = readMenu()
check(full.state == .ready && full.entries.count == 2, "Complete menu must be ready")
missingOptionalValue = true
check(readMenu().state == .ready, "Absent optional attributes must not make every scan partial")
missingOptionalValue = false
for failure in [Fault.count, .children, .vanishedChildren, .shortChildren, .title, .role, .character, .modifiers] {
    fault = failure
    let result = readMenu()
    check(result.state == .partial && result.entries.count == 1, "Failure \(failure) must be partial")
    var library = LibraryDocument()
    library.rememberApp(bundleIdentifier: scope, name: "Review", entries: full.entries)
    library.rememberApp(bundleIdentifier: scope, name: "Review", entries: result.entries, partial: result.state == .partial)
    check(library.apps.first?.entries.count == 2, "Failure \(failure) must preserve saved menus")
}
fault = .allMenus
check(readMenu().state == .unavailable, "Whole menu failure must be unavailable")
fault = .none
var truncated = false
let limited = AXRead.children(nodes[1], limit: 1, onIncomplete: { truncated = true })
check(truncated && limited.count == 1, "Truncated children must signal incomplete data")
omitSecondMenu = true
let smaller = readMenu()
var library = LibraryDocument()
library.rememberApp(bundleIdentifier: scope, name: "Review", entries: full.entries)
library.rememberApp(bundleIdentifier: scope, name: "Review", entries: smaller.entries, partial: smaller.state == .partial)
check(smaller.state == .ready && library.apps.first?.entries.count == 1, "A complete scan must still remove obsolete menus")

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cheatble-behavior-" + UUID().uuidString)
let defaultsName = "app.cheatble.behavior." + UUID().uuidString
let defaults = UserDefaults(suiteName: defaultsName)!
defer {
    try? FileManager.default.removeItem(at: directory)
    defaults.removePersistentDomain(forName: defaultsName)
}
let oldKeys = "Control+Option+Command+F20"
let newKeys = "Control+Option+Command+F19"
let pack = AppShortcutPack(bundleIdentifier: scope, appName: "Review", shortcuts: [
    .init(id: "review.action", title: "Review action", category: "Review", keys: oldKeys)
])
try AppPackStorage(directory: directory.appendingPathComponent("Packs")).install(pack)
var edited = try pack.entries()[0]
edited.source = .user
edited.sequence = try KeySequence.parse(newKeys + " → X")
var editedLibrary = LibraryDocument()
editedLibrary.entries = [edited]
let libraryURL = directory.appendingPathComponent("library.json")
try LibraryStorage(url: libraryURL).save(editedLibrary)
try ToggleShortcut.parse(oldKeys).save(to: defaults)
let model = AppModel(catalog: emptyCatalog, defaults: defaults, storageURL: libraryURL)
var registered: ToggleShortcut?
model.onToggleShortcutChange = { registered = $0 }
model.activateToggleShortcut()
check(model.shortcuts(for: scope) == [edited], "Visible list must prefer the override")
check(model.toggleShortcutRegistered && registered == model.toggleShortcut, "Overridden pack key must be reusable")
check(!model.updateToggleShortcut(newKeys), "First chord of the effective sequence must still conflict")
check(registered == model.toggleShortcut, "Rejected change must keep the prior registration")
model.removeEntry(edited)
check(!model.toggleShortcutRegistered && registered == nil, "Removing override must suspend a now-conflicting hot key")
check(model.saveEntry(edited) && model.toggleShortcutRegistered && registered != nil, "Restoring override must restore the freed hot key")
let other = ShortcutEntry(scope: "com.example.other", actionID: edited.actionID, title: "Other action", category: "Review",
                      sequence: try KeySequence.parse(oldKeys), source: .user)
check(model.saveEntry(other) && !model.toggleShortcutRegistered, "An identical chord in another scope must still conflict")
model.removeEntry(other)
check(model.toggleShortcutRegistered, "Removing the other conflict must restore registration")
check(model.updateToggleShortcut(oldKeys, enabled: false), "Disable toggle for navigation test")
var navigation: [NavigationAction: ToggleShortcut] = [:]
model.onNavigationShortcutChange = { navigation[$0] = $1 }
check(model.updateNavigationShortcut(.system, text: oldKeys), "Navigation must also accept overridden pack keys")
model.removeEntry(edited)
check(!model.navigationRegistered.contains(.system) && navigation[.system] == nil, "Removing override must suspend conflicting navigation")
check(model.saveEntry(edited) && model.navigationRegistered.contains(.system), "Restoring override must restore navigation")

let future = ShortcutEntry(scope: "macOS", actionID: "future", title: "Future action", category: "Review",
                          sequence: try KeySequence.parse(newKeys), minimumOS: ProcessInfo.processInfo.operatingSystemVersion.majorVersion + 1)
let osModel = AppModel(catalog: try Catalog(entries: [future]), defaults: defaults,
                       storageURL: directory.appendingPathComponent("os/library.json"))
osModel.onToggleShortcutChange = { _ in }
check(osModel.updateToggleShortcut(newKeys), "Unsupported OS entries must not block a hot key")
print("App behavior: \(checks) checks passed (no GUI or global hot-key registration).")
