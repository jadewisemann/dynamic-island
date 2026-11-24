import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Draft config edited by the settings window. Every change is saved to
/// config.json after a short pause and applied to the island right away.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var draft: IslandConfig {
        didSet {
            preview.apply(config: draft)
            syncPreviewLook()
            if !suppressSave { scheduleSave() }
        }
    }
    @Published var connectionStatus = ""
    @Published var accessibilityGranted = false
    @Published var calendarAccess: CalendarProvider.Access = CalendarProvider.currentAccess()
    @Published var notificationDatabaseStatus: NotificationDatabaseWatcher.Status = .off
    @Published var configError: String?
    /// Whether macOS is in dark mode right now.
    @Published var systemIsDark = true {
        didSet { if oldValue != systemIsDark { editingLight = !systemIsDark } }
    }
    /// With theme.mode = system: edit (and preview) the light colors.
    @Published var editingLight = false {
        didSet { syncPreviewLook() }
    }
    @Published var previewPhase: IslandPhase = .compact {
        didSet { preview.showSample(previewPhase) }
    }
    let configPath: String
    /// A second island drawn inside the settings window.
    let preview = IslandModel()

    var onSave: ((IslandConfig) -> IslandConfig)?
    var onPreview: (() -> Void)?
    var onOpenFile: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onPreviewNotification: (() -> Void)?
    var onSendTestNotification: (() -> Void)?
    var onRecordNotificationDiagnostics: (() -> Void)?
    var onOpenCalendarPrivacy: (() -> Void)?
    var onOpenFullDiskAccess: (() -> Void)?
    @Published var claudeHooksInstalled = false
    var onToggleClaudeHooks: (() -> Void)?
    var onTestAgentCard: (() -> Void)?

    private var saveWork: DispatchWorkItem?
    private var suppressSave = false

    init(config: IslandConfig, configPath: String) {
        self.draft = config
        self.configPath = configPath
        preview.isPreview = true
        preview.geometry = NotchGeometry(width: 180, height: 32, hasNotch: true)
        preview.loadSample()
        preview.apply(config: config)
        preview.showSample(.compact)
        syncPreviewLook()
    }

    /// Applies a config that changed elsewhere (e.g. the file was edited).
    func sync(_ config: IslandConfig) {
        guard config != draft else { return }
        suppressSave = true
        draft = config
        suppressSave = false
    }

    func resetToDefaults() {
        draft = IslandConfig()
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard let onSave else { return }
        let normalized = onSave(draft)
        sync(normalized)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: Theme editing

    var followsSystem: Bool { draft.theme.mode.lowercased() == "system" }

    /// True when the theme tab edits the light colors.
    var editsLight: Bool { followsSystem && editingLight }

    /// The color set the theme tab edits: the light colors when following
    /// the system and "light" is selected, otherwise the appearance colors.
    var editedColors: IslandConfig.ThemeColors {
        get { editsLight ? draft.theme.light : draft.appearance.colors }
        set {
            if editsLight { draft.theme.light = newValue } else { draft.appearance.colors = newValue }
        }
    }

    private func syncPreviewLook() {
        let light = editsLight
        if preview.lookOverride != light { preview.lookOverride = light }
    }

    func apply(_ preset: ThemePreset) {
        var next = draft
        if editsLight { next.theme.light = preset.colors } else { next.appearance.colors = preset.colors }
        if let design = preset.fontDesign {
            next.appearance.fontDesign = design
            next.appearance.fontFamily = ""
        }
        if let number = preset.numberFontDesign { next.appearance.numberFontDesign = number }
        draft = next
    }

    func apply(_ saved: IslandConfig.SavedTheme) {
        editedColors = saved.colors
    }

    func saveCurrentTheme(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var saved = draft.theme.saved.filter { $0.name != trimmed }
        saved.append(IslandConfig.SavedTheme(name: trimmed, colors: editedColors))
        draft.theme.saved = saved
    }

    func deleteSavedTheme(_ theme: IslandConfig.SavedTheme) {
        draft.theme.saved.removeAll { $0.name == theme.name }
    }

    /// Writes the edited colors and fonts as a shareable .json file.
    func exportTheme() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "omni-island-theme.json"
        panel.message = "테마를 저장할 위치를 고르세요"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var dict = editedColors.dictionary
        dict["name"] = url.deletingPathExtension().lastPathComponent
        dict["fontFamily"] = draft.appearance.fontFamily
        dict["fontDesign"] = draft.appearance.fontDesign
        dict["numberFontDesign"] = draft.appearance.numberFontDesign
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: url, options: .atomic)
        } catch {
            configError = "테마를 내보내지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// Reads a theme .json file into the edited colors and saves it to
    /// "내 테마" under its name.
    func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "가져올 테마 파일(.json)을 고르세요"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let dict = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any] else {
                configError = "테마 파일의 형식이 올바르지 않습니다."
                return
            }
            var next = draft
            let colors = IslandConfig.ThemeColors(dict: dict, base: IslandConfig.ThemeColors())
            if editsLight { next.theme.light = colors } else { next.appearance.colors = colors }
            if let v = dict["fontFamily"] as? String { next.appearance.fontFamily = v }
            if let v = dict["fontDesign"] as? String { next.appearance.fontDesign = v }
            if let v = dict["numberFontDesign"] as? String { next.appearance.numberFontDesign = v }
            let name = (dict["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? url.deletingPathExtension().lastPathComponent
            next.theme.saved.removeAll { $0.name == name }
            next.theme.saved.append(IslandConfig.SavedTheme(name: name, colors: colors))
            draft = next
        } catch {
            configError = "테마를 가져오지 못했습니다: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "OmniIsland 설정"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Make sure a pending edit is not lost.
        model.saveNow()
    }
}

// MARK: - Views

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            PreviewPane(model: model, island: model.preview)
                .padding([.top, .horizontal], 12)

            TabView {
                GeneralSettings(model: model)
                    .tabItem { Label("일반", systemImage: "gearshape") }
                ThemeSettings(model: model)
                    .tabItem { Label("테마", systemImage: "paintpalette") }
                LayoutSettings(model: model)
                    .tabItem { Label("레이아웃", systemImage: "rectangle.3.group") }
                WidgetSettings(model: model)
                    .tabItem { Label("표시 요소", systemImage: "square.grid.2x2") }
                NotificationSettings(model: model)
                    .tabItem { Label("알림·일정", systemImage: "bell.badge") }
                LauncherSettings(model: model)
                    .tabItem { Label("런처", systemImage: "magnifyingglass") }
                AgentSettings(model: model)
                    .tabItem { Label("에이전트", systemImage: "sparkle") }
                AnimationSettings(model: model)
                    .tabItem { Label("애니메이션", systemImage: "wand.and.stars") }
                ConnectionSettings(model: model)
                    .tabItem { Label("연결", systemImage: "point.3.connected.trianglepath.dotted") }
            }
            .padding([.top, .horizontal], 12)

            Divider()
            HStack(spacing: 10) {
                Button {
                    model.saveNow()
                    model.onPreview?()
                } label: {
                    Label("실제 화면에서 미리보기", systemImage: "play.fill")
                }
                .keyboardShortcut("p", modifiers: .command)
                Spacer()
                Button("설정 파일 열기") { model.onOpenFile?() }
                Button("기본값으로 되돌리기") { model.resetToDefaults() }
            }
            .padding(12)
        }
        .frame(width: 640, height: 850)
    }
}

