import AppKit
import SwiftUI

/// Semantic AppKit colors follow light/dark mode and increased contrast.
enum CheatbleStyle {
    static let accent = Color(nsColor: .labelColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let appIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Cheatble")!
    }()
}
