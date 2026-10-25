import AppKit
import ApplicationServices

struct ActiveAppContext {
    var pid: pid_t
    var bundleIdentifier: String
    var name: String
    var icon: NSImage?
    var accessibilityWindowFrame: CGRect?
    var cacheKey: String { "\(pid):\(bundleIdentifier)" }
}

final class ActiveAppTracker {
    var onAppChange: ((ActiveAppContext) -> Void)?
    var onWindowChange: ((CGRect?) -> Void)?
    var onMenuChange: (() -> Void)?
    private(set) var context: ActiveAppContext?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var observer: AXObserver?
    private var observedApp: AXUIElement?
    private var observedWindow: AXUIElement?
    private let windowQueue = DispatchQueue(label: "app.cheatble.window", qos: .userInitiated)
    private var windowRequest = 0
    private var pendingWindow: DispatchWorkItem?

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.activate(app)
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshWindow()
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == self.context?.pid else { return }
            self.detachObserver()
            if let front = NSWorkspace.shared.frontmostApplication { self.activate(front) }
        })
        if let app = NSWorkspace.shared.frontmostApplication { activate(app) }
    }

    func stop() {
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
        pendingWindow?.cancel()
        detachObserver()
    }
    func permissionsChanged() {
        detachObserver()
        attachObserver()
        refreshWindow()
    }
    private func activate(_ app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular, !app.isTerminated else { return }
        let scope = app.bundleIdentifier ?? "process.\(app.processIdentifier)"
        if context?.pid == app.processIdentifier { refreshWindow(); return }
        detachObserver()
        context = ActiveAppContext(pid: app.processIdentifier, bundleIdentifier: scope,
                                   name: app.localizedName ?? "현재 앱", icon: app.icon)
        if let context { onAppChange?(context) }
        attachObserver()
        refreshWindow()
    }
    private func attachObserver() {
        guard AXIsProcessTrusted(), let context else { return }
        var result: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<ActiveAppTracker>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            if name == kAXMenuClosedNotification {
                tracker.onMenuChange?()
            } else { tracker.refreshWindow() }
        }
        guard AXObserverCreate(context.pid, callback, &result) == .success, let result else { return }
        observer = result
        let app = AXUIElementCreateApplication(context.pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        observedApp = app
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXMenuClosedNotification] {
            _ = AXObserverAddNotification(result, app, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(result), .commonModes)
    }
    private func detachObserver() {
        windowRequest += 1
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil; observedApp = nil; observedWindow = nil
    }
    func refreshWindow() {
        pendingWindow?.cancel()
        let pending = DispatchWorkItem { [weak self] in self?.readWindow() }
        pendingWindow = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: pending)
    }
    private func readWindow() {
        guard AXIsProcessTrusted(), let context else { onWindowChange?(nil); return }
        windowRequest += 1
        let request = windowRequest
        windowQueue.async { [weak self] in
            let app = AXUIElementCreateApplication(context.pid)
            AXUIElementSetMessagingTimeout(app, 0.1)
            let window = AXRead.element(app, kAXFocusedWindowAttribute) ?? AXRead.element(app, kAXMainWindowAttribute)
            if let window { AXUIElementSetMessagingTimeout(window, 0.1) }
            let frame = window.flatMap { AXRead.frame($0) }
            DispatchQueue.main.async {
                guard let self, self.windowRequest == request, self.context?.pid == context.pid else { return }
                self.context?.accessibilityWindowFrame = frame
                self.observeWindow(window)
                self.onWindowChange?(frame)
            }
        }
    }
    private func observeWindow(_ window: AXUIElement?) {
        guard let observer else { return }
        if let old = observedWindow, let window, CFEqual(old, window) { return }
        if let old = observedWindow {
            for name in [kAXMovedNotification, kAXResizedNotification] {
                _ = AXObserverRemoveNotification(observer, old, name as CFString)
            }
        }
        observedWindow = window
        if let window {
            for name in [kAXMovedNotification, kAXResizedNotification] {
                _ = AXObserverAddNotification(observer, window, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
    }
}
