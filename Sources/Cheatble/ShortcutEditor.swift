import AppKit
import SwiftUI
import CheatbleCore

struct ShortcutEditor: View {
    @ObservedObject var model: AppModel
    let original: ShortcutEntry?
    var close: () -> Void
    @State private var scope: String
    @State private var title: String
    @State private var category: String
    @State private var keys: String
    @State private var detail: String
    @State private var validation: String?

    init(model: AppModel, original: ShortcutEntry?, scope: String? = nil, close: @escaping () -> Void) {
        self.model = model; self.original = original; self.close = close
        _scope = State(initialValue: original?.scope ?? scope ?? (model.scope == "unknown" ? "macOS" : model.scope))
        _title = State(initialValue: original?.title ?? "")
        _category = State(initialValue: original?.category ?? "내 단축키")
        _keys = State(initialValue: original.map { KeySequence.editable($0.sequence) } ?? "")
        _detail = State(initialValue: original?.detail ?? "")
    }
    private var preview: [KeyChord]? { try? KeySequence.parse(keys) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(original == nil ? "단축키 추가" : "단축키 수정").font(.title2.bold())
            Text("직접 기록한 내용은 앱 메뉴와 기본 목록보다 우선합니다.")
                .font(.callout).foregroundStyle(.secondary)
            Form {
                TextField("대상", text: $scope).disabled(original != nil)
                if original == nil {
                    HStack {
                        Button("macOS") { scope = "macOS" }
                        if let app = model.activeApp {
                            Button(app.name) { scope = app.bundleIdentifier }
                        }
                    }
                }
                TextField("동작 이름", text: $title)
                TextField("그룹", text: $category)
                TextField("키 조합", text: $keys, prompt: Text("Command+Shift+4"))
                TextField("설명", text: $detail, axis: .vertical).lineLimit(3...5)
            }
            if let preview {
                HStack {
                    Text("미리 보기").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Keycaps(sequence: preview, inlineSequence: scope.trimmingCharacters(in: .whitespacesAndNewlines) == "org.tmux.tmux")
                }
            }
            Text("예: ⌘⇧4, Control+Option+K, Fn+Q\n연속 입력: Command+Shift+4 → Space\n화살표는 Left·Right·Up·Down, 더하기 키는 Plus로 입력하세요.\n대상은 macOS 또는 앱의 번들 ID입니다. 예: com.apple.Safari")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("취소", action: close).keyboardShortcut(.cancelAction)
                Button("저장", action: save).keyboardShortcut(.defaultAction)
                    .disabled(preview == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 470, height: 480)
            .background(Color(nsColor: .windowBackgroundColor))
            .tint(CheatbleStyle.accent)
    }
    private func save() {
        guard let sequence = preview else { validation = ShortcutParseError.invalid.localizedDescription; return }
        let entry = ShortcutEntry(
            scope: scope.trimmingCharacters(in: .whitespacesAndNewlines),
            actionID: original?.actionID ?? "custom.\(UUID().uuidString)",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            sequence: sequence, source: .user, detail: detail,
            aliases: original?.aliases ?? [], menuPath: original?.menuPath ?? [],
            minimumOS: original?.minimumOS, maximumOS: original?.maximumOS,
            sourceURL: original?.sourceURL)
        guard entry.isValid else { validation = "대상·이름·그룹을 입력해 주세요."; return }
        if model.saveEntry(entry) { close() }
        else { validation = model.error }
    }
}

final class EditorWindowController: NSWindowController {
    init(model: AppModel, entry: ShortcutEntry?, scope: String? = nil) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 518, height: 528),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = entry == nil ? "Cheatble — 단축키 추가" : "Cheatble — 단축키 수정"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: ShortcutEditor(model: model, original: entry, scope: scope) { [weak self] in self?.close() })
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
