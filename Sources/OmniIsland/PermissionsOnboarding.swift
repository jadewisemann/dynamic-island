import AppKit
import EventKit
import SwiftUI

/// A macOS permission the island can use.
enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility
    case fullDiskAccess
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "손쉬운 사용"
        case .fullDiskAccess: return "전체 디스크 접근"
        case .calendar: return "캘린더"
        }
    }

    var systemImage: String {
        switch self {
        case .accessibility: return "accessibility"
        case .fullDiskAccess: return "externaldrive.badge.checkmark"
        case .calendar: return "calendar"
        }
    }

    var purpose: String {
        switch self {
        case .accessibility:
            return "Option 키를 누르고 있는지 감지하고, 화면에 뜨는 알림 배너를 읽으려면 필요합니다. 이 권한이 없으면 아일랜드가 열리지 않습니다."
        case .fullDiskAccess:
            return "macOS가 알림을 저장하는 데이터베이스를 읽어서, 배너가 뜨지 않는 앱의 알림까지 받으려면 필요합니다. macOS는 이 권한을 직접 묻지 않기 때문에 시스템 설정에서 켜 주어야 합니다."
        case .calendar:
            return "캘린더 위젯에 오늘 일정을 보여 주고, 일정이 시작되기 전에 알림을 띄우려면 필요합니다."
        }
    }

    var steps: [String] {
        switch self {
        case .accessibility:
            return [
                "아래 버튼으로 시스템 설정의 손쉬운 사용 화면을 엽니다.",
                "목록에서 OmniIsland를 찾아 스위치를 켭니다.",
            ]
        case .fullDiskAccess:
            return [
                "아래 버튼으로 시스템 설정의 전체 디스크 접근 권한 화면을 엽니다.",
                "목록에 OmniIsland가 있으면 스위치를 켭니다.",
                "목록에 없으면 + 버튼을 누르거나, 'Finder에서 앱 보기'로 연 OmniIsland.app을 목록으로 끌어다 놓습니다.",
            ]
        case .calendar:
            return [
                "아래 버튼을 누르면 macOS가 캘린더 접근을 묻는 창을 띄웁니다.",
                "'전체 접근 허용'을 선택합니다. 이미 거부했다면 시스템 설정의 캘린더 화면에서 켭니다.",
            ]
        }
    }

    var isRequired: Bool { self == .accessibility }

    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .fullDiskAccess: anchor = "Privacy_AllFiles"
        case .calendar: anchor = "Privacy_Calendars"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    /// Whether the permission is granted right now.
    @MainActor var isGranted: Bool {
        switch self {
        case .accessibility: return ModifierMonitor.isTrusted(prompt: false)
        case .fullDiskAccess: return NotificationDatabaseReader.hasFullDiskAccess()
        case .calendar: return CalendarProvider.currentAccess() == .granted
        }
    }

    /// The user can still be asked through a system prompt (calendar only).
    var canPrompt: Bool {
        self == .calendar && EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }
}

