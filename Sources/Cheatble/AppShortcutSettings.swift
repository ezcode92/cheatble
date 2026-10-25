import AppKit
import SwiftUI
import CheatbleCore

struct AppShortcutSettingsView: View {
    @ObservedObject var model: AppModel
    @State var scope: String
    @State private var query = ""
    let edit: (ShortcutEntry?, String) -> Void

    private var choices: [AppModel.SavedChoice] {
        var apps = model.savedApps
        if let active = model.activeApp, AppScope.isValid(active.bundleIdentifier),
           !apps.contains(where: { $0.id == active.bundleIdentifier }) {
            apps.append(.init(id: active.bundleIdentifier, name: active.name))
        }
        if AppScope.isValid(scope), !apps.contains(where: { $0.id == scope }) {
            apps.append(.init(id: scope, name: model.appName(for: scope)))
        }
        return [.init(id: "macOS", name: "macOS")] + apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var entries: [ShortcutEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.shortcuts(for: scope, includeLiveMenu: scope == model.activeApp?.bundleIdentifier).filter {
            query.isEmpty || [$0.title, $0.category, KeySequence.editable($0.sequence)].contains { $0.localizedStandardContains(query) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("앱별 단축키 설정").font(.title2.bold())
            HStack {
                Picker("앱", selection: $scope) {
                    ForEach(choices) { app in Text(app.name).tag(app.id) }
                }.frame(maxWidth: 310)
                Spacer()
                Button("단축키 추가…") { edit(nil, scope) }
            }
            TextField("동작·카테고리·키 조합 검색", text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Text("\(entries.count)개").monospacedDigit()
                Spacer()
                Text("즐겨찾기 · 익힘 표시 · 직접 수정").foregroundStyle(.secondary)
            }.font(.caption)
            Divider()
            if entries.isEmpty {
                Text("표시할 단축키가 없습니다.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(entries) { entry in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title).font(.system(size: 12, weight: .medium))
                                    Text(entry.category).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Keycaps(sequence: entry.sequence, inlineSequence: entry.scope == "org.tmux.tmux")
                                Button { model.toggleFavorite(entry) } label: {
                                    Image(systemName: model.library.favorites.contains(entry.id) ? "star.fill" : "star")
                                }.help("즐겨찾기 전환").accessibilityLabel("\(entry.title) 즐겨찾기")
                                Toggle("익힘", isOn: Binding(get: { model.library.learned.contains(entry.id) },
                                                          set: { _ in model.toggleLearned(entry) }))
                                    .toggleStyle(.checkbox).fixedSize()
                                Button("수정") { edit(entry, scope) }
                                Menu {
                                    if entry.source == .user {
                                        Button("직접 추가·수정한 값 제거", role: .destructive) { model.removeEntry(entry) }
                                    }
                                    Text(entry.detail ?? entry.source.label)
                                } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                                .disabled(entry.source != .user && entry.detail == nil)
                            }
                            .padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(20).frame(minWidth: 620, minHeight: 450)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(CheatbleStyle.accent)
        .onChange(of: scope) { _ in query = "" }
    }
}

final class AppShortcutSettingsWindowController: NSWindowController {
    init(model: AppModel, scope: String, edit: @escaping (ShortcutEntry?, String) -> Void) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 780, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Cheatble — 앱별 단축키 설정"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AppShortcutSettingsView(model: model,
            scope: scope == "macOS" || AppScope.isValid(scope) ? scope : "macOS", edit: edit))
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
    }
}
