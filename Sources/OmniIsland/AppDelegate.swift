import AppKit
import SwiftUI

@main
struct OmniIslandMain {
    @MainActor
    static func main() {
        // `omni-island`, `omni-island notify …` and the agent hooks run the
        // same executable.
        if let code = IslandCLI.run(CommandLine.arguments) { exit(code) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private let model = IslandModel()
    private let tracker = WMStateTracker()
    private let client = OmniWMClient()
    private let modifiers = ModifierMonitor()
    private let hotKeys = HotKeyMonitor()
    private let badgeMonitor = DockBadgeMonitor()
    private let notificationWatcher = NotificationWatcher()
    private let calendarProvider = CalendarProvider()
    private let notificationDatabase = NotificationDatabaseWatcher()
    private let deduplicator = NotificationDeduplicator()
    private let socketServer = IslandSocketServer()
    private let agents = AgentMonitor()
    private let aiUsage = AIUsageMonitor()
    private let shelf = ClipboardShelf()
    private var windowController: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var accessibilityMenuItem: NSMenuItem?
    private var configErrorMenuItem: NSMenuItem?
    private var demoStep = 0
    private var settingsModel: SettingsModel?
    private var settingsController: SettingsWindowController?
    private let onboarding = OnboardingWindowController()
    private var recentMenu = NSMenu()

    private let isDemo = CommandLine.arguments.contains("--demo")
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configStore.start()
        model.apply(config: configStore.config)
        observeSystemAppearance()
        installMainMenu()
        setUpSettings()

        let wc = IslandWindowController(model: model)
        windowController = wc
        wc.show()

        configStore.onChange = { [weak self] config in
            self?.configChanged(config)
        }

        tracker.onStateChange = { [weak self] in
            guard let self else { return }
            self.model.update(from: self.tracker)
            self.windowController?.setPreferredDisplay(name: self.tracker.activeDisplay?.name)
            // The island may have grown (more workspaces or apps).
            self.windowController?.reposition()
        }
        tracker.onEvent = { [weak self] event in
            self?.model.present(event)
        }
        model.onActivateApp = { [weak self] app, ws in
            self?.activate(app, in: ws)
        }
        model.onFocusWorkspace = { [weak self] ws in
            self?.focusWorkspace(ws)
        }
        setUpLauncher()
        model.onOpenNotification = { [weak self] n in
            self?.openNotification(n)
        }
        model.onRecentChange = { [weak self] in
            self?.rebuildRecentMenu()
        }

        client.onMessage = { [weak self] message in
            self?.tracker.handle(message)
        }
        client.onStatus = { [weak self] status in
            self?.statusMenuItem?.title = status.label
            self?.settingsModel?.connectionStatus = status.label
        }

        modifiers.configure(modifier: configStore.config.trigger.modifier,
                            exactMatch: configStore.config.trigger.exactMatch,
                            allowShift: configStore.config.trigger.allowShift)
        modifiers.onChange = { [weak self] held in
            self?.model.modifierChanged(held: held)
            if held { self?.badgeMonitor.refresh() }
        }

        badgeMonitor.onChange = { [weak self] labels in
            self?.model.setBadges(labels)
        }
        configureBadges(configStore.config)

        aiUsage.onChange = { [weak self] usage in
            self?.model.setAIUsage(usage)
        }
        model.onCloseAllNotifications = { [weak self] in
            self?.notificationWatcher.dismissVisibleBanners()
        }
        notificationWatcher.onNotification = { [weak self] notification in
            self?.receive(notification)
        }
        notificationDatabase.onNotification = { [weak self] notification in
            guard let self else { return }
            self.receive(notification)
            if self.configStore.config.notifications.dismissSystemBanner {
                self.notificationWatcher.dismissVisibleBanners()
            }
        }
        notificationDatabase.onStatus = { [weak self] status in
            self?.settingsModel?.notificationDatabaseStatus = status
        }
        calendarProvider.onChange = { [weak self] events in
            self?.model.setCalendarEvents(events)
            self?.windowController?.reposition()
        }
        calendarProvider.onAlert = { [weak self] event, minutes in
            guard let self, self.configStore.config.calendar.showAlerts else { return }
            self.model.present(notification: event.alertNotification(minutesBefore: minutes))
        }
        calendarProvider.onAccessChange = { [weak self] access in
            self?.settingsModel?.calendarAccess = access
        }
        configureWidgets(configStore.config)
        setUpAgents()
        setUpOnboarding()
        let launchSteps = isDemo ? [] : OnboardingStore.launchSteps(for: configStore.config)
        // The onboarding window explains Accessibility before macOS asks.
        modifiers.start(promptForAccessibility: !isDemo && launchSteps.isEmpty)

        rebuildStatusItem()
        settingsModel?.connectionStatus = isDemo ? "데모 모드" : client.status.label

        if !launchSteps.isEmpty {
            onboarding.show(steps: launchSteps)
        } else if configStore.createdDefaultFile || !configStore.config.behavior.showMenuBarIcon {
            showSettings()
        }

        if isDemo {
            loadDemoState()
        } else {
            client.start(executablePath: configStore.config.omniwmctlPath,
                         socketPath: configStore.config.socketPath)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        client.stop()
    }

    // MARK: - System appearance

    /// Keeps `model.systemIsDark` in step with macOS dark mode, for
    /// theme.mode = system.
    private func observeSystemAppearance() {
        updateSystemAppearance()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateSystemAppearance() }
            }
        }
        _ = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            // effectiveAppearance updates a moment after the notification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                MainActor.assumeIsolated { self?.updateSystemAppearance() }
            }
        }
    }

    private func updateSystemAppearance() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if model.systemIsDark != dark {
            withAnimation(model.swiftUIAnimation) { model.systemIsDark = dark }
        }
        settingsModel?.systemIsDark = dark
    }

    // MARK: - Config

    private func configChanged(_ config: IslandConfig) {
        let previous = model.config
        model.apply(config: config)
        model.update(from: tracker)
        modifiers.configure(modifier: config.trigger.modifier, exactMatch: config.trigger.exactMatch,
                            allowShift: config.trigger.allowShift)
        configureBadges(config)
        configureWidgets(config)
        configureLauncher(config)
        configureShelf(config)
        agents.config = config.agents
        windowController?.reposition()
        if previous.omniwmctlPath != config.omniwmctlPath || previous.socketPath != config.socketPath {
            if !isDemo {
                client.restart(executablePath: config.omniwmctlPath, socketPath: config.socketPath)
            }
        }
        if previous.behavior.showMenuBarIcon != config.behavior.showMenuBarIcon {
            rebuildStatusItem()
        }
        settingsModel?.sync(config)
        settingsModel?.configError = configStore.lastError
        configErrorMenuItem?.title = configStore.lastError ?? ""
        configErrorMenuItem?.isHidden = configStore.lastError == nil
    }

    // MARK: - Agents and the local socket

    private func setUpAgents() {
        agents.config = configStore.config.agents
        agents.windowsProvider = { [weak self] in
            guard let self else { return ([], nil) }
            return (self.tracker.windows, self.tracker.focusedWindowId)
        }
        agents.onSessionsChange = { [weak self] sessions in
            self?.model.setAgentSessions(sessions)
            // A finished or started turn changes the token counts.
            self?.aiUsage.refresh()
            self?.windowController?.reposition()
        }
        agents.present = { [weak self] n in self?.model.present(notification: n) }
        agents.dismiss = { [weak self] id in self?.model.dismiss(externalId: id) }
        agents.start()
        model.onNotificationAction = { [weak self] n, action in
            self?.agents.perform(action, on: n)
        }
        model.onOpenAgent = { [weak self] session in
            self?.focusTerminal(windowId: session.windowId, bundleId: session.bundleId)
        }
        socketServer.onRequest = { [weak self] request, reply in
            guard let self else { return reply(nil) }
            self.handle(request: request, reply: reply)
        }
        socketServer.start()
    }

    private func handle(request: [String: Any], reply: @escaping ([String: Any]?) -> Void) {
        switch request["type"] as? String ?? "" {
        case "agent":
            agents.handle(request, reply: reply)
        case "notify":
            model.present(notification: Self.externalNotification(request))
            reply(["ok": true])
        case "dismiss":
            if let id = request["id"] as? String { model.dismiss(externalId: "ext:" + id) }
            reply(["ok": true])
        case "settings":
            showSettings()
            reply(["ok": true])
        case "launcher":
            model.toggleLauncher()
            reply(["ok": true])
        case "quit":
            reply(["ok": true])
            DispatchQueue.main.async { NSApp.terminate(nil) }
        default:
            reply(["ok": false, "error": "unknown type"])
        }
    }

    /// A card from `omni-island notify`.
    private static func externalNotification(_ r: [String: Any]) -> IslandNotification {
        func text(_ key: String) -> String? {
            (r[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        var n = IslandNotification(source: .external, appName: text("app") ?? "알림",
                                   bundleId: text("bundle-id"), title: text("title") ?? "",
                                   subtitle: text("subtitle"), body: text("body"))
        n.symbol = text("icon") ?? (n.bundleId == nil ? "bell.fill" : nil)
        n.tint = text("color")
        if let seconds = (r["duration"] as? NSNumber)?.doubleValue, seconds > 0 {
            n.durationMs = seconds * 1000
        }
        if let progress = (r["progress"] as? NSNumber)?.doubleValue {
            n.detail = "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
        }
        if let id = text("id") {
            n.externalId = "ext:" + id
            n.group = "ext:" + id
        }
        return n
    }

    /// Goes to the OmniWM window an agent runs in, or its terminal app.
    private func focusTerminal(windowId: String?, bundleId: String?) {
        if let windowId {
            runWindowCommand(["window", "navigate", windowId], fallbackBundleId: bundleId)
        } else if let bundleId {
            activateApp(bundleId: bundleId)
        }
    }

    @objc private func toggleClaudeHooks() {
        do {
            if ClaudeHookInstaller.isInstalled() {
                try ClaudeHookInstaller.uninstall()
            } else {
                try ClaudeHookInstaller.install()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Claude Code 훅을 바꾸지 못했습니다"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        rebuildStatusItem()
        settingsModel?.claudeHooksInstalled = ClaudeHookInstaller.isInstalled()
    }

    // MARK: - Launcher

    private func setUpLauncher() {
        hotKeys.onPress = { [weak self] in self?.model.toggleLauncher() }
        configureLauncher(configStore.config)
        let launcher = model.launcher
        launcher.windowsProvider = { [weak self] in self?.launcherWindows() ?? [] }
        launcher.onOpenApp = { app in
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        }
        launcher.onRevealApp = { app in
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
        }
        launcher.onFocusWindow = { [weak self] window in
            self?.runWindowCommand(["window", "navigate", window.id], fallbackBundleId: window.bundleId)
        }
        launcher.onOpenSettings = { [weak self] in self?.showSettings() }
        launcher.shelfProvider = { [weak self] in
            guard let self, self.configStore.config.shelf.enabled else { return [] }
            return self.shelf.items
        }
        launcher.onCopyShelf = { [weak self] items in self?.shelf.copy(items) }
        launcher.onPasteShelf = { [weak self] items in
            guard let self else { return }
            let restoreInput = self.model.holdInputSourceForPaste()
            self.shelf.paste(items) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    MainActor.assumeIsolated { restoreInput() }
                }
            }
        }
        launcher.onRemoveShelf = { [weak self] item in self?.shelf.remove(item) }
        launcher.shelfDragProvider = { [weak self] item in self?.shelf.itemProvider(item) ?? NSItemProvider() }
        configureShelf(configStore.config)
        launcher.onSummonWindow = { [weak self] window in
            self?.runWindowCommand(["window", "summon-right", window.id], fallbackBundleId: window.bundleId)
        }
    }

    /// Open windows for the launcher: by workspace (number, then OmniWM's
    /// workspace order), then in layout order within the workspace.
    private func launcherWindows() -> [LauncherWindow] {
        let workspaceIndex = Dictionary(
            tracker.workspaces.enumerated().map { ($0.element.ref.key, $0.offset) },
            uniquingKeysWith: { first, _ in first })
        var rows: [(window: LauncherWindow, key: (Int, Int, Int))] = []
        for (offset, w) in tracker.windows.enumerated() {
            guard let id = w.id, w.isScratchpad != true else { continue }
            let ws = w.workspace
            let window = LauncherWindow(id: id, appName: w.app?.name ?? "?", bundleId: w.app?.bundleId,
                                        title: w.title ?? "",
                                        workspaceLabel: ws.map { model.label(for: $0) } ?? "?")
            let key = (ws?.number ?? Int.max,
                       ws.flatMap { workspaceIndex[$0.key] } ?? Int.max,
                       offset)
            rows.append((window, key))
        }
        return rows.sorted { $0.key < $1.key }.map(\.window)
    }

    private func configureShelf(_ config: IslandConfig) {
        let s = config.shelf
        shelf.configure(.init(enabled: s.enabled && !isDemo, maxItems: Int(s.maxItems.rounded()),
                              captureImages: s.captureImages, captureFiles: s.captureFiles,
                              ignoreApps: s.ignoreApps))
    }

    @objc private func clearShelf() {
        shelf.clear()
    }

    private func configureLauncher(_ config: IslandConfig) {
        let wanted = (config.launcher.enabled ? config.launcher.hotkey : "").trimmingCharacters(in: .whitespaces)
        if hotKeys.registeredSpec == wanted || (wanted.isEmpty && hotKeys.registeredSpec == nil) { return }
        hotKeys.register(wanted)
    }

    private func runWindowCommand(_ arguments: [String], fallbackBundleId: String?) {
        let fallback = { [weak self] in
            if let bundleId = fallbackBundleId { self?.activateApp(bundleId: bundleId) }
        }
        guard !isDemo else {
            fallback()
            return
        }
        let config = configStore.config
        OmniWMClient.run(arguments, executablePath: config.omniwmctlPath, socketPath: config.socketPath) { ok in
            if !ok { fallback() }
        }
    }

    private func configureBadges(_ config: IslandConfig) {
        let wanted = config.appearance.showBadges && config.appearance.workspaceStyle.lowercased() != "pills"
        badgeMonitor.configure(enabled: wanted && !isDemo, intervalMs: config.behavior.badgeIntervalMs)
    }

    private func configureWidgets(_ config: IslandConfig) {
        notificationWatcher.configure(enabled: config.notifications.enabled && !isDemo,
                                      dismissSystemBanner: config.notifications.dismissSystemBanner)
        calendarProvider.configure(enabled: config.calendar.enabled,
                                   calendars: config.calendar.calendars,
                                   alertMinutes: config.calendar.alertMinutes.map { Int($0.rounded()) },
                                   includeAllDay: config.calendar.includeAllDay)
        notificationDatabase.configure(enabled: config.notifications.enabled && config.notifications.readDatabase && !isDemo)
        aiUsage.configure(config.usage, used: config.showsUsage)
        settingsModel?.calendarAccess = calendarProvider.access
        settingsModel?.notificationDatabaseStatus = notificationDatabase.status
    }

    // MARK: - Notification history

    private func openNotification(_ n: IslandNotification) {
        if n.source == .agent || n.windowId != nil {
            return focusTerminal(windowId: n.windowId, bundleId: n.bundleId)
        }
        let bundleId = n.source == .calendar ? "com.apple.iCal" : n.bundleId
        if let bundleId, !bundleId.isEmpty { activateApp(bundleId: bundleId) }
    }

    private func rebuildRecentMenu() {
        recentMenu.removeAllItems()
        let list = model.recentNotifications
        if list.isEmpty {
            let empty = NSMenuItem(title: "받은 알림이 없습니다", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
            return
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        for (index, n) in list.prefix(15).enumerated() {
            let text = model.visibleText(n)
            var title = "\(formatter.string(from: n.date))  \(n.appName) · \(text.title)"
            if let body = text.body ?? text.subtitle { title += " — " + body }
            if title.count > 80 { title = String(title.prefix(79)) + "…" }
            let item = NSMenuItem(title: title, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            recentMenu.addItem(item)
        }
        recentMenu.addItem(.separator())
        recentMenu.addItem(makeItem("기록 지우기", #selector(clearRecent), ""))
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        let list = model.recentNotifications
        guard list.indices.contains(sender.tag) else { return }
        openNotification(list[sender.tag])
    }

    @objc private func clearRecent() {
        model.clearRecent()
    }

    // MARK: - Permissions

    private func setUpOnboarding() {
        onboarding.configure = { [weak self] model in
            model.onSendTestNotification = { NotificationWatcher.sendTestNotification() }
            model.onCalendarGranted = { [weak self] in self?.enableCalendar() }
        }
    }

    /// Granting calendar access in the onboarding means the user wants it.
    private func enableCalendar() {
        var config = configStore.config
        guard !config.calendar.enabled else {
            calendarProvider.refresh()
            return
        }
        config.calendar.enabled = true
        configStore.save(config)
    }

    @objc private func showPermissionsWindow() {
        onboarding.show(steps: OnboardingStore.relevant(for: configStore.config))
    }

    private func showOnboarding(at kind: PermissionKind) {
        onboarding.show(steps: OnboardingStore.relevant(for: configStore.config), at: kind)
    }

    // MARK: - Clicks in the workspace row

    /// Brings the clicked window forward through OmniWM (which also switches
    /// workspace), falling back to activating the app.
    private func activate(_ app: WorkspaceApp, in ws: WorkspaceItem) {
        let fallback = { [weak self] in
            if let bundleId = app.bundleId { self?.activateApp(bundleId: bundleId) }
        }
        guard !isDemo, let id = app.targetWindowId else {
            fallback()
            return
        }
        let config = configStore.config
        OmniWMClient.run(["window", "navigate", id], executablePath: config.omniwmctlPath,
                         socketPath: config.socketPath) { ok in
            if !ok { fallback() }
        }
    }

    private func focusWorkspace(_ ws: WorkspaceItem) {
        guard !isDemo else { return }
        let name = ws.rawName ?? ws.label
        let config = configStore.config
        OmniWMClient.run(["workspace", "focus-name", name], executablePath: config.omniwmctlPath,
                         socketPath: config.socketPath) { _ in }
    }

    private func activateApp(bundleId: String) {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Banner observation and the database usually both see a notification.
    private func receive(_ notification: IslandNotification) {
        guard deduplicator.accept(notification) else { return }
        model.present(notification: notification)
    }

    // MARK: - Status item

    private func rebuildStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        guard configStore.config.behavior.showMenuBarIcon else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "OmniIsland")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        let versionItem = NSMenuItem(
            title: "OmniIsland \(version)" + (build.map { " (\($0))" } ?? ""),
            action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        let status = NSMenuItem(title: isDemo ? "데모 모드" : client.status.label, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        let configError = NSMenuItem(title: configStore.lastError ?? "", action: nil, keyEquivalent: "")
        configError.isEnabled = false
        configError.isHidden = configStore.lastError == nil
        menu.addItem(configError)
        configErrorMenuItem = configError

        let ax = NSMenuItem(title: "손쉬운 사용 권한 허용…", action: #selector(openAccessibility), keyEquivalent: "")
        ax.target = self
        menu.addItem(ax)
        accessibilityMenuItem = ax
        menu.addItem(makeItem("권한 설정…", #selector(showPermissionsWindow), ""))

        menu.addItem(.separator())
        menu.addItem(makeItem("애니메이션 미리보기", #selector(playDemo), "p"))
        let notifications = NSMenuItem(title: "알림", action: nil, keyEquivalent: "")
        let notificationMenu = NSMenu()
        notificationMenu.addItem(makeItem("알림 카드 미리보기", #selector(previewNotification), ""))
        notificationMenu.addItem(makeItem("테스트 알림 보내기", #selector(sendTestNotification), ""))
        notificationMenu.addItem(makeItem("알림 배너 구조 기록 (1분)", #selector(recordNotificationDiagnostics), ""))
        notifications.submenu = notificationMenu
        menu.addItem(notifications)
        let recent = NSMenuItem(title: "최근 알림", action: nil, keyEquivalent: "")
        recentMenu = NSMenu()
        recent.submenu = recentMenu
        menu.addItem(recent)
        menu.addItem(makeItem("클립보드 기록 비우기", #selector(clearShelf), ""))
        let hooks = makeItem("Claude Code 훅 설치", #selector(toggleClaudeHooks), "")
        hooks.state = ClaudeHookInstaller.isInstalled() ? .on : .off
        menu.addItem(hooks)
        rebuildRecentMenu()
        menu.addItem(makeItem("설정…", #selector(showSettings), ","))
        menu.addItem(makeItem("설정 파일 열기", #selector(openConfig), ""))
        menu.addItem(makeItem("설정 다시 불러오기", #selector(reloadConfig), "r"))
        menu.addItem(makeItem("OmniWM 다시 연결", #selector(reconnect), ""))
        menu.addItem(makeItem("아일랜드 위치 되돌리기", #selector(resetIslandPosition), ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("OmniIsland 종료", #selector(quit), "q"))
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again (e.g. from Finder) shows the settings, which
        // matters when the menu bar icon is hidden.
        showSettings()
        return false
    }

    private func setUpSettings() {
        let settings = SettingsModel(config: configStore.config, configPath: configStore.fileURL.path)
        settings.systemIsDark = model.systemIsDark
        settings.onSave = { [weak self] config in
            guard let self else { return config }
            let normalized = self.configStore.save(config)
            self.settingsModel?.configError = self.configStore.lastError
            return normalized
        }
        settings.onPreview = { [weak self] in self?.playDemo() }
        settings.onOpenFile = { [weak self] in self?.openConfig() }
        settings.onOpenAccessibility = { [weak self] in
            self?.openAccessibility()
        }
        settings.onPreviewNotification = { [weak self] in self?.previewNotification() }
        settings.onSendTestNotification = { NotificationWatcher.sendTestNotification() }
        settings.onRecordNotificationDiagnostics = { [weak self] in self?.recordNotificationDiagnostics() }
        settings.onOpenFullDiskAccess = { [weak self] in
            self?.showOnboarding(at: .fullDiskAccess)
        }
        settings.claudeHooksInstalled = ClaudeHookInstaller.isInstalled()
        settings.onToggleClaudeHooks = { [weak self] in self?.toggleClaudeHooks() }
        settings.onTestAgentCard = { [weak self] in
            var n = IslandNotification(source: .agent, appName: "Claude Code · omni-island", bundleId: nil,
                                       title: "Bash 실행을 허용할까요?", subtitle: nil,
                                       body: "Bash: swift build")
            n.symbol = "sparkle"
            n.tint = AgentSession.State.approval.color
            n.actions = [AgentMonitor.allowAction, AgentMonitor.denyAction]
            self?.model.present(notification: n)
        }
        settings.onOpenCalendarPrivacy = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        }
        settingsModel = settings
        settingsController = SettingsWindowController(model: settings)
    }

    @objc private func showSettings() {
        settingsModel?.accessibilityGranted = ModifierMonitor.isTrusted(prompt: false)
        settingsModel?.configError = configStore.lastError
        settingsController?.show()
    }

    /// Accessory apps have no visible menu bar, but the main menu still
    /// provides ⌘C / ⌘V / ⌘A / ⌘W in the settings window.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "OmniIsland 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "윈도우")
        windowMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    @objc private func previewNotification() {
        model.previewNotification()
    }

    @objc private func sendTestNotification() {
        NotificationWatcher.sendTestNotification()
    }

    /// Records the Notification Center tree for a minute while a test banner
    /// arrives, then shows the log so it can be attached to a bug report.
    @objc private func recordNotificationDiagnostics() {
        let n = configStore.config.notifications
        let context = [
            "notifications.enabled: \(n.enabled), readDatabase: \(n.readDatabase)",
            "full disk access: \(NotificationDatabaseReader.hasFullDiskAccess())",
            "database: \(notificationDatabase.status.label) \(notificationDatabase.currentPath ?? "")",
            "database candidates: \(NotificationDatabaseReader.candidatePaths.joined(separator: ", "))",
        ]
        let url = notificationWatcher.recordDiagnostics(seconds: 60, context: context)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NotificationWatcher.sendTestNotification()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 62) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(configStore.fileURL)
    }

    @objc private func reloadConfig() {
        configStore.reload()
        configChanged(configStore.config)
    }

    @objc private func resetIslandPosition() {
        windowController?.resetPosition()
    }

    @objc private func reconnect() {
        guard !isDemo else { return }
        tracker.reset()
        client.restart(executablePath: configStore.config.omniwmctlPath,
                       socketPath: configStore.config.socketPath)
    }

    @objc private func openAccessibility() {
        _ = ModifierMonitor.isTrusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Demo

    /// Fills the model with fake workspaces so the island can be tried
    /// without OmniWM (`OmniIsland --demo`, or the menu's preview item).
    private func loadDemoState() {
        let display = DisplayRef(id: "demo", name: "Demo", isMain: true)
        let names = ["1", "2", "3", "4", "5"]
        let counts = [3, 1, 0, 2, 0]
        var workspaces: [WorkspaceSnapshot] = []
        for (index, name) in names.enumerated() {
            let count: Int = counts[index]
            let isFirst: Bool = index == 0
            let windowCounts = WorkspaceSnapshot.Counts(total: count, tiled: count, floating: 0, scratchpad: 0)
            let snapshot = WorkspaceSnapshot(
                id: "ws-" + name,
                rawName: name,
                displayName: name,
                number: index + 1,
                display: display,
                isFocused: isFirst,
                isVisible: isFirst,
                isCurrent: isFirst,
                counts: windowCounts
            )
            workspaces.append(snapshot)
        }
        tracker.handle(.workspaces(WorkspacesPayload(workspaces: workspaces)))

        let demoApps: [(String, String, String)] = [
            ("1", "Finder", "com.apple.finder"),
            ("1", "Safari", "com.apple.Safari"),
            ("1", "Safari", "com.apple.Safari"),
            ("2", "Messages", "com.apple.MobileSMS"),
            ("4", "Mail", "com.apple.mail"),
            ("4", "System Settings", "com.apple.systempreferences"),
        ]
        var demoWindows: [WindowSnapshot] = []
        for (index, entry) in demoApps.enumerated() {
            let ws = workspaces.first { $0.rawName == entry.0 }?.ref
            let window = WindowSnapshot(
                id: "demo-\(index)",
                workspace: ws,
                display: display,
                app: AppRef(name: entry.1, bundleId: entry.2),
                title: entry.1,
                isFocused: index == 0,
                isScratchpad: false,
                mode: entry.1 == "System Settings" ? "floating" : "tiling",
                pid: nil
            )
            demoWindows.append(window)
        }
        tracker.handle(.windows(WindowsPayload(windows: demoWindows)))
        model.setBadges(["com.apple.mobilesms": "2", "com.apple.mail": "•"])
        tracker.handle(.activeWorkspace(ActiveWorkspacePayload(
            display: display,
            workspace: workspaces[0].ref,
            focusedApp: AppRef(name: "Finder", bundleId: "com.apple.finder")
        )))
    }

    @objc private func playDemo() {
        if tracker.workspaces.isEmpty { loadDemoState() }
        let items = model.workspaces
        guard items.count >= 2 else {
            model.preview(.workspaceSwitch(
                from: WorkspaceRef(id: "a", rawName: "1", displayName: "1", number: 1),
                to: WorkspaceRef(id: "b", rawName: "2", displayName: "2", number: 2),
                app: AppRef(name: "Finder", bundleId: "com.apple.finder")
            ))
            return
        }
        let current = items.firstIndex { $0.id == model.activeWorkspaceKey } ?? 0
        let next = (current + 1) % items.count
        let from = WorkspaceRef(id: items[current].id, rawName: items[current].label,
                                displayName: items[current].label, number: items[current].number)
        let to = WorkspaceRef(id: items[next].id, rawName: items[next].label,
                              displayName: items[next].label, number: items[next].number)
        demoStep += 1
        if demoStep % 2 == 0 {
            model.preview(.windowMove(
                app: AppRef(name: "Safari", bundleId: "com.apple.Safari"),
                title: "OmniWM – GitHub", from: from, to: to, count: 1
            ))
        } else {
            if isDemo {
                // The tracker sees a real-looking switch and raises the event itself.
                tracker.handle(.activeWorkspace(ActiveWorkspacePayload(
                    display: DisplayRef(id: "demo", name: "Demo", isMain: true),
                    workspace: to, focusedApp: model.focusedApp
                )))
            } else {
                model.preview(.workspaceSwitch(from: from, to: to, app: model.focusedApp))
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let trusted = ModifierMonitor.isTrusted(prompt: false)
        accessibilityMenuItem?.isHidden = trusted
        settingsModel?.accessibilityGranted = trusted
        if !isDemo { statusMenuItem?.title = client.status.label }
    }
}