/// Walks through the permissions one at a time, opens the matching System
/// Settings pane, and moves on by itself once a permission turns on.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var steps: [PermissionKind]
    /// Index into `steps`; `steps.count` is the closing summary.
    @Published var index = 0
    @Published private(set) var granted: [PermissionKind: Bool] = [:]
    @Published private(set) var calendarCanPrompt = false

    var onCalendarGranted: (() -> Void)?
    var onSendTestNotification: (() -> Void)?
    var onFinish: (() -> Void)?

    private var timer: Timer?
    private var advanceWork: DispatchWorkItem?
    private let store = EKEventStore()

    init(steps: [PermissionKind]) {
        self.steps = steps
        refresh()
    }

    var current: PermissionKind? { index < steps.count ? steps[index] : nil }

    func start(at kind: PermissionKind? = nil) {
        if let kind {
            if !steps.contains(kind) { steps.append(kind) }
            index = steps.firstIndex(of: kind) ?? 0
        }
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        advanceWork?.cancel()
    }

    func refresh() {
        var next: [PermissionKind: Bool] = [:]
        for kind in PermissionKind.allCases { next[kind] = kind.isGranted }
        let wasGranted = current.map { granted[$0] ?? false } ?? false
        if next != granted { granted = next }
        calendarCanPrompt = PermissionKind.calendar.canPrompt
        // Move on by itself the moment the current permission turns on.
        if let current, !wasGranted, next[current] == true, timer != nil {
            if current == .calendar { onCalendarGranted?() }
            advanceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.current == current else { return }
                    self.advance()
                }
            }
            advanceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
        }
    }

    func isGranted(_ kind: PermissionKind) -> Bool { granted[kind] ?? false }

    func advance() {
        advanceWork?.cancel()
        if index < steps.count {
            withAnimation(.snappy) { index += 1 }
        }
    }

    func back() {
        advanceWork?.cancel()
        if index > 0 { withAnimation(.snappy) { index -= 1 } }
    }

    func skip() {
        if let current { OnboardingStore.markSkipped(current) }
        advance()
    }

    func perform(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            _ = ModifierMonitor.isTrusted(prompt: true)
            openSettings(kind)
        case .fullDiskAccess:
            openSettings(kind)
        case .calendar:
            if kind.canPrompt {
                NSApp.activate()
                store.requestFullAccessToEvents { [weak self] _, _ in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.refresh() }
                    }
                }
            } else {
                openSettings(kind)
            }
        }
    }

    func openSettings(_ kind: PermissionKind) {
        if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
    }

    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func sendTestNotification() { onSendTestNotification?() }

    func finish() {
        onFinish?()
    }

    /// Closing the window counts as done: optional permissions left off
    /// are not asked about again at launch.
    func dismissed() {
        OnboardingStore.completed = true
        for kind in steps where !isGranted(kind) { OnboardingStore.markSkipped(kind) }
    }

    /// Some permissions (Full Disk Access in particular) only apply after
    /// the app starts again.
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}

/// What the user already went through, kept in UserDefaults.
enum OnboardingStore {
    private static let completedKey = "onboarding.completed"
    private static let skippedKey = "onboarding.skipped"

    static var completed: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    static var skipped: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: skippedKey) ?? [])
    }

    static func markSkipped(_ kind: PermissionKind) {
        guard !kind.isRequired else { return }
        UserDefaults.standard.set(Array(skipped.union([kind.rawValue])), forKey: skippedKey)
    }

    /// Permissions worth walking through for this config.
    @MainActor static func relevant(for config: IslandConfig) -> [PermissionKind] {
        var kinds: [PermissionKind] = [.accessibility]
        if config.notifications.enabled && config.notifications.readDatabase { kinds.append(.fullDiskAccess) }
        kinds.append(.calendar)
        return kinds
    }

    /// Steps to show at launch, or an empty list when nothing is needed:
    /// everything on the first run, later only what is missing and was not
    /// skipped before.
    @MainActor static func launchSteps(for config: IslandConfig) -> [PermissionKind] {
        let kinds = relevant(for: config)
        if !completed { return kinds }
        let skipped = skipped
        return kinds.filter { kind in
            guard !kind.isGranted else { return false }
            if kind == .calendar && !config.calendar.enabled { return false }
            return kind.isRequired || !skipped.contains(kind.rawValue)
        }
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private(set) var model: OnboardingModel?
    var configure: ((OnboardingModel) -> Void)?

    func show(steps: [PermissionKind], at kind: PermissionKind? = nil) {
        if window == nil || model == nil {
            let model = OnboardingModel(steps: steps.isEmpty ? PermissionKind.allCases : steps)
            model.onFinish = { [weak self] in self?.window?.close() }
            configure?(model)
            let host = NSHostingController(rootView: OnboardingView(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "OmniIsland 권한 설정"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 540, height: 470))
            w.center()
            window = w
            self.model = model
        }
        model?.start(at: kind)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        model?.dismissed()
        model = nil
        window = nil
    }
}

