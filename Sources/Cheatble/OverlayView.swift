import SwiftUI
import CheatbleCore

private let accent = CheatbleStyle.accent

struct OverlayView: View {
    @ObservedObject var model: AppModel
    @State private var showLegend = false
    private var background: Color {
        CheatbleStyle.background
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            searchAndFilters
            if model.isFollowingActiveApp && !model.hasPermission { permissionBanner }
            if let error = model.error { errorBanner(error) }
            if model.toggleShortcutEnabled, !model.toggleShortcutRegistered, let error = model.toggleShortcutError {
                errorBanner(error)
            }
            list
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .overlay(alignment: .leading) { ResizeHandle(edge: .left).frame(width: 9).padding(.vertical, 30) }
        .overlay(alignment: .bottom) { ResizeHandle(edge: .bottom).frame(height: 9).padding(.horizontal, 30) }
        .overlay(alignment: .bottomLeading) { ResizeHandle(edge: .corner).frame(width: 30, height: 30) }
        .tint(accent)

    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(nsImage: CheatbleStyle.appIcon).resizable().interpolation(.high).frame(width: 22, height: 22)
                    Text("CHEATBLE").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2.1)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                }.frame(maxWidth: .infinity, minHeight: 26).overlay { MoveHandle() }
                smallButton("물음표", symbol: "questionmark.circle") { showLegend.toggle() }
                    .popover(isPresented: $showLegend, arrowEdge: .bottom) { legend.padding(20) }
                smallButton("설정", symbol: "slider.horizontal.3") { model.openSettings?() }
                smallButton("시트 숨기기", symbol: "xmark") { model.hidePanel?() }
            }
            HStack(spacing: 8) {
                tab(selection: "app", name: "현재 앱 자동 전환: \(model.activeApp?.name ?? "현재 앱")",
                    icon: model.activeApp?.icon, symbol: "app.dashed", live: true)
                    .accessibilityIdentifier("scope.active").help("현재 앱 자동 전환" + model.navigationHint(.activeApp))
                tab(selection: "macOS", name: "macOS 기본 단축키", symbol: "apple.logo")
                    .accessibilityIdentifier("scope.system").help("macOS 단축키" + model.navigationHint(.system))
                savedAppSelector
                Text(model.isSystem ? "macOS" : model.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(model.title)
            }.frame(height: 38)

        }.padding(14)
    }
    private var savedAppSelector: some View {
        let selected = model.preferences.savedScope != nil
        return Button {
            model.releaseSearchFocus?()
            model.isAppPickerPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                if let scope = model.preferences.savedScope, let icon = model.icon(for: scope) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 26, height: 26)
                } else {
                    Image(systemName: "square.grid.2x2").font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 26, height: 26)
                }
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 62, height: 36)
            .background(selected ? accent.opacity(0.16) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .bottom) {
                if selected { Capsule().fill(accent).frame(width: 12, height: 2).offset(y: 2) }
            }
        }
        .buttonStyle(.plain)
        .help("저장된 앱 선택" + model.navigationHint(.savedApps))
        .accessibilityLabel("저장된 앱 선택").accessibilityIdentifier("scope.saved")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .popover(isPresented: $model.isAppPickerPresented, arrowEdge: .bottom) {
            SavedAppPicker(model: model)
        }
    }
    private func tab(selection: String, name: String, icon: NSImage? = nil,
                     symbol: String, live: Bool = false) -> some View {
        let selected = model.preferences.selectedTab == selection
        return Button { model.selectTab(selection) } label: {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 26, height: 26)
                } else {
                    Image(systemName: symbol).font(.system(size: 23, weight: .medium))
                        .foregroundStyle(selected ? accent : Color.secondary)
                }
            }
            .frame(width: 37, height: 36)
            .background(selected ? accent.opacity(0.16) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .topTrailing) {
                if live { Circle().fill(accent).frame(width: 5, height: 5).padding(2) }
            }
            .overlay(alignment: .bottom) {
                if selected { Capsule().fill(accent).frame(width: 12, height: 2).offset(y: 2) }
            }
        }.buttonStyle(.plain).help(name).accessibilityLabel(name)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var searchAndFilters: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                SearchField(text: $model.query) { model.releaseSearchFocus?() }.frame(height: 19)
                if !model.query.isEmpty {
                    smallButton("검색 지우기", symbol: "xmark.circle.fill") { model.query = "" }
                }
            }.padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            HStack(spacing: 5) {
                ForEach([Modifier.command, .option, .control, .shift], id: \.self) { modifier in
                    Button {
                        if !model.modifiers.insert(modifier).inserted { model.modifiers.remove(modifier) }
                    } label: {
                        Text(modifier.symbol).font(.system(size: 16, weight: .semibold))
                            .frame(width: 29, height: 25)
                            .background(model.modifiers.contains(modifier) ? accent.opacity(0.17) : Color.primary.opacity(0.035),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(model.modifiers.contains(modifier) ? accent : .secondary)
                    }.buttonStyle(.plain).help("\(modifier.name) 키가 포함된 단축키")
                        .accessibilityLabel("\(modifier.name) 필터")
                        .accessibilityAddTraits(model.modifiers.contains(modifier) ? .isSelected : [])
                }
                Button { model.favoritesOnly.toggle() } label: {
                    Image(systemName: model.favoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(model.favoritesOnly ? accent : .secondary).frame(width: 29, height: 25)
                }.buttonStyle(.plain).help("즐겨찾기만 보기").accessibilityLabel("즐겨찾기 필터")
                Button { model.showLearned.toggle() } label: {
                    Image(systemName: model.showLearned ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(model.showLearned ? accent : .secondary).frame(width: 29, height: 25)
                }.buttonStyle(.plain).help("공부 완료한 단축키도 보기").accessibilityLabel("공부 완료한 단축키 표시 전환")
                    .accessibilityValue(model.showLearned ? "표시" : "숨김")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.raised").font(.system(size: 12)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("앱 메뉴도 함께 보세요").font(.system(size: 11, weight: .semibold))
                Text("권한 없이도 기본 목록은 볼 수 있어요.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("권한 설정") { model.requestPermission() }.buttonStyle(.borderless).font(.system(size: 10, weight: .semibold))
        }
        .padding(10).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 16).padding(.bottom, 6)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top) {
            Text(error).font(.system(size: 10)).lineLimit(3)
            Button("설정") { model.openSettings?() }.buttonStyle(.borderless)
        }.padding(10).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
    }

    private var list: some View {
        GeometryReader { geometry in
        ScrollView {
            if model.groups.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: model.query.isEmpty ? "keyboard" : "magnifyingglass")
                        .font(.system(size: 27, weight: .light)).foregroundStyle(accent.opacity(0.7))
                    Text(model.allEntries.isEmpty ? "아직 표시할 단축키가 없어요" : "조건에 맞는 단축키가 없어요")
                        .font(.system(size: 12, weight: .medium))
                    Text(model.allEntries.isEmpty ? "macOS 탭을 보거나 단축키를 직접 추가하세요." : "검색이나 필터를 바꿔 보세요.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if model.allEntries.isEmpty && model.canRequestPack {
                        Button(model.requestCopied ? "요청을 복사했어요" : "추가 요청 복사") { model.copyAdditionRequest() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        if model.requestCopied {
                            Text("대화에 붙여 넣으면 이 앱의 단축키 추가를 요청할 수 있어요.")
                                .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        Button("단축키 직접 추가…") { model.openEditor?(nil) }.buttonStyle(.borderless)
                    }
                    if !model.allEntries.isEmpty {
                        Button("필터 초기화") { model.query = ""; model.modifiers = []; model.favoritesOnly = false; model.showLearned = true }
                            .buttonStyle(.borderless)
                    }
                }.padding(.vertical, 36).frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(model.groups) { group in
                        VStack(spacing: 3) {
                            Button { model.toggleGroup(group.id) } label: {
                                HStack {
                                    Text(group.title).font(.system(size: 11, weight: .semibold))
                                    Text("\(group.entries.count)").font(.system(size: 10, design: .monospaced)).opacity(0.6)
                                    Spacer()
                                    Image(systemName: model.library.collapsedGroups.contains(group.id) ? "chevron.right" : "chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(width: 20, height: 20)
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 9)
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(group.title) 펼치기 또는 접기")
                            .accessibilityValue(model.library.collapsedGroups.contains(group.id) ? "접힘" : "펼쳐짐")
                            if !model.library.collapsedGroups.contains(group.id) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top),
                                                         count: PanelGeometry.columnCount(for: geometry.size.width)), spacing: 4) {
                                    ForEach(group.entries) { entry in
                                        ShortcutRow(entry: entry, model: model)
                                    }
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 12).padding(.bottom, 16)
            }
        }
        .id(model.scope)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var footer: some View {
        VStack(spacing: 10) {
            Divider().opacity(0.45)
            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $model.preferences.backgroundOpacity, in: 0.2...1)
                    .controlSize(.mini).accessibilityLabel("시트 전체 불투명도")
                Text("\(Int(model.preferences.backgroundOpacity * 100))%")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
            }.padding(.leading, 36).padding(.trailing, 18).padding(.bottom, 14)
        }
    }
    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("키보드 기호 읽기").font(.headline)
            ForEach(Modifier.allCases, id: \.self) { modifier in
                HStack { Text(modifier.symbol).font(.system(size: 18)).frame(width: 35); Text(modifier.name).font(.system(size: 12)) }
            }
            Divider()
            Text("한 묶음의 키는 함께 누르세요.\n‘→’ 또는 ‘↳’ 다음 키는 앞의 키를 놓고 누르세요.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("별표로 모으고, 익힌 항목은 체크해 숨기세요.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("왼쪽 아래 손잡이를 드래그하면 시트 크기가 바뀝니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(width: 245)
    }
    private func smallButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 18, height: 20).contentShape(Rectangle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct SavedAppPicker: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var highlightedID: String?
    private let columns = Array(repeating: GridItem(.fixed(52), spacing: 8, alignment: .top), count: 5)
    private var apps: [AppModel.SavedChoice] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.selectableSavedApps.filter {
            query.isEmpty || $0.name.localizedStandardContains(query) || $0.id.localizedStandardContains(query)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("저장된 앱").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(model.selectableSavedApps.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                AppPickerSearchField(text: $query, highlightedID: highlightedID,
                                     move: moveSelection, choose: chooseHighlighted,
                                     dismiss: { model.isAppPickerPresented = false })
                    .frame(height: 19)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("앱 검색 지우기")
                }
            }.padding(8).background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            if apps.isEmpty {
                Text(query.isEmpty ? "다른 저장된 앱이 없어요." : "찾는 앱이 없어요.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(apps) { app in
                            Button { model.selectTab("saved:" + app.id) } label: {
                                VStack(spacing: 5) {
                                    Group {
                                        if let icon = model.icon(for: app.id) {
                                            Image(nsImage: icon).resizable().interpolation(.high)
                                        } else { Image(systemName: "app").resizable() }
                                    }.frame(width: 32, height: 32)
                                        .frame(width: 46, height: 46)
                                        .background(model.preferences.savedScope == app.id ? accent.opacity(0.18) : Color.primary.opacity(0.04),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(highlightedID == app.id ? accent : .clear, lineWidth: 2)
                                        }
                                        .overlay(alignment: .bottomTrailing) {
                                            if model.preferences.savedScope == app.id {
                                                Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                                                    .foregroundStyle(accent).background(.background, in: Circle()).offset(x: 2, y: 2)
                                            }
                                        }
                                    Text(app.name).font(.system(size: 10)).lineLimit(2)
                                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                        .frame(width: 52, height: 28, alignment: .top)
                                }.frame(width: 52).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(app.name).accessibilityLabel("저장된 \(app.name) 선택")
                                .accessibilityAddTraits(model.preferences.savedScope == app.id ? .isSelected : [])
                                .accessibilityValue(highlightedID == app.id ? "키보드 선택 중" : "")
                                .id(app.id)
                        }
                    }.padding(.vertical, 2)
                }.frame(height: min(CGFloat((apps.count + 4) / 5) * 89, 304))
                    .onChange(of: highlightedID) { id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }.padding(16).frame(width: 324).background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                query = ""
                highlightedID = apps.first { $0.id == model.preferences.savedScope }?.id ?? apps.first?.id
            }
            .onChange(of: apps.map(\.id)) { ids in
                if !ids.contains(highlightedID ?? "") { highlightedID = ids.first }
            }
            .onDisappear {
                DispatchQueue.main.async { model.releaseSearchFocus?() }
            }
    }
    private func moveSelection(_ direction: AppPickerSearchField.Direction) {
        guard !apps.isEmpty else { highlightedID = nil; return }
        let index = apps.firstIndex { $0.id == highlightedID } ?? 0
        let next: Int
        switch direction {
        case .left: next = max(0, index - 1)
        case .right: next = min(apps.count - 1, index + 1)
        case .up: next = index >= columns.count ? index - columns.count : index
        case .down: next = index / columns.count < (apps.count - 1) / columns.count
            ? min(apps.count - 1, index + columns.count) : index
        }
        highlightedID = apps[next].id
    }
    private func chooseHighlighted() {
        guard let id = highlightedID, apps.contains(where: { $0.id == id }) else { return }
        model.selectTab("saved:" + id)
    }
}

