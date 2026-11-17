import AppKit
import SwiftUI

/// Draft config edited by the settings window. Every change is saved to
/// config.json after a short pause and applied to the island right away.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var draft: IslandConfig {
        didSet { if !suppressSave { scheduleSave() } }
    }
    @Published var connectionStatus = ""
    @Published var accessibilityGranted = false
    @Published var configError: String?
    let configPath: String

    var onSave: ((IslandConfig) -> IslandConfig)?
    var onPreview: (() -> Void)?
    var onOpenFile: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?

    private var saveWork: DispatchWorkItem?
    private var suppressSave = false

    init(config: IslandConfig, configPath: String) {
        self.draft = config
        self.configPath = configPath
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
            TabView {
                GeneralSettings(model: model)
                    .tabItem { Label("일반", systemImage: "gearshape") }
                AppearanceSettings(model: model)
                    .tabItem { Label("모양", systemImage: "paintpalette") }
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
                    Label("미리보기", systemImage: "play.fill")
                }
                .keyboardShortcut("p", modifiers: .command)
                Spacer()
                Button("설정 파일 열기") { model.onOpenFile?() }
                Button("기본값으로 되돌리기") { model.resetToDefaults() }
            }
            .padding(12)
        }
        .frame(width: 560, height: 620)
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
                SliderRow(title: "누르고 있어야 하는 시간", value: $model.draft.trigger.holdDelayMs,
                          range: 0...600, step: 10, unit: "ms")
                SliderRow(title: "키를 뗀 뒤 사라지기까지", value: $model.draft.trigger.hideDelayMs,
                          range: 0...1000, step: 10, unit: "ms")
            }

            Section("이동 알림") {
                Toggle("워크스페이스 전환 보여 주기", isOn: $model.draft.behavior.showWorkspaceSwitch)
                Toggle("창 이동 보여 주기", isOn: $model.draft.behavior.showWindowMove)
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
                Toggle("빈 워크스페이스도 표시", isOn: $model.draft.behavior.showEmptyWorkspaces)
                Toggle("포커스된 앱 표시", isOn: $model.draft.appearance.showFocusedApp)
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

private struct AppearanceSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("색상") {
                ColorRow(title: "배경", hex: $model.draft.appearance.backgroundColor)
                SliderRow(title: "배경 불투명도", value: $model.draft.appearance.backgroundOpacity,
                          range: 0.2...1, step: 0.05, decimals: 2)
                ColorRow(title: "강조색", hex: $model.draft.appearance.accentColor)
                ColorRow(title: "글자", hex: $model.draft.appearance.textColor)
                ColorRow(title: "보조 글자", hex: $model.draft.appearance.secondaryTextColor, supportsOpacity: true)
                SliderRow(title: "테두리 밝기", value: $model.draft.appearance.borderOpacity,
                          range: 0...0.4, step: 0.02, decimals: 2)
                Toggle("그림자", isOn: $model.draft.appearance.shadow)
            }

            Section("모양") {
                SliderRow(title: "아래쪽 모서리 반경", value: $model.draft.appearance.bottomCornerRadius,
                          range: 0...32, step: 1, unit: "pt")
                SliderRow(title: "위쪽 어깨 반경", value: $model.draft.appearance.topCornerRadius,
                          range: 0...16, step: 1, unit: "pt")
                SliderRow(title: "펼쳤을 때 너비", value: $model.draft.appearance.expandedWidth,
                          range: 260...700, step: 10, unit: "pt")
                SliderRow(title: "워크스페이스 줄 높이", value: $model.draft.appearance.compactRowHeight,
                          range: 28...60, step: 1, unit: "pt")
                SliderRow(title: "알림 줄 높이", value: $model.draft.appearance.expandedHeaderHeight,
                          range: 40...90, step: 1, unit: "pt")
            }

            Section("내용") {
                SliderRow(title: "글자 크기", value: $model.draft.appearance.fontSize,
                          range: 10...18, step: 0.5, unit: "pt", decimals: 1)
                SliderRow(title: "워크스페이스 알약 크기", value: $model.draft.appearance.pillSize,
                          range: 18...36, step: 1, unit: "pt")
                SliderRow(title: "알약 간격", value: $model.draft.appearance.pillSpacing,
                          range: 2...16, step: 1, unit: "pt")
                Toggle("앱 아이콘 표시", isOn: $model.draft.appearance.showAppIcons)
                Toggle("남은 시간 막대 표시", isOn: $model.draft.appearance.showEventProgress)
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
}

private struct AnimationSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("움직임") {
                Picker("스타일", selection: $model.draft.animation.style) {
                    Text("스프링 (직접 조절)").tag("spring")
                    Text("통통 튀게").tag("bouncy")
                    Text("부드럽게").tag("smooth")
                    Text("빠르고 경쾌하게").tag("snappy")
                    Text("가속·감속").tag("easeInOut")
                    Text("애니메이션 없음").tag("none")
                }
                timingRows
            }

            Section("효과") {
                Toggle("나타날 때 블러 효과", isOn: $model.draft.animation.blurTransitions)
                Toggle("이벤트가 들어올 때 살짝 튀어오르기", isOn: $model.draft.animation.popOnEvent)
            }

            Section {
                Text("값을 바꾸면 바로 적용됩니다. 아래쪽의 미리보기 버튼(⌘P)으로 확인해 보세요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var style: String { model.draft.animation.style }

    @ViewBuilder private var timingRows: some View {
        if style == "spring" {
            SliderRow(title: "응답 시간", value: $model.draft.animation.response,
                      range: 0.15...1.2, step: 0.01, unit: "s", decimals: 2)
            SliderRow(title: "감쇠 (낮을수록 튐)", value: $model.draft.animation.dampingFraction,
                      range: 0.3...1.0, step: 0.01, unit: "", decimals: 2)
        }
        if style != "spring" && style != "none" {
            SliderRow(title: "재생 시간", value: $model.draft.animation.durationMs,
                      range: 100...1200, step: 10, unit: "ms")
        }
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
