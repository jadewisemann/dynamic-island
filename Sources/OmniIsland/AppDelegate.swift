import AppKit

@main
struct OmniIslandMain {
    @MainActor
    static func main() {
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
    private let badgeMonitor = DockBadgeMonitor()
    private var windowController: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var accessibilityMenuItem: NSMenuItem?
    private var configErrorMenuItem: NSMenuItem?
    private var demoStep = 0
    private var settingsModel: SettingsModel?
    private var settingsController: SettingsWindowController?

    private let isDemo = CommandLine.arguments.contains("--demo")

    func applicationDidFinishLaunching(_ notification: Notification) {
        configStore.start()
        model.apply(config: configStore.config)
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

        client.onMessage = { [weak self] message in
            self?.tracker.handle(message)
        }
        client.onStatus = { [weak self] status in
            self?.statusMenuItem?.title = status.label
            self?.settingsModel?.connectionStatus = status.label
        }

        modifiers.configure(modifier: configStore.config.trigger.modifier,
                            exactMatch: configStore.config.trigger.exactMatch)
        modifiers.onChange = { [weak self] held in
            self?.model.modifierChanged(held: held)
            if held { self?.badgeMonitor.refresh() }
        }

        badgeMonitor.onChange = { [weak self] labels in
            self?.model.setBadges(labels)
        }
        configureBadges(configStore.config)
        modifiers.start(promptForAccessibility: !isDemo)

        rebuildStatusItem()
        settingsModel?.connectionStatus = isDemo ? "데모 모드" : client.status.label

        if configStore.createdDefaultFile || !configStore.config.behavior.showMenuBarIcon {
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

    // MARK: - Config

    private func configChanged(_ config: IslandConfig) {
        let previous = model.config
        model.apply(config: config)
        model.update(from: tracker)
        modifiers.configure(modifier: config.trigger.modifier, exactMatch: config.trigger.exactMatch)
        configureBadges(config)
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

    private func configureBadges(_ config: IslandConfig) {
        let wanted = config.appearance.showBadges && config.appearance.workspaceStyle.lowercased() != "pills"
        badgeMonitor.configure(enabled: wanted && !isDemo, intervalMs: config.behavior.badgeIntervalMs)
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

        menu.addItem(.separator())
        menu.addItem(makeItem("애니메이션 미리보기", #selector(playDemo), "p"))
        menu.addItem(makeItem("설정…", #selector(showSettings), ","))
        menu.addItem(makeItem("설정 파일 열기", #selector(openConfig), ""))
        menu.addItem(makeItem("설정 다시 불러오기", #selector(reloadConfig), "r"))
        menu.addItem(makeItem("OmniWM 다시 연결", #selector(reconnect), ""))
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

    @objc private func openConfig() {
        NSWorkspace.shared.open(configStore.fileURL)
    }

    @objc private func reloadConfig() {
        configStore.reload()
        configChanged(configStore.config)
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
                isScratchpad: false
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