// MARK: - Views

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            Group {
                if let kind = model.current {
                    StepView(model: model, kind: kind)
                        .id(kind)
                } else {
                    SummaryView(model: model)
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(width: 540, height: 470)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OmniIsland 시작하기")
                    .font(.title2.weight(.semibold))
                Text("필요한 권한을 하나씩 켭니다. 켜지면 자동으로 다음 단계로 넘어갑니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Array(model.steps.enumerated()), id: \.element) { i, kind in
                    Image(systemName: model.isGranted(kind) ? "checkmark.circle.fill"
                          : (i == model.index ? "circle.inset.filled" : "circle"))
                        .foregroundStyle(model.isGranted(kind) ? Color.green
                                         : (i == model.index ? Color.accentColor : Color.secondary))
                        .help(kind.title)
                }
            }
            .font(.system(size: 14))
        }
    }
}

private struct StepView: View {
    @ObservedObject var model: OnboardingModel
    let kind: PermissionKind

    var body: some View {
        let granted = model.isGranted(kind)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 26, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.15)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(kind.title).font(.title3.weight(.semibold))
                        Text(kind.isRequired ? "필수" : "선택")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    StatusLabel(granted: granted)
                }
            }
            Text(kind.purpose)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(kind.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        Text(step).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                Button(primaryTitle) { model.perform(kind) }
                    .buttonStyle(.borderedProminent)
                    .disabled(granted)
                if kind == .fullDiskAccess {
                    Button("Finder에서 앱 보기") { model.revealApp() }
                }
            }
            if kind == .fullDiskAccess && !granted {
                HStack(spacing: 6) {
                    Text("켰는데도 계속 '아직 허용 안 됨'으로 보이면 앱을 다시 실행해 보세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("다시 실행") { OnboardingModel.relaunch() }
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
            HStack {
                if model.index > 0 {
                    Button("이전") { model.back() }
                }
                Spacer()
                if !granted && !kind.isRequired {
                    Button("건너뛰기") { model.skip() }
                }
                Button(granted ? "다음" : (kind.isRequired ? "나중에 하기" : "다음")) { model.advance() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var primaryTitle: String {
        if model.isGranted(kind) { return "허용됨" }
        switch kind {
        case .calendar: return model.calendarCanPrompt ? "캘린더 접근 허용…" : "시스템 설정 열기"
        default: return "시스템 설정 열기"
        }
    }
}

private struct StatusLabel: View {
    let granted: Bool

    var body: some View {
        HStack(spacing: 4) {
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("허용됨")
            } else {
                ProgressView().controlSize(.mini)
                Text("아직 허용 안 됨, 켜지기를 기다리는 중")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct SummaryView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("설정이 끝났습니다")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.steps) { kind in
                    HStack(spacing: 8) {
                        Image(systemName: model.isGranted(kind) ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(model.isGranted(kind) ? Color.green : Color.orange)
                        Text(kind.title)
                        Spacer()
                        if !model.isGranted(kind) {
                            Button("다시 설정") {
                                if let i = model.steps.firstIndex(of: kind) { model.index = i }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            Text("테스트 알림을 보내면 몇 초 안에 아일랜드에 알림 카드가 떠야 합니다. 뜨지 않으면 메뉴 막대의 알림 메뉴에서 '알림 배너 구조 기록'을 실행한 뒤 기록 파일을 보내 주세요.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("테스트 알림 보내기") { model.sendTestNotification() }
            Spacer(minLength: 0)
            HStack {
                Button("이전") { model.back() }
                Spacer()
                Text("메뉴 막대 아이콘의 '권한 설정…'에서 언제든 다시 열 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("완료") { model.finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
