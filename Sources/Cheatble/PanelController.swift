import AppKit
import SwiftUI
import Combine
import CheatbleCore

final class OverlayPanel: NSPanel {
    var isDragging = false
    var didDrag: ((CGRect) -> Void)?
    override var canBecomeMain: Bool { false }
    override var canBecomeKey: Bool { true }
}

final class PassiveHostingView<Content: View>: NSHostingView<Content> {
    override var needsPanelToBecomeKey: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

final class PanelController: NSObject, NSWindowDelegate {
    let panel: OverlayPanel
    private let model: AppModel
    private var subscriptions = Set<AnyCancellable>()
    private var displayObserver: NSObjectProtocol?
    private var lastScreenID: NSNumber?
    private var windowFrame: CGRect?
    private var placing = false

    init(model: AppModel) {
        self.model = model
        panel = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 640),
                             styleMask: [.borderless, .resizable, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        super.init()
        panel.title = "Cheatble"
        panel.identifier = NSUserInterfaceItemIdentifier("CheatbleOverlay")
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.isMovable = true
        panel.didDrag = { [weak self] frame in
            self?.model.preferences.position = frame.origin
            self?.place()
        }
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.minSize = CGSize(width: 240, height: 320)
        panel.contentView = PassiveHostingView(rootView: OverlayView(model: model))
        model.$preferences
            .map { $0.clamped().backgroundOpacity }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] opacity in self?.panel.alphaValue = opacity }
            .store(in: &subscriptions)
        model.$preferences
            .removeDuplicates { $0.width == $1.width && $0.height == $1.height && $0.position == $1.position }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.place() }
            .store(in: &subscriptions)
        model.onWindowFrame = { [weak self] frame in self?.windowFrame = frame; self?.place() }
        model.releaseSearchFocus = { [weak self] in self?.releaseSearchFocus() }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in self?.place() }
        place()
    }
    deinit { if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) } }
    func show() {
        place()
        panel.orderFrontRegardless()
    }
    func hide() {
        model.isAppPickerPresented = false
        releaseSearchFocus()
        panel.orderOut(nil)
    }
    func releaseSearchFocus() {
        if panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            panel.resignKey()
        }
    }
    func place() {
        guard !placing, !panel.isDragging, !NSScreen.screens.isEmpty else { return }
        placing = true; defer { placing = false }
        let screens = NSScreen.screens
        let previous = screens.firstIndex { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == lastScreenID } ?? 0
        let cocoaFrame = windowFrame.map { PanelGeometry.fromAccessibility($0, primaryScreenTop: screens[0].frame.maxY) }
        let manualFrame = model.preferences.position.map {
            CGRect(origin: $0, size: CGSize(width: model.preferences.width, height: model.preferences.height))
        }
        let index = PanelGeometry.screenIndex(for: manualFrame ?? cocoaFrame, screens: screens.map(\.frame), fallback: previous) ?? 0
        let screen = screens[index]
        lastScreenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let frame = PanelGeometry.frame(in: screen.visibleFrame,
            requestedSize: CGSize(width: model.preferences.width, height: model.preferences.height), origin: model.preferences.position)
        panel.minSize = CGSize(width: min(240, frame.width), height: min(320, frame.height))
        panel.maxSize = CGSize(width: max(frame.width, min(2400, screen.visibleFrame.width - 32)),
                               height: max(frame.height, min(1400, screen.visibleFrame.height - 32)))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
    func windowDidResize(_ notification: Notification) {
        guard !placing else { return }
        var preferences = model.preferences
        preferences.width = panel.frame.width
        preferences.height = panel.frame.height
        if preferences.position != nil { preferences.position = panel.frame.origin }
        model.preferences = preferences.clamped()
        place()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
}

struct MoveHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView(frame: .zero) }
    func updateNSView(_ nsView: DragView, context: Context) {}
    final class DragView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            toolTip = "드래그하여 시트 위치 이동"
            setAccessibilityLabel(toolTip)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override var needsPanelToBecomeKey: Bool { false }
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) {
            guard let panel = window as? OverlayPanel else { return }
            let initial = panel.frame.origin
            panel.isDragging = true
            NSCursor.closedHand.push()
            panel.performDrag(with: event)
            NSCursor.pop()
            panel.isDragging = false
            if panel.frame.origin != initial { panel.didDrag?(panel.frame) }
        }
    }
}

struct ResizeHandle: NSViewRepresentable {
    enum Edge { case left, bottom, corner }
    let edge: Edge
    func makeNSView(context: Context) -> ResizeView { ResizeView(edge: edge) }
    func updateNSView(_ nsView: ResizeView, context: Context) {}

    final class ResizeView: NSView {
        let edge: Edge
        init(edge: Edge) {
            self.edge = edge; super.init(frame: .zero)
            toolTip = edge == .corner ? "드래그하여 너비와 높이 조절" : edge == .left ? "드래그하여 너비 조절" : "드래그하여 높이 조절"
            setAccessibilityLabel(toolTip)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override var needsPanelToBecomeKey: Bool { false }
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            guard edge == .corner else { return }
            NSColor.secondaryLabelColor.withAlphaComponent(0.7).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            for length in [CGFloat(5), 10, 15] {
                path.move(to: NSPoint(x: 7, y: 7 + length))
                path.line(to: NSPoint(x: 7 + length, y: 7))
            }
            path.stroke()
        }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: edge == .left ? .resizeLeftRight : edge == .bottom ? .resizeUpDown : .crosshair)
        }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let initial = window.frame
            let start = NSEvent.mouseLocation
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let point = NSEvent.mouseLocation
                var size = initial.size
                if edge != .bottom { size.width = initial.width - (point.x - start.x) }
                if edge != .left { size.height = initial.height - (point.y - start.y) }
                size.width = min(window.maxSize.width, max(window.minSize.width, size.width))
                size.height = min(window.maxSize.height, max(window.minSize.height, size.height))
                window.setFrame(CGRect(x: initial.maxX - size.width, y: initial.maxY - size.height,
                                       width: size.width, height: size.height), display: true)
            }
        }
    }
}

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder = "동작이나 단축키 검색"
    var onEnd: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Input {
        let input = Input()
        input.placeholderString = placeholder
        input.font = .systemFont(ofSize: 12)
        input.isBordered = false
        input.isBezeled = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.cell?.usesSingleLineMode = true
        input.delegate = context.coordinator
        input.setAccessibilityLabel(placeholder)
        return input
    }
    func updateNSView(_ nsView: Input, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text { nsView.stringValue = text }
    }
    final class Input: NSTextField {
        override var needsPanelToBecomeKey: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.makeKey()
            super.mouseDown(with: event)
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if !parent.text.isEmpty { parent.text = ""; control.stringValue = "" }
                else { parent.onEnd() }
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { parent.onEnd(); return true }
            return false
        }
    }
}