private struct ShortcutRow: View {
    let entry: ShortcutEntry
    @ObservedObject var model: AppModel
    @State private var expanded = false
    @State private var hovering = false
    private var favorite: Bool { model.library.favorites.contains(entry.id) }
    private var learned: Bool { model.library.learned.contains(entry.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Button { expanded.toggle() } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Text(entry.title).fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                            Keycaps(sequence: entry.sequence, inlineSequence: entry.scope == "org.tmux.tmux")
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            Text(entry.title).lineLimit(2).multilineTextAlignment(.leading)
                            Keycaps(sequence: entry.sequence, alignment: .leading, inlineSequence: entry.scope == "org.tmux.tmux")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12, weight: learned ? .regular : .medium))
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(entry.detail ?? entry.title)

            }
            if expanded {
                HStack(spacing: 5) {
                    Text(entry.source.label).font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(accent.opacity(0.1), in: Capsule())
                    if entry.enabled == false { Text("현재 앱에서 비활성").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !entry.menuPath.isEmpty {
                    Text(entry.menuPath.joined(separator: " › ")).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                if entry.source == .builtin {
                    Text("기본 키 조합입니다. 설정을 바꿨다면 직접 수정하세요.")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    detailButton("즐겨찾기", symbol: favorite ? "star.fill" : "star", selected: favorite) {
                        model.toggleFavorite(entry)
                    }
                    .help(favorite ? "즐겨찾기 해제" : "즐겨찾기에 추가")
                    .accessibilityLabel("\(entry.title) 즐겨찾기")
                    .accessibilityValue(favorite ? "등록됨" : "등록 안 됨")
                    detailButton("공부 완료", symbol: learned ? "checkmark.circle.fill" : "checkmark.circle", selected: learned) {
                        model.toggleLearned(entry)
                    }
                    .help(learned ? "공부 완료 해제" : "공부 완료로 표시")
                    .accessibilityLabel("\(entry.title) 공부 완료")
                    .accessibilityValue(learned ? "완료" : "미완료")
                    Spacer(minLength: 0)
                    Button { model.openEditor?(entry) } label: {
                        Image(systemName: "pencil").font(.system(size: 11, weight: .medium))
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("단축키 수정")
                    .accessibilityLabel("\(entry.title) 단축키 수정")
                }.padding(.top, 3)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 9)
        .background(Color.primary.opacity(hovering || expanded ? 0.055 : 0.025), in: RoundedRectangle(cornerRadius: 8))
        .opacity(entry.enabled == false ? 0.55 : learned ? 0.7 : 1)
        .onHover { hovering = $0 }
    }
    private func detailButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 10, weight: .medium)).fixedSize()
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(Color.primary.opacity(selected ? 0.13 : 0.06), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct Keycaps: View {
    let sequence: [KeyChord]
    var alignment: HorizontalAlignment = .trailing
    var inlineSequence = false
    private var layout: AnyLayout {
        inlineSequence ? AnyLayout(HStackLayout(spacing: 5)) : AnyLayout(VStackLayout(alignment: alignment, spacing: 4))
    }
    var body: some View {
        layout {
            ForEach(Array(sequence.enumerated()), id: \.offset) { index, chord in
                HStack(spacing: 3) {
                    if index > 0 { Text(inlineSequence ? "→" : "↳").font(.system(size: 10)).foregroundStyle(.secondary) }
                    ForEach(chord.modifiers, id: \.self) { modifier in
                        cap(modifier == .function ? "Fn" : modifier.symbol)
                    }
                    cap(KeyChord.displayKey(chord.key))
                }
            }
        }.fixedSize().accessibilityElement(children: .ignore).accessibilityLabel(KeySequence.editable(sequence))
    }
    private func cap(_ key: String) -> some View {
        // Keep the original 11pt label's keycap width, using its padding for a larger glyph.
        let originalLabelWidth = (key as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)]).width
        return Text(key).font(.system(size: 15, weight: .semibold, design: .monospaced))
            .lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 2)
            .frame(width: max(21, ceil(originalLabelWidth) + 10), height: 24)
            .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.16)))
    }
}