/// Live island drawn with the draft settings, above the tabs.
private struct PreviewPane: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var island: IslandModel

    var body: some View {
        let light = model.editsLight || (!model.followsSystem && !IslandPalette(model.draft.appearance.colors).isDark)
        ZStack(alignment: .top) {
            LinearGradient(
                colors: light ? [Color(hex: "#DCE4EE"), Color(hex: "#F3ECE2")] : [Color(hex: "#4F6596"), Color(hex: "#9B7C95")],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle()
                .fill(Color.black.opacity(light ? 0.06 : 0.22))
                .frame(height: island.geometry.height)
            IslandView(model: island)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if model.followsSystem {
                Text(model.editingLight ? "밝은 모양" : "어두운 모양")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Picker("", selection: $model.previewPhase) {
                Text("숨김").tag(IslandPhase.hidden)
                Text("워크스페이스").tag(IslandPhase.compact)
                Text("이동 알림").tag(IslandPhase.expanded)
                Text("알림").tag(IslandPhase.notification)
                Text("대시보드").tag(IslandPhase.dashboard)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 400)
            .padding(8)
        }
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: SettingsModel

    private static let modifiers: [(String, String)] = [
        ("option", "Option (⌥)"),
        ("leftOption", "왼쪽 Option"),
        ("rightOption", "오른쪽 Option"),
        ("command", "Command (⌘)"),
        ("rightCommand", "오른쪽 Command"),
        ("control", "Control (⌃)"),
        ("shift", "Shift (⇧)"),
        ("control+option", "Control + Option"),
        ("option+command", "Option + Command"),
    ]

    var body: some View {
        Form {
            Section("나타나는 조건") {
                Picker("트리거 키", selection: $model.draft.trigger.modifier) {
                    ForEach(options, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                Toggle("이 키만 눌렀을 때만 표시", isOn: $model.draft.trigger.exactMatch)
                if model.draft.trigger.exactMatch {
                    Toggle("Shift를 함께 눌러도 표시 (Option+Shift 단축키 중에도)", isOn: $model.draft.trigger.allowShift)
                }
                SliderRow(title: "누르고 있어야 하는 시간", value: $model.draft.trigger.holdDelayMs,
                          range: 0...600, step: 10, unit: "ms")
                SliderRow(title: "키를 뗀 뒤 사라지기까지", value: $model.draft.trigger.hideDelayMs,
                          range: 0...1000, step: 10, unit: "ms")
                Toggle("마우스를 아일랜드 위쪽 화면 끝에 대면 열기", isOn: $model.draft.behavior.revealOnHover)
                if model.draft.behavior.revealOnHover {
                    SliderRow(title: "화면 끝에 머물러야 하는 시간", value: $model.draft.behavior.hoverDelayMs,
                              range: 0...800, step: 10, unit: "ms")
                }
                Picker("자동으로 숨긴 메뉴 막대 막기", selection: $model.draft.behavior.blockMenuBar) {
                    Text("노치 없는 화면의 아일랜드 주변").tag("virtualNotch")
                    Text("모든 화면의 아일랜드 주변").tag("island")
                    Text("아일랜드 화면의 위쪽 끝 전체").tag("screen")
                    Text("막지 않음").tag("off")
                }
                Toggle("열린 아일랜드를 Option을 누른 채 끌어서 옮기기", isOn: $model.draft.behavior.dragToMove)
            }

            Section("이동 알림") {
                Toggle("워크스페이스 전환 보여 주기", isOn: $model.draft.behavior.showWorkspaceSwitch)
                Toggle("창 이동 보여 주기", isOn: $model.draft.behavior.showWindowMove)
                Toggle("옮겨진 창을 워크스페이스 줄에서 흘러가듯 보여 주기", isOn: $model.draft.behavior.windowMoveTrail)
                Toggle("키를 누르지 않았을 때도 보여 주기", isOn: $model.draft.behavior.showEventsWithoutModifier)
                SliderRow(title: "펼쳐진 상태 유지 시간", value: $model.draft.behavior.eventDurationMs,
                          range: 500...5000, step: 100, unit: "ms")
                SliderRow(title: "겹친 이벤트 합치기", value: $model.draft.behavior.coalesceMs,
                          range: 0...500, step: 10, unit: "ms")
            }

            Section("표시") {
                Picker("표시할 화면", selection: $model.draft.behavior.screen) {
                    Text("노치가 있는 화면").tag("notch")
                    Text("메뉴 막대가 있는 화면").tag("main")
                    Text("OmniWM이 조작 중인 화면").tag("active")
                }
                Picker("숨었을 때", selection: $model.draft.behavior.hiddenStyle) {
                    Text("자동").tag("auto")
                    Text("노치 모양 유지").tag("notch")
                    Text("완전히 사라짐").tag("fade")
                }
                Toggle("메뉴 막대 아이콘 표시", isOn: $model.draft.behavior.showMenuBarIcon)
                if !model.draft.behavior.showMenuBarIcon {
                    Text("아이콘을 숨기면 설정 창은 Finder에서 앱을 다시 열어야 나타납니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var options: [(String, String)] {
        let current = model.draft.trigger.modifier
        if Self.modifiers.contains(where: { $0.0 == current }) { return Self.modifiers }
        return Self.modifiers + [(current, "사용자 지정: \(current)")]
    }
}

// MARK: - Theme tab

private struct ThemeSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var newThemeName = ""

    private var fontFamilies: [String] { NSFontManager.shared.availableFontFamilies.sorted() }

    var body: some View {
        Form {
            Section("모양 모드") {
                Picker("색 구성", selection: $model.draft.theme.mode) {
                    Text("항상 같은 테마").tag("fixed")
                    Text("시스템 설정 따라가기").tag("system")
                }
                if model.followsSystem {
                    Picker("편집할 모양", selection: $model.editingLight) {
                        Text("어두울 때").tag(false)
                        Text("밝을 때").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text("macOS가 다크 모드면 어두울 때의 테마를, 라이트 모드면 밝을 때의 테마를 씁니다. 아래 프리셋과 색은 지금 고른 쪽에 적용됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("기본 테마") {
                PresetGrid(model: model, presets: ThemePreset.builtIn)
            }

            Section {
                PresetGrid(model: model, presets: ThemePreset.community)
            } header: {
                Text("커뮤니티 테마")
            } footer: {
                Text("r/unixporn 등에서 많이 쓰는 색 구성을 각 테마의 공식 팔레트 값으로 옮겼습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("내 테마") {
                if !model.draft.theme.saved.isEmpty {
                    SavedThemeGrid(model: model)
                }
                HStack {
                    TextField("이름", text: $newThemeName, prompt: Text("지금 색 구성을 저장할 이름"))
                    Button("저장") {
                        model.saveCurrentTheme(named: newThemeName)
                        newThemeName = ""
                    }
                    .disabled(newThemeName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Button("파일로 내보내기…") { model.exportTheme() }
                    Button("파일에서 가져오기…") { model.importTheme() }
                }
            }

            Section("배경") {
                Picker("재질", selection: $model.editedColors.backgroundStyle) {
                    Text("단색").tag("solid")
                    Text("반투명").tag("material")
                    Text("그라데이션").tag("gradient")
                }
                .pickerStyle(.segmented)
                ColorRow(title: style == "gradient" ? "시작 색" : "배경색", hex: $model.editedColors.backgroundColor)
                if style == "gradient" {
                    ColorRow(title: "끝 색", hex: $model.editedColors.gradientColor)
                    SliderRow(title: "방향", value: $model.editedColors.gradientAngle,
                              range: 0...360, step: 5, unit: "°")
                }
                if style == "material" {
                    Picker("두께", selection: $model.editedColors.material) {
                        Text("얇게").tag("thin")
                        Text("보통").tag("regular")
                        Text("두껍게").tag("thick")
                    }
                    .pickerStyle(.segmented)
                }
                SliderRow(title: style == "material" ? "색 덧칠 강도" : "불투명도",
                          value: $model.editedColors.backgroundOpacity,
                          range: style == "material" ? 0...1 : 0.2...1, step: 0.05, decimals: 2)
                SliderRow(title: "테두리 밝기", value: $model.editedColors.borderOpacity,
                          range: 0...0.4, step: 0.02, decimals: 2)
                Toggle("그림자", isOn: $model.editedColors.shadow)
            }

            Section("색") {
                ColorRow(title: "강조색", hex: $model.editedColors.accentColor)
                ColorRow(title: "글자", hex: $model.editedColors.textColor)
                ColorRow(title: "보조 글자", hex: $model.editedColors.secondaryTextColor, supportsOpacity: true)
                ColorRow(title: "활성 워크스페이스 글자", hex: $model.editedColors.activeTextColor)
                ColorRow(title: "옅은 채움 (비활성 칸, 테두리)", hex: $model.editedColors.fillColor)
                ColorRow(title: "알림 배지", hex: $model.editedColors.badgeColor)
                ColorRow(title: "알림 배지 글자", hex: $model.editedColors.badgeTextColor)
                LabeledContent("남은 시간 막대") {
                    HStack {
                        if !model.editedColors.progressColor.isEmpty {
                            Button("강조색 사용") { model.editedColors.progressColor = "" }
                                .buttonStyle(.link)
                        }
                        ColorPicker("", selection: progressBinding).labelsHidden()
                    }
                }
                Picker("활성 워크스페이스 표시", selection: $model.editedColors.activeStyle) {
                    Text("채움").tag("fill")
                    Text("테두리").tag("outline")
                    Text("밑줄").tag("underline")
                    Text("점").tag("dot")
                }
                Toggle("활성 워크스페이스 빛 번짐", isOn: $model.editedColors.activeGlow)
            }

            Section("글꼴") {
                Picker("글꼴", selection: fontChoice) {
                    Text("시스템 기본").tag("design:default")
                    Text("둥근 글꼴").tag("design:rounded")
                    Text("고정폭").tag("design:monospaced")
                    Text("세리프").tag("design:serif")
                    Divider()
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).tag("family:" + family)
                    }
                }
                Picker("굵기", selection: $model.draft.appearance.fontWeight) {
                    Text("가늘게").tag("light")
                    Text("보통").tag("regular")
                    Text("굵게").tag("bold")
                    Text("아주 굵게").tag("heavy")
                }
                .pickerStyle(.segmented)
                Picker("워크스페이스 번호 글꼴", selection: $model.draft.appearance.numberFontDesign) {
                    Text("본문과 같게").tag("same")
                    Text("시스템 기본").tag("default")
                    Text("둥근 글꼴").tag("rounded")
                    Text("고정폭").tag("monospaced")
                    Text("세리프").tag("serif")
                }
                SliderRow(title: "글자 크기", value: $model.draft.appearance.fontSize,
                          range: 10...18, step: 0.5, unit: "pt", decimals: 1)
            }
        }
        .formStyle(.grouped)
    }

    private var style: String { model.editedColors.backgroundStyle.lowercased() }

    private var progressBinding: Binding<Color> {
        Binding(
            get: {
                let c = model.editedColors
                return Color(hex: c.progressColor.isEmpty ? c.accentColor : c.progressColor)
            },
            set: { model.editedColors.progressColor = $0.hexString(includeAlpha: false) }
        )
    }

    /// One picker for both system designs and installed families.
    private var fontChoice: Binding<String> {
        Binding(
            get: {
                let a = model.draft.appearance
                return a.fontFamily.isEmpty ? "design:" + a.fontDesign.lowercased() : "family:" + a.fontFamily
            },
            set: { value in
                if value.hasPrefix("family:") {
                    model.draft.appearance.fontFamily = String(value.dropFirst("family:".count))
                } else {
                    model.draft.appearance.fontFamily = ""
                    model.draft.appearance.fontDesign = String(value.dropFirst("design:".count))
                }
            }
        )
    }
}

private struct PresetGrid: View {
    @ObservedObject var model: SettingsModel
    let presets: [ThemePreset]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(presets) { preset in
                ThemeCard(name: preset.name, colors: preset.colors,
                          selected: model.editedColors == preset.colors) {
                    model.apply(preset)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SavedThemeGrid: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(model.draft.theme.saved) { theme in
                ThemeCard(name: theme.name, colors: theme.colors,
                          selected: model.editedColors == theme.colors) {
                    model.apply(theme)
                }
                .contextMenu {
                    Button("삭제", role: .destructive) { model.deleteSavedTheme(theme) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A small island-shaped swatch with the theme's name.
private struct ThemeCard: View {
    let name: String
    let colors: IslandConfig.ThemeColors
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ThemeSwatch(colors: colors)
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(selected ? 0.08 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeSwatch: View {
    let colors: IslandConfig.ThemeColors

    var body: some View {
        let p = IslandPalette(colors)
        ZStack {
            switch colors.backgroundStyle.lowercased() {
            case "gradient":
                IslandBackground.gradient(p)
            case "material":
                ZStack {
                    LinearGradient(colors: [Color(hex: "#6F86B8"), Color(hex: "#C7A7B9")],
                                   startPoint: .leading, endPoint: .trailing)
                    p.background.opacity(max(colors.backgroundOpacity, 0.45))
                }
            default:
                p.background
            }
            HStack(spacing: 4) {
                Capsule().fill(p.fill.opacity(0.16)).frame(width: 14, height: 10)
                Capsule().fill(p.accent).frame(width: 20, height: 10)
                Capsule().fill(p.fill.opacity(0.16)).frame(width: 14, height: 10)
            }
        }
        .frame(height: 30)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous))
        .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
            .stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Layout tab

private struct LayoutSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("형태와 위치") {
                Picker("형태", selection: $model.draft.layout.shape) {
                    Text("노치에 붙음").tag("attached")
                    Text("떠 있는 캡슐").tag("floating")
                }
                .pickerStyle(.segmented)
                if floating {
                    SliderRow(title: "메뉴 막대와의 간격", value: $model.draft.layout.topGap,
                              range: 0...40, step: 1, unit: "pt")
                }
                Picker("가로 위치", selection: $model.draft.layout.horizontalPosition) {
                    Text("가운데").tag("center")
                    Text("왼쪽").tag("left")
                    Text("오른쪽").tag("right")
                }
                .pickerStyle(.segmented)
                SliderRow(title: "가로 위치 미세 조정", value: $model.draft.layout.horizontalOffset,
                          range: -400...400, step: 5, unit: "pt")
                Text("노치가 있는 화면에서는 아일랜드가 항상 노치 가운데에 붙으므로 가로 위치를 쓰지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("크기") {
                Picker("너비", selection: $model.draft.layout.widthMode) {
                    Text("내용에 맞춤").tag("auto")
                    Text("고정 너비").tag("fixed")
                }
                .pickerStyle(.segmented)
                if model.draft.layout.widthMode.lowercased() == "fixed" {
                    SliderRow(title: "고정 너비", value: $model.draft.layout.fixedWidth,
                              range: 200...900, step: 10, unit: "pt")
                }
                SliderRow(title: "펼쳤을 때 최소 너비", value: $model.draft.appearance.expandedWidth,
                          range: 260...800, step: 10, unit: "pt")
                SliderRow(title: "워크스페이스 줄 높이", value: $model.draft.appearance.compactRowHeight,
                          range: 24...64, step: 1, unit: "pt")
                SliderRow(title: "알림 줄 높이", value: $model.draft.appearance.expandedHeaderHeight,
                          range: 36...96, step: 1, unit: "pt")
                SliderRow(title: "안쪽 여백", value: $model.draft.layout.contentPadding,
                          range: 4...40, step: 1, unit: "pt")
            }

            Section("모서리") {
                SliderRow(title: floating ? "모서리 반경" : "아래쪽 모서리 반경",
                          value: $model.draft.appearance.bottomCornerRadius,
                          range: 0...40, step: 1, unit: "pt")
                if !floating {
                    SliderRow(title: "위쪽 어깨 반경", value: $model.draft.appearance.topCornerRadius,
                              range: 0...16, step: 1, unit: "pt")
                }
            }

            Section("워크스페이스 줄") {
                Picker("정렬", selection: $model.draft.layout.rowAlignment) {
                    Text("가운데").tag("center")
                    Text("왼쪽").tag("leading")
                    Text("양쪽 맞춤").tag("spread")
                }
                .pickerStyle(.segmented)
                SliderRow(title: "워크스페이스 알약 크기", value: $model.draft.appearance.pillSize,
                          range: 18...36, step: 1, unit: "pt")
                SliderRow(title: "워크스페이스 간격", value: $model.draft.appearance.pillSpacing,
                          range: 2...16, step: 1, unit: "pt")
            }

            Section("이동 알림") {
                Picker("알림 줄 위치", selection: $model.draft.layout.eventPlacement) {
                    Text("워크스페이스 줄 아래").tag("below")
                    Text("워크스페이스 줄 위").tag("above")
                    Text("워크스페이스 줄 대신").tag("replace")
                }
            }

            Section("노치가 없는 화면") {
                SliderRow(title: "가상 노치 너비", value: $model.draft.appearance.fallbackNotchWidth,
                          range: 100...320, step: 5, unit: "pt")
                SliderRow(title: "가상 노치 높이", value: $model.draft.appearance.fallbackNotchHeight,
                          range: 20...44, step: 1, unit: "pt")
            }
        }
        .formStyle(.grouped)
    }

    private var floating: Bool { model.draft.layout.shape.lowercased() == "floating" }
}

// MARK: - Widgets tab

private struct WidgetSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                wingPicker("왼쪽", selection: $model.draft.widgets.leftWing)
                wingPicker("가운데", selection: $model.draft.widgets.centerWing)
                wingPicker("오른쪽", selection: $model.draft.widgets.rightWing)
                if usesClock {
                    Picker("시계 형식", selection: $model.draft.widgets.clockFormat) {
                        Text("24시간").tag("24h")
                        Text("12시간").tag("12h")
                        Text("24시간, 초 표시").tag("24hSeconds")
                    }
                }
            } header: {
                Text("노치 줄")
            } footer: {
                Text("가운데 위젯은 노치가 없는 화면에서만 보입니다. 떠 있는 캡슐 형태에서는 왼쪽과 오른쪽 위젯이 워크스페이스 줄의 양 끝에 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("한쪽 칸 너비", selection: $model.draft.widgets.panelUnits) {
                    Text("1칸 (정사각형)").tag(1.0)
                    Text("2칸").tag(2.0)
                    Text("3칸").tag(3.0)
                }
                .pickerStyle(.segmented)
                PanelSlotEditor(model: model)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                Toggle("이벤트 중에도 표시", isOn: $model.draft.widgets.panelsDuringEvents)
            } header: {
                Text("좌우 위젯 칸")
            } footer: {
                Text("트리거 키를 눌러 워크스페이스 줄이 나타날 때 아일랜드 양옆에 붙습니다. ‘이벤트 중에도 표시’를 켜면 이동 알림이나 macOS 알림이 펼쳐질 때도 위젯 칸이 그대로 남습니다. 칸보다 위젯이 적으면 남는 너비를 나눠 쓰고, 2칸 이상이면 위젯이 넓은 모양으로 바뀝니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("워크스페이스 줄") {
                Picker("표시 방식", selection: $model.draft.appearance.workspaceStyle) {
                    Text("번호와 앱 아이콘").tag("apps")
                    Text("번호만").tag("pills")
                }
                .pickerStyle(.segmented)
                Picker("워크스페이스 이름", selection: $model.draft.widgets.workspaceLabel) {
                    Text("OmniWM 표시 이름").tag("name")
                    Text("번호만").tag("number")
                    Text("번호와 이름").tag("both")
                }
                Toggle("빈 워크스페이스도 표시", isOn: $model.draft.behavior.showEmptyWorkspaces)
                if model.draft.appearance.workspaceStyle != "pills" {
                    SliderRow(title: "앱 아이콘 크기", value: $model.draft.appearance.appIconSize,
                              range: 14...32, step: 1, unit: "pt")
                    SliderRow(title: "워크스페이스당 최대 아이콘", value: $model.draft.appearance.maxAppsPerWorkspace,
                              range: 1...12, step: 1, unit: "개")
                    Picker("창이 여러 개인 앱", selection: $model.draft.appearance.multiWindowStyle) {
                        Text("하나로 합치기").tag("merge")
                        Text("점 표시").tag("dots")
                        Text("창마다 아이콘").tag("separate")
                    }
                    Toggle("포커스된 창 강조", isOn: $model.draft.appearance.highlightFocusedWindow)
                    Toggle("알림 배지 표시", isOn: $model.draft.appearance.showBadges)
                    if model.draft.appearance.showBadges {
                        SliderRow(title: "배지 확인 간격", value: $model.draft.behavior.badgeIntervalMs,
                                  range: 1000...10000, step: 500, unit: "ms")
                        Text("배지는 Dock에 표시된 빨간 알림 숫자를 읽어 옵니다. 손쉬운 사용 권한이 필요합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("이동 알림 카드") {
                Toggle("아이콘", isOn: $model.draft.widgets.eventIcon)
                if model.draft.widgets.eventIcon {
                    Toggle("창을 옮길 때 앱 아이콘 사용", isOn: $model.draft.appearance.showAppIcons)
                }
                Toggle("부제목 (창 제목, 포커스된 앱)", isOn: $model.draft.widgets.eventSubtitle)
                Toggle("출발 → 도착 워크스페이스", isOn: $model.draft.widgets.eventFromTo)
                Toggle("남은 시간 막대", isOn: $model.draft.appearance.showEventProgress)
            }
        }
        .formStyle(.grouped)
    }

    private var usesClock: Bool {
        let w = model.draft.widgets
        return [w.leftWing, w.centerWing, w.rightWing].contains { $0.lowercased() == "clock" }
            || (w.leftPanel + w.rightPanel).contains("clock")
    }

    private func wingPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("포커스된 앱").tag("app")
            Text("활성 워크스페이스").tag("workspace")
            Text("시계").tag("clock")
            Text("날짜").tag("date")
            Text("창 개수").tag("windows")
            Text("다음 일정").tag("nextEvent")
            Text("놓친 알림 수").tag("notifications")
            Text("코딩 에이전트").tag("agents")
            Text("AI 사용량").tag("usage")
            Text("없음").tag("none")
        }
    }
}

// MARK: - Widget slot editor

/// The widgets that can go into a side panel slot.
enum PanelWidgetKind: String, CaseIterable, Identifiable {
    case clock, calendar, nextEvent, events, notifications, agents, usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "시계"
        case .calendar: return "달력"
        case .nextEvent: return "다음 일정"
        case .events: return "오늘 일정"
        case .notifications: return "최근 알림"
        case .agents: return "코딩 에이전트"
        case .usage: return "AI 사용량"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock"
        case .calendar: return "calendar"
        case .nextEvent: return "calendar.badge.clock"
        case .events: return "list.bullet.rectangle"
        case .notifications: return "bell.badge"
        case .agents: return "sparkle"
        case .usage: return "gauge.with.dots.needle.33percent"
        }
    }

    static func named(_ name: String) -> PanelWidgetKind? {
        allCases.first { $0.rawValue.lowercased() == name.lowercased() }
    }
}

/// A sketch of the island: slots on the left, the workspace row, slots on
/// the right. Click a slot to choose its widget.
private struct PanelSlotEditor: View {
    @ObservedObject var model: SettingsModel

    private var slots: Int { min(max(Int(model.draft.widgets.panelUnits.rounded()), 1), 3) }

    var body: some View {
        let w = model.draft.widgets
        let count = max(slots, w.leftPanel.count, w.rightPanel.count)
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                side(\.leftPanel, count: count)
                Text("워크스페이스 줄")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, height: 58)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                side(\.rightPanel, count: count)
            }
            Text("칸을 눌러 위젯을 고르거나 비웁니다. 한쪽을 모두 비우면 그쪽에는 칸이 생기지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func side(_ key: WritableKeyPath<IslandConfig.Widgets, [String]>, count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                slot(key, index)
            }
        }
    }

    private func slot(_ key: WritableKeyPath<IslandConfig.Widgets, [String]>, _ index: Int) -> some View {
        let items = model.draft.widgets[keyPath: key]
        let current = index < items.count ? PanelWidgetKind.named(items[index]) : nil
        return Menu {
            ForEach(PanelWidgetKind.allCases) { kind in
                Button {
                    set(key, index, kind.rawValue)
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
            if current != nil {
                Divider()
                Button("비우기", role: .destructive) { set(key, index, "") }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: current?.symbol ?? "plus")
                    .font(.system(size: 16, weight: .medium))
                Text(current?.title ?? "비어 있음")
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundStyle(current == nil ? Color.secondary : Color.primary)
            .frame(width: 58, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(current == nil ? Color.clear : Color.accentColor.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(current == nil ? Color.secondary.opacity(0.4) : Color.accentColor,
                                  style: StrokeStyle(lineWidth: 1, dash: current == nil ? [4, 3] : []))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func set(_ key: WritableKeyPath<IslandConfig.Widgets, [String]>, _ index: Int, _ value: String) {
        var items = model.draft.widgets[keyPath: key]
        while items.count <= index { items.append("") }
        items[index] = value
        model.draft.widgets[keyPath: key] = items.filter { !$0.isEmpty }
    }
}

// MARK: - Notifications tab

private struct NotificationSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("macOS 알림을 아일랜드에 보여 주기", isOn: $model.draft.notifications.enabled)
                if model.draft.notifications.enabled && !model.accessibilityGranted {
                    HStack {
                        Text("알림을 읽으려면 손쉬운 사용 권한이 필요합니다.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("권한 허용…") { model.onOpenAccessibility?() }
                    }
                }
                SliderRow(title: "표시 시간", value: $model.draft.notifications.durationMs,
                          range: 1500...10000, step: 250, unit: "ms")
                Picker("보여 줄 내용", selection: $model.draft.notifications.contentMode) {
                    Text("제목과 본문").tag("full")
                    Text("제목만").tag("title")
                    Text("앱 이름만").tag("app")
                }
                SliderRow(title: "같은 앱 알림 합치기", value: $model.draft.notifications.mergeWindowMs,
                          range: 0...10000, step: 500, unit: "ms")
                Toggle("알림 데이터베이스도 읽기", isOn: $model.draft.notifications.readDatabase)
                if model.draft.notifications.enabled && model.draft.notifications.readDatabase {
                    HStack {
                        Text("상태: \(model.notificationDatabaseStatus.label)")
                            .font(.caption)
                            .foregroundStyle(model.notificationDatabaseStatus == .running ? Color.secondary : Color.orange)
                        Spacer()
                        if model.notificationDatabaseStatus == .needsFullDiskAccess {
                            Button("권한 허용…") { model.onOpenFullDiskAccess?() }
                        }
                    }
                }
                Toggle("macOS 기본 배너 닫기 (아일랜드에 띄운 뒤 바로 닫음)", isOn: $model.draft.notifications.dismissSystemBanner)
                Toggle("놓친 알림을 노치 옆에 표시", isOn: $model.draft.notifications.keepIndicator)
                if model.draft.notifications.keepIndicator {
                    SliderRow(title: "표시 유지 시간", value: $model.draft.notifications.indicatorTimeoutMin,
                              range: 1...240, step: 1, unit: "분")
                }
            } header: {
                Text("알림 카드")
            } footer: {
                Text("macOS 알림 배너에 보이는 내용을 손쉬운 사용 API로 읽어 옵니다. 데이터베이스 읽기를 켜고 전체 디스크 접근 권한을 주면 배너가 뜨지 않는 알림(집중 모드, 알림 스타일 \"없음\")도 1~2초 늦게 보여 줍니다. 두 경로로 들어온 같은 알림은 한 번만 보여 줍니다. 기본 배너를 닫는 옵션을 켜도 배너가 잠깐 보였다가 사라집니다. 오른쪽 배너가 아예 뜨지 않게 하려면 데이터베이스 읽기를 켜 둔 채 시스템 설정 → 알림에서 앱별 알림 스타일을 \"없음\"으로 바꾸세요. 알림은 알림 센터와 아일랜드에 그대로 들어옵니다. 지난 알림은 대시보드와 메뉴 막대의 \"최근 알림\"에서 다시 볼 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("앱 필터") {
                Picker("대상", selection: $model.draft.notifications.filterMode) {
                    Text("모든 앱").tag("all")
                    Text("목록의 앱만").tag("allow")
                    Text("목록의 앱 빼고").tag("block")
                }
                if model.draft.notifications.filterMode != "all" {
                    TextField("앱 목록", text: appsText, prompt: Text("Slack, 메시지, com.apple.mail"))
                    Text("앱 이름이나 번들 ID를 쉼표로 구분해서 적습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("캘린더 사용", isOn: $model.draft.calendar.enabled)
                if model.draft.calendar.enabled {
                    switch model.calendarAccess {
                    case .granted:
                        EmptyView()
                    case .notDetermined:
                        Text("곧 캘린더 접근 권한을 묻는 창이 나타납니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .denied:
                        HStack {
                            Text("캘린더 접근이 거부되어 있습니다.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("시스템 설정 열기…") { model.onOpenCalendarPrivacy?() }
                        }
                    }
                    TextField("사용할 캘린더", text: calendarsText, prompt: Text("비워 두면 전체"))
                    Toggle("일정 시작 전에 알리기", isOn: $model.draft.calendar.showAlerts)
                    if model.draft.calendar.showAlerts {
                        TextField("알림 시점 (분 전)", text: alertMinutesText, prompt: Text("5, 0"))
                    }
                    Toggle("종일 일정 포함", isOn: $model.draft.calendar.includeAllDay)
                }
            } header: {
                Text("캘린더")
            } footer: {
                Text("다음 일정은 표시 요소 탭에서 노치 양옆 위젯을 \"다음 일정\"으로 바꾸면 보입니다. 거절한 일정은 표시하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("대시보드 사용", isOn: $model.draft.dashboard.enabled)
                if model.draft.dashboard.enabled {
                    SliderRow(title: "추가로 누르고 있는 시간", value: $model.draft.dashboard.holdMs,
                              range: 200...3000, step: 100, unit: "ms")
                    Toggle("큰 시계", isOn: itemBinding("clock"))
                    Toggle("오늘 남은 일정", isOn: itemBinding("events"))
                    Toggle("AI 사용량", isOn: itemBinding("usage"))
                    Toggle("최근 알림", isOn: itemBinding("notifications"))
                }
            } header: {
                Text("대시보드")
            } footer: {
                Text("트리거 키를 눌러 워크스페이스 줄이 나타난 뒤 계속 누르고 있으면 한 단계 더 펼쳐집니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("알림 카드 미리보기") {
                        model.saveNow()
                        model.onPreviewNotification?()
                    }
                    Button("테스트 알림 보내기") { model.onSendTestNotification?() }
                    Button("배너 구조 기록 (1분)") { model.onRecordNotificationDiagnostics?() }
                }
            } header: {
                Text("확인")
            } footer: {
                Text("테스트 알림이 아일랜드에 보이지 않으면 \"배너 구조 기록\"을 누르고 1분 뒤 Finder에 나타나는 로그 파일을 보내 주세요. macOS 버전에 맞게 판독 코드를 고칠 때 씁니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var appsText: Binding<String> {
        Binding(
            get: { model.draft.notifications.apps.joined(separator: ", ") },
            set: { model.draft.notifications.apps = Self.split($0) }
        )
    }

    private var calendarsText: Binding<String> {
        Binding(
            get: { model.draft.calendar.calendars.joined(separator: ", ") },
            set: { model.draft.calendar.calendars = Self.split($0) }
        )
    }

    private var alertMinutesText: Binding<String> {
        Binding(
            get: { model.draft.calendar.alertMinutes.map { String(Int($0)) }.joined(separator: ", ") },
            set: { model.draft.calendar.alertMinutes = Self.split($0).compactMap(Double.init) }
        )
    }

    private func itemBinding(_ item: String) -> Binding<Bool> {
        Binding(
            get: { model.draft.dashboard.items.contains(item) },
            set: { on in
                let order = ["clock", "events", "usage", "notifications"]
                var items = model.draft.dashboard.items.filter { $0 != item }
                if on { items.append(item) }
                model.draft.dashboard.items = order.filter(items.contains)
            }
        )
    }
}

// MARK: - Animation tab

private struct LauncherSettings: View {
    @ObservedObject var model: SettingsModel

    private static let hotkeys: [(String, String)] = [
        ("option+h", "⌥H"),
        ("option+space", "⌥Space"),
        ("control+space", "⌃Space"),
        ("option+command+space", "⌥⌘Space"),
        ("option+k", "⌥K"),
        ("control+option+space", "⌃⌥Space"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("런처 사용", isOn: $model.draft.launcher.enabled)
                Picker("단축키", selection: $model.draft.launcher.hotkey) {
                    ForEach(hotkeyOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .disabled(!model.draft.launcher.enabled)
                Toggle("열 때 영어 입력으로 바꾸기", isOn: $model.draft.launcher.englishInput)
                    .disabled(!model.draft.launcher.enabled)
                Text("Option을 누르고 있으면 아일랜드가 나타나고, 이어서 H를 누르면 검색창이 열립니다. 바로 입력하면 결과가 아래로 붙습니다. 영어 입력으로 바꾸기를 켜 두면 한글 입력 중이었더라도 영어로 시작하고, 닫을 때 원래 입력 소스로 돌아갑니다. 열린 상태에서 입력 소스를 바꾸면 한글로도 검색할 수 있습니다. ↑↓로 고르고 Return으로 실행하며, Esc를 누르면 검색어를 지우고 한 번 더 누르면 닫힙니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("열기")
            }

            Section {
                ForEach(Self.plugins, id: \.id) { plugin in
                    LabeledContent {
                        TextField("", text: prefixBinding(plugin.id), prompt: Text("없음"))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    } label: {
                        Label(plugin.name, systemImage: plugin.symbol)
                    }
                }
                Text("검색창에 접두어를 입력하고 스페이스를 누르면 그 내장 앱만 보입니다. 예를 들어 c 다음에 스페이스를 누르면 클립보드 관리자가 열립니다. 한글 자판으로 친 ㅊ, ㅈ, ㄴ, ㄹ도 됩니다. 빈 검색창에서 ⌫ 또는 Esc를 누르면 처음 검색으로 돌아갑니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("내장 앱과 트리거 접두어")
            }
            .disabled(!model.draft.launcher.enabled)

            QuickLinkSettings(model: model)
                .disabled(!model.draft.launcher.enabled)

            Section("기본 검색에 포함할 것") {
                Toggle("앱", isOn: $model.draft.launcher.searchApps)
                Toggle("OmniWM에 열려 있는 창", isOn: $model.draft.launcher.searchWindows)
                Text("창은 Return을 누르면 그 창으로 이동하고, ⌘Return을 누르면 지금 워크스페이스로 불러옵니다. 앱은 ⌘Return을 누르면 Finder에서 보여 줍니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("계산기 (2^10*3 같은 수식)", isOn: $model.draft.launcher.calculator)
                Toggle("환율 (100 USD to KRW, 100달러)", isOn: $model.draft.launcher.currency)
                Toggle("시스템 설정 패널과 OmniIsland 설정", isOn: $model.draft.launcher.searchSettings)
                Toggle("홈 폴더의 파일 (Spotlight)", isOn: $model.draft.launcher.searchFiles)
                if model.draft.launcher.searchFiles {
                    SliderRow(title: "파일 결과 수", value: $model.draft.launcher.maxFiles, range: 1...8, step: 1)
                }
                Toggle("클립보드 기록", isOn: $model.draft.launcher.searchClipboard)
                Toggle("고른 결과를 학습해서 위로 올리기", isOn: $model.draft.launcher.learnFromPicks)
            }
            .disabled(!model.draft.launcher.enabled)

            Section("웹") {
                Toggle("Google에서 검색 줄", isOn: $model.draft.launcher.webSearch)
                Toggle("Google 추천 검색어", isOn: $model.draft.launcher.suggestions)
                    .disabled(!model.draft.launcher.webSearch)
                if model.draft.launcher.webSearch && model.draft.launcher.suggestions {
                    SliderRow(title: "추천 검색어 수", value: $model.draft.launcher.maxSuggestions, range: 1...6, step: 1)
                    Text("추천 검색어를 받으려고 입력한 글자를 Google에 보냅니다. 점, 슬래시, @처럼 주소로 보이는 입력은 보내지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Claude에게 묻기", isOn: $model.draft.launcher.askClaude)
                Toggle("Grok에게 묻기", isOn: $model.draft.launcher.askGrok)
                Toggle("X에서 검색", isOn: $model.draft.launcher.searchX)
            }
            .disabled(!model.draft.launcher.enabled)

            Section("표시") {
                SliderRow(title: "최대 결과 수", value: $model.draft.launcher.maxResults,
                          range: 3...14, step: 1)
                Toggle("검색어가 없을 때 최근에 연 앱 보여 주기", isOn: $model.draft.launcher.showRecent)
                if model.draft.launcher.showRecent {
                    SliderRow(title: "최근 앱 개수", value: $model.draft.launcher.recentCount,
                              range: 1...10, step: 1)
                }
                SliderRow(title: "펼친 너비", value: $model.draft.launcher.width,
                          range: 400...800, step: 10, unit: "pt")
            }
            .disabled(!model.draft.launcher.enabled)

            Section("클립보드 관리자") {
                Toggle("복사한 것을 기록하기", isOn: $model.draft.shelf.enabled)
                if model.draft.shelf.enabled {
                    SliderRow(title: "기억할 개수", value: $model.draft.shelf.maxItems, range: 5...200, step: 5)
                    Toggle("이미지도 기록하기", isOn: $model.draft.shelf.captureImages)
                    Toggle("Finder에서 복사한 파일도 기록하기", isOn: $model.draft.shelf.captureFiles)
                }
                Text("런처에서 c 다음에 스페이스를 누르면 복사 기록이 최신순으로 나오고, 입력하면 그 안에서 검색합니다. Return은 원래 앱에 붙여넣기, ⌘Return은 복사만 하기, ⌘⌫는 삭제입니다. Tab이나 ⇧↑↓, ⌘클릭으로 여러 개를 고르면 고른 순서대로 한꺼번에 붙여넣습니다(텍스트는 줄을 바꿔 이어 붙입니다). 행을 끌어서 다른 앱에 놓을 수도 있습니다. 비밀번호 관리자에서 복사한 것은 기록하지 않으며, 앱을 다시 시작해도 남아 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static let plugins: [(id: String, name: String, symbol: String)] = [
        ("clipboard", "클립보드 관리자", "doc.on.clipboard"),
        ("windows", "창 관리자", "macwindow.on.rectangle"),
        ("settings", "설정 관리자", "gearshape.fill"),
        ("files", "파일 검색", "doc.text.magnifyingglass"),
        ("apps", "앱", "square.grid.2x2"),
        ("quicklinks", "Quick Links", "link"),
    ]

    private func prefixBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { model.draft.launcher.prefixes[id] ?? "" },
            set: { model.draft.launcher.prefixes[id] = $0.replacingOccurrences(of: " ", with: "").lowercased() }
        )
    }

    private var hotkeyOptions: [(String, String)] {
        let current = model.draft.launcher.hotkey
        if Self.hotkeys.contains(where: { $0.0 == current }) { return Self.hotkeys }
        return Self.hotkeys + [(current, "사용자 지정: \(HotKeyMonitor.symbols(current))")]
    }
}

/// The Quick Links list: add, edit and remove saved links. Edits happen in
/// local fields and reach the config only on 저장, so a half-typed link is
/// never written to the file.
private struct QuickLinkSettings: View {
    @ObservedObject var model: SettingsModel
    /// The link being edited: its index, or -1 for a new one.
    @State private var editing: Int?
    @State private var form = QuickLink()

    private var links: [QuickLink] { model.draft.launcher.quickLinks }

    var body: some View {
        Section {
            Toggle("기본 검색에 포함하기", isOn: $model.draft.launcher.searchQuickLinks)
            ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                if editing == index {
                    editor
                } else {
                    row(index, link)
                }
            }
            if editing == -1 {
                editor
            } else {
                Button {
                    form = QuickLink()
                    editing = -1
                } label: {
                    Label("링크 추가", systemImage: "plus")
                }
                .disabled(editing != nil)
            }
            Text("런처에서 이름이나 키워드로 찾아 Return을 누르면 링크를 엽니다. 링크에 {query}를 넣으면, 키워드(없으면 이름) 다음에 스페이스를 누르고 입력한 내용이 그 자리에 들어갑니다. 예를 들어 키워드가 gh이고 링크가 https://github.com/{query}이면, gh jadewisemann/dynamic-island를 입력해서 그 저장소를 엽니다. 아무것도 입력하지 않고 Return을 누르면 {query} 앞부분(https://github.com/)을 엽니다. 키워드는 gh bb stg처럼 여러 단어로 적어 계층을 만들 수 있습니다. g만 입력해도 g로 시작하는 키워드가 위에 힌트로 나오고, gh 다음에 스페이스를 누르면 gh 아래의 링크가 모두 나옵니다. Tab을 누르면 키워드를 다음 단어까지 완성합니다. 링크에는 웹 주소뿐 아니라 obsidian://, mailto: 같은 URL이나 ~/Downloads 같은 파일·폴더 경로도 적을 수 있습니다. ⌘Return은 열지 않고 주소만 복사합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Quick Links")
        }
    }

    private func row(_ index: Int, _ link: QuickLink) -> some View {
        HStack(spacing: 10) {
            Image(systemName: link.needsInput ? "magnifyingglass" : link.isFile ? "folder" : "link")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.name)
                Text(link.app.isEmpty ? link.link : "\(link.link) · \(link.app)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !link.keyword.isEmpty {
                Text(link.keyword)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            Button("편집") {
                form = link
                editing = index
            }
            .disabled(editing != nil)
            Button(role: .destructive) {
                model.draft.launcher.quickLinks.remove(at: index)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(editing != nil)
            .help("삭제")
        }
    }

    private var trimmed: QuickLink {
        QuickLink(name: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  link: form.link.trimmingCharacters(in: .whitespacesAndNewlines),
                  keyword: QuickLink.words(form.keyword).text,
                  app: form.app.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var preview: String? {
        let link = trimmed
        guard !link.link.isEmpty, let url = link.url(argument: link.needsInput ? "example" : nil) else { return nil }
        return url.isFileURL ? url.path : url.absoluteString
    }

    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("이름", text: $form.name, prompt: Text("GitHub 저장소"))
            TextField("링크", text: $form.link, prompt: Text("https://github.com/{query}"))
            TextField("키워드", text: $form.keyword, prompt: Text("gh 또는 gh bb stg (선택)"))
            TextField("열 앱", text: $form.app, prompt: Text("비워 두면 기본 앱 (Safari, com.google.Chrome)"))
            if let preview {
                Text(trimmed.needsInput ? "example을 입력하면: \(preview)" : "열 주소: \(preview)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !trimmed.app.isEmpty && trimmed.appURL == nil {
                Text("이 이름의 앱을 찾지 못했습니다. 앱 이름, 번들 ID, 또는 .app 경로를 적어 주세요.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("취소") { editing = nil }
                    .keyboardShortcut(.cancelAction)
                Button("저장") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!trimmed.isValid)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let link = trimmed
        guard link.isValid, let index = editing else { return }
        if index >= 0 && index < links.count {
            model.draft.launcher.quickLinks[index] = link
        } else {
            model.draft.launcher.quickLinks.append(link)
        }
        editing = nil
    }
}

private struct AnimationSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("움직임") {
                Picker("스타일", selection: $model.draft.motion.style) {
                    Text("스프링 (직접 조절)").tag("spring")
                    Text("통통 튀게").tag("bouncy")
                    Text("부드럽게").tag("smooth")
                    Text("빠르고 경쾌하게").tag("snappy")
                    Text("가속·감속").tag("easeInOut")
                    Text("애니메이션 없음").tag("none")
                }
                timingRows
                if style != "none" {
                    SliderRow(title: "전체 속도", value: $model.draft.motion.speed,
                              range: 0.5...2, step: 0.05, unit: "×", decimals: 2)
                }
            }

            Section("효과") {
                Picker("내용 전환", selection: $model.draft.motion.contentTransition) {
                    Text("블러와 페이드").tag("blur")
                    Text("페이드만").tag("fade")
                    Text("아래에서 밀려 올라옴").tag("slide")
                    Text("없음").tag("none")
                }
                Toggle("이벤트가 들어올 때 살짝 튀어오르기", isOn: $model.draft.motion.popOnEvent)
                Toggle("끈적한 액체처럼 움직이기", isOn: $model.draft.motion.liquid)
                Text("좌우 위젯 칸이 아일랜드에서 방울처럼 떨어져 나오고, 활성 워크스페이스 표시가 늘어나며 옮겨 갑니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("값을 바꾸면 위쪽 미리보기에 바로 반영됩니다. 실제 화면에서 보려면 아래쪽 버튼(⌘P)을 누르세요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var style: String { model.draft.motion.style }

    @ViewBuilder private var timingRows: some View {
        if style == "spring" {
            SliderRow(title: "응답 시간", value: $model.draft.motion.response,
                      range: 0.15...1.2, step: 0.01, unit: "s", decimals: 2)
            SliderRow(title: "감쇠 (낮을수록 튐)", value: $model.draft.motion.dampingFraction,
                      range: 0.3...1.0, step: 0.01, unit: "", decimals: 2)
        }
        if style != "spring" && style != "none" {
            SliderRow(title: "재생 시간", value: $model.draft.motion.durationMs,
                      range: 100...1200, step: 10, unit: "ms")
        }
    }
}

private struct AgentSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("코딩 에이전트 상태 보여 주기", isOn: $model.draft.agents.enabled)
                LabeledContent("Claude Code 훅") {
                    HStack {
                        if model.claudeHooksInstalled {
                            Label("설치됨", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Button(model.claudeHooksInstalled ? "제거" : "설치") { model.onToggleClaudeHooks?() }
                    }
                }
                Text("설치하면 ~/.claude/settings.json에 OmniIsland 훅을 추가합니다. 기존 설정과 훅은 그대로 두고, 바꾸기 전 파일은 settings.json.omni-island-backup으로 남깁니다. 이미 실행 중인 Claude Code 세션은 다시 시작해야 훅이 적용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("연결")
            }

            Section("권한 요청") {
                Toggle("아일랜드에서 허용·거부하기", isOn: $model.draft.agents.approvals)
                SliderRow(title: "응답 기다리는 시간", value: $model.draft.agents.approvalTimeoutSec,
                          range: 15...300, step: 5, unit: "초")
                Text("시간 안에 누르지 않으면 카드가 닫히고 터미널에서 평소처럼 묻습니다. 카드를 누르면 그 세션이 열린 터미널 창으로 이동합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("승인 카드 미리보기") { model.onTestAgentCard?() }
            }
            .disabled(!model.draft.agents.enabled)

            Section("알림") {
                Toggle("작업을 마치면 알리기", isOn: $model.draft.agents.notifyDone)
                Toggle("입력을 기다리면 알리기", isOn: $model.draft.agents.notifyWaiting)
                SliderRow(title: "카드 표시 시간", value: $model.draft.agents.cardDurationMs,
                          range: 1000...15000, step: 500, unit: "ms")
                Text("노치 옆 날개나 위젯 칸에 \"코딩 에이전트\"를 넣으면 세션마다 상태 점이 보입니다. 파랑은 작업 중, 노랑은 입력 대기, 주황은 승인 필요, 초록은 완료입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!model.draft.agents.enabled)

            Section {
                Toggle("Claude Code 사용량 보여 주기", isOn: $model.draft.usage.enabled)
                Toggle("요금제 한도(5시간·주간 %) 가져오기", isOn: $model.draft.usage.planLimits)
                    .disabled(!model.draft.usage.enabled)
            } header: {
                Text("AI 사용량")
            } footer: {
                Text("노치 옆 날개, 좌우 위젯 칸, 대시보드에 \"AI 사용량\"을 넣으면 보입니다. 토큰 수는 ~/.claude/projects에 남는 Claude Code 기록에서 읽습니다. 한도는 키체인에 저장된 Claude Code 로그인으로 Claude Code의 /usage와 같은 곳에서 5분마다 가져옵니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Codex") {
                Text("~/.codex/config.toml에 다음 줄을 넣으면 Codex가 답을 마칠 때 알립니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CodexHookInfo.configLine)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("스크립트에서 카드 띄우기") {
                Text("omni-island notify --title \"빌드 완료\" --body \"3분 12초\" --icon hammer")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("Homebrew로 설치하면 omni-island 명령이 PATH에 들어갑니다. 텔레그램 봇이나 CI 결과 알림처럼 아무 스크립트에서나 호출할 수 있습니다. omni-island help로 옵션을 볼 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ConnectionSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("상태") {
                LabeledContent("OmniWM", value: model.connectionStatus)
                LabeledContent("손쉬운 사용 권한") {
                    if model.accessibilityGranted {
                        Label("허용됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("허용하기…") { model.onOpenAccessibility?() }
                    }
                }
                if !model.accessibilityGranted {
                    Text("권한이 없어도 동작하지만, 키 상태를 주기적으로 읽는 방식이라 반응이 조금 늦을 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = model.configError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("omniwmctl") {
                HStack {
                    TextField("경로", text: optionalText(\.omniwmctlPath),
                              prompt: Text(detectedPath ?? "자동으로 찾기"))
                    Button("찾아보기…") { browse() }
                }
                Text(detectedPath.map { "자동으로 찾은 경로: \($0)" } ?? "omniwmctl을 찾지 못했습니다. OmniWM 메뉴의 Install CLI to PATH를 실행하거나 경로를 직접 지정하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("IPC 소켓") {
                TextField("소켓 경로", text: optionalText(\.socketPath), prompt: Text("기본값 사용"))
                Text("OMNIWM_SOCKET을 바꿔서 쓰는 경우에만 지정합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("설정 파일") {
                Text(model.configPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private var detectedPath: String? {
        OmniWMClient.resolveExecutable(configured: nil)
    }

    private func optionalText(_ keyPath: WritableKeyPath<IslandConfig, String?>) -> Binding<String> {
        Binding(
            get: { model.draft[keyPath: keyPath] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                model.draft[keyPath: keyPath] = trimmed.isEmpty ? nil : (trimmed as NSString).expandingTildeInPath
            }
        )
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "omniwmctl 실행 파일을 선택하세요"
        if panel.runModal() == .OK, let url = panel.url {
            model.draft.omniwmctlPath = url.path
        }
    }
}

// MARK: - Rows

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = ""
    var decimals: Int = 0

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: clamped, in: range, step: step)
                    .frame(width: 190)
                Text(formatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }

    private var clamped: Binding<Double> {
        Binding(
            get: { min(max(value, range.lowerBound), range.upperBound) },
            set: { value = $0 }
        )
    }

    private var formatted: String {
        String(format: "%.\(decimals)f", value) + unit
    }
}

struct ColorRow: View {
    let title: String
    @Binding var hex: String
    var supportsOpacity = false

    var body: some View {
        ColorPicker(title, selection: colorBinding, supportsOpacity: supportsOpacity)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: hex) },
            set: { hex = $0.hexString(includeAlpha: supportsOpacity) }
        )
    }
}

extension Color {
    func hexString(includeAlpha: Bool) -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", byte(ns.redComponent), byte(ns.greenComponent), byte(ns.blueComponent))
        return includeAlpha ? rgb + String(format: "%02X", byte(ns.alphaComponent)) : rgb
    }
}
