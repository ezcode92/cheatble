import AppKit
import SwiftUI

/// Keeps keyboard input inside the picker without activating Cheatble as the working app.
struct AppPickerSearchField: NSViewRepresentable {
    enum Direction { case left, right, up, down }
    @Binding var text: String
    var highlightedID: String?
    var move: (Direction) -> Void
    var choose: () -> Void
    var dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Input {
        let input = Input()
        input.placeholderString = "앱 이름 검색"
        input.font = .systemFont(ofSize: 12)
        input.isBordered = false
        input.isBezeled = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.cell?.usesSingleLineMode = true
        input.delegate = context.coordinator
        input.setAccessibilityLabel("앱 이름 검색")
        input.setAccessibilityHelp("방향키로 앱 이동, Return으로 선택, Escape로 닫기")
        return input
    }
    func updateNSView(_ input: Input, context: Context) {
        context.coordinator.parent = self
        if input.stringValue != text { input.stringValue = text }
        input.highlightedID = highlightedID
    }
    static func dismantleNSView(_ input: Input, coordinator: Coordinator) {
        input.releaseKeyboardFocus()
        input.delegate = nil
    }
    final class Input: NSTextField {
        private(set) var focusRequested = false
        var highlightedID: String?
        override var needsPanelToBecomeKey: Bool { true }
        func releaseKeyboardFocus() {
            guard let window, window.isKeyWindow else { return }
            window.makeFirstResponder(nil)
            window.resignKey()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { focusRequested = false; return }
            guard !focusRequested else { return }
            focusRequested = true
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window, window.isVisible else { return }
                window.makeKey()
                window.makeFirstResponder(self)
            }
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AppPickerSearchField
        init(_ parent: AppPickerSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let input = notification.object as? NSTextField { parent.text = input.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Let an input method finish composing text before handling navigation.
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveLeft(_:)): parent.move(.left)
            case #selector(NSResponder.moveRight(_:)): parent.move(.right)
            case #selector(NSResponder.moveUp(_:)): parent.move(.up)
            case #selector(NSResponder.moveDown(_:)): parent.move(.down)
            case #selector(NSResponder.insertNewline(_:)):
                guard parent.highlightedID != nil else { return true }
                (control as? Input)?.releaseKeyboardFocus()
                parent.choose()
            case #selector(NSResponder.cancelOperation(_:)):
                (control as? Input)?.releaseKeyboardFocus()
                parent.dismiss()
            default: return false
            }
            return true
        }
    }
}
