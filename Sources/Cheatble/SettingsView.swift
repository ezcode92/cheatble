import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CheatbleCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmReset = false
    @State private var notice: String?
    @State private var toggleKeys = ""
    @State private var showDeepScanConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(nsImage: CheatbleStyle.appIcon).resizable().interpolation(.high).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cheatble").font(.title2.bold())
                        Text("작업 곁에 두는 단축키 시트").foregroundStyle(.secondary)
                    }
                }
                GroupBox("오버레이") {
                    VStack(alignment: .leading, spacing: 14) {
                        settingSlider("너비", value: $model.preferences.width, range: 240...min(2400, max(240, NSScreen.main?.visibleFrame.width ?? 1440)), unit: "pt")
                        settingSlider("높이", value: $model.preferences.height, range: 320...1400, unit: "pt")
                        HStack {
                            Text("전체 불투명도").frame(width: 95, alignment: .leading)
                            Slider(value: $model.preferences.backgroundOpacity, in: 0.2...1)
                            Text("\(Int(model.preferences.backgroundOpacity * 100))%")
                                .monospacedDigit().frame(width: 50, alignment: .trailing)
                        }
                        Text("상단 CHEATBLE 영역을 드래그해 위치를 옮깁니다. 왼쪽 아래 손잡이나 가장자리로 크기를 조절하면 너비에 따라 1·2·3단으로 표시됩니다. 불투명도는 시트 전체에 적용됩니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("자동 오른쪽 배치로 되돌리기") { model.preferences.position = nil }
                            .disabled(model.preferences.position == nil)
                    }.padding(10)
                }
                GroupBox("시트 열기·닫기 단축키") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Toggle("사용", isOn: Binding(
                                get: { model.toggleShortcutEnabled },
                                set: { model.updateToggleShortcut(KeySequence.editable([model.toggleShortcut.chord]), enabled: $0) }
                            )).toggleStyle(.switch)
                            Spacer()
                            Keycaps(sequence: [model.toggleShortcut.chord])
                        }
                        HStack {
                            TextField("Control+Option+Command+Return", text: $toggleKeys)
                                .textFieldStyle(.roundedBorder)
                            Button("적용") { model.updateToggleShortcut(toggleKeys) }
                            Button("기본값") {
                                model.updateToggleShortcut(KeySequence.editable([ToggleShortcut.standard.chord]))
                            }
                        }
                        Text("다른 앱에서 작업 중에도 시트를 열고 닫습니다. 표시된 키를 함께 누르세요. 변경할 때 Control 또는 Command를 포함해 보조 키 두 개 이상을 사용하세요.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = model.toggleShortcutError {
                            Text(error).font(.caption).foregroundStyle(.red)
                        } else if model.toggleShortcutRegistered {
                            Text("사용 중 · 앱이 실행되어 있을 때 동작").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(10)
                }
                GroupBox("목록 전환 단축키") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("기본값: 왼손으로 ⌃⌥⌘, 오른손으로 J·K·;를 누르세요. 시트 열기·닫기는 오른손 Return을 사용합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(NavigationAction.allCases) { action in
                            NavigationShortcutSetting(model: model, action: action)
                        }
                    }.padding(10)
                }
                GroupBox("앱별 단축키") {
                    HStack {
                        Text("앱마다 단축키 추가·수정, 즐겨찾기와 익힘 표시를 관리합니다.").font(.caption)
                        Spacer()
                        Button("앱별 단축키 설정…") { model.openShortcutSettings?() }
                    }.padding(10)
                }
                GroupBox("앱 메뉴 읽기") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.hasPermission ? "손쉬운 사용 권한이 허용되어 있습니다" : "손쉬운 사용 권한이 필요합니다",
                              systemImage: model.hasPermission ? "checkmark.circle" : "hand.raised")
                        Text("macOS 기본 목록과 저장된 단축키 목록은 권한 없이도 사용할 수 있습니다. 앱의 실제 메뉴와 활성 창 위치를 읽을 때만 권한을 사용합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("손쉬운 사용 설정 열기") { model.requestPermission() }
                        HStack {
                            Button("현재 앱 메뉴 새로고침") { model.refresh() }
                            Button("메뉴 더 읽기…") { showDeepScanConfirmation = true }
                        }.disabled(!model.hasPermission || model.isLoading)
                        Text(model.statusText).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                GroupBox("저장된 앱 · 추가 목록") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("저장된 앱 \(model.savedApps.count)개 · 추가 목록 \(model.packs.count)개").font(.callout)
                        Text("앱 메뉴를 읽으면 목록을 저장합니다. 상단 세 번째 아이콘 옆 ∨를 열어 앱 아이콘을 선택하면 다른 앱에서 작업 중에도 목록을 유지합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("추가 목록 가져오기…") { model.openPackImport?() }
                            Button("저장 폴더 열기") { model.openPacksFolder() }
                            Button("새로고침") { model.reloadPacks() }
                            Button("현재 앱 저장") { model.saveCurrentApp() }.disabled(model.activeApp == nil)
                        }
                        Text("단축키가 없는 앱에서는 ‘추가 요청 복사’를 눌러 대화에 붙여 넣으세요. 완성된 목록을 추가하면 앱이 자동으로 반영합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(model.packIssues, id: \.self) { issue in
                            Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                GroupBox("내 목록") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("직접 추가·수정 \(model.library.entries.count)개 · 즐겨찾기 \(model.library.favorites.count)개 · 익힘 \(model.library.learned.count)개")
                            .font(.callout)
                        HStack {
                            Button("JSON 가져오기…") { importFile() }
                            Button("JSON 내보내기…") { exportFile() }
                            Button("익힘 표시 초기화…") { confirmReset = true }
                                .disabled(model.library.learned.isEmpty)
                        }
                        Text("가져온 목록을 합칩니다. 같은 동작을 직접 수정한 항목은 가져온 값이 우선합니다. 기본 단축키는 앱에 포함되어 있습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        if model.storageNeedsRecovery {
                            Button("손상된 원본을 백업하고 새 목록 시작") { model.recoverLibrary() }
                        }
                        if let error = model.error {
                            Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        }
                        if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                        Button("목록 저장 폴더 열기") {
                            let directory = model.storage.url.deletingLastPathComponent()
                            do {
                                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                                NSWorkspace.shared.open(directory)
                            } catch { model.error = error.localizedDescription }
                        }.buttonStyle(.link)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                Text("로컬에서 동작하며 계정·서버·구독이 없습니다. 키 입력을 기록하거나 단축키를 대신 실행하지 않습니다. 변경한 키 조합은 앱별 단축키 설정에서 수정할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .frame(minWidth: 520, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(CheatbleStyle.accent)
        .onAppear { toggleKeys = KeySequence.editable([model.toggleShortcut.chord]) }
        .onChange(of: model.toggleShortcut) { toggleKeys = KeySequence.editable([$0.chord]) }
        .confirmationDialog("메뉴 더 읽기", isPresented: $showDeepScanConfirmation, titleVisibility: .visible) {
            Button("메뉴를 잠시 열어 읽기") { model.refresh(deep: true) }
        } message: { Text("현재 앱의 메뉴를 잠시 열었다 닫아 숨겨진 단축키를 찾습니다. 메뉴 명령은 실행하지 않습니다.") }
        .confirmationDialog("모든 익힘 표시를 지울까요?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("익힘 표시 초기화", role: .destructive) { model.resetLearned() }
        } message: { Text("숨겨졌던 단축키가 다시 나타납니다. 단축키와 즐겨찾기는 유지됩니다.") }
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack {
            Text(title).frame(width: 95, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue))\(unit)").monospacedDigit().frame(width: 50, alignment: .trailing)
        }
    }
    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Cheatble에서 내보낸 단축키 목록을 선택하세요."
        if panel.runModal() == .OK, let url = panel.url {
            model.error = nil
            model.importLibrary(from: url)
            notice = model.error == nil ? "목록을 가져왔습니다." : nil
        }
    }
    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Cheatble-shortcuts.json"
        if panel.runModal() == .OK, let url = panel.url {
            model.error = nil
            model.exportLibrary(to: url)
            notice = model.error == nil ? "목록을 내보냈습니다." : nil
        }
    }
}

private struct NavigationShortcutSetting: View {
    @ObservedObject var model: AppModel
    let action: NavigationAction
    @State private var text = ""
    private var shortcut: ToggleShortcut { model.navigationShortcuts[action] ?? action.standard }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(action.title, isOn: Binding(get: { model.navigationEnabled[action] == true }, set: {
                    model.updateNavigationShortcut(action, text: KeySequence.editable([shortcut.chord]), enabled: $0)
                })).toggleStyle(.switch)
                Spacer()
                Keycaps(sequence: [shortcut.chord])
            }
            HStack {
                TextField("키 조합", text: $text).textFieldStyle(.roundedBorder)
                Button("적용") { model.updateNavigationShortcut(action, text: text) }
                Button("기본값") { model.updateNavigationShortcut(action, text: KeySequence.editable([action.standard.chord])) }
            }
            if let error = model.navigationErrors[action] { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { text = KeySequence.editable([shortcut.chord]) }
        .onChange(of: shortcut) { text = KeySequence.editable([$0.chord]) }
    }
}

final class SettingsWindowController: NSWindowController {
    init(model: AppModel) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 670),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Cheatble 설정"
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
