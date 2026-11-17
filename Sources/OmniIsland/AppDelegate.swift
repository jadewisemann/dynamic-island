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
    private var windowController: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var accessibilityMenuItem: NSMenuItem?
    private var configErrorMenuItem: NSMenuItem?
    private var demoStep = 0

    private let isDemo = CommandLine.arguments.contains("--demo")

    func applicationDidFinishLaunching(_ notification: Notification) {
        configStore.start()
        model.apply(config: configStore.config)

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
        }
        tracker.onEvent = { [weak self] event in
            self?.model.present(event)
        }

        client.onMessage = { [weak self] message in
            self?.tracker.handle(message)
        }
        client.onStatus = { [weak self] status in
            self?.statusMenuItem?.title = status.label
        }

        modifiers.configure(modifier: configStore.config.trigger.modifier,
                            exactMatch: configStore.config.trigger.exactMatch)
        modifiers.onChange = { [weak self] held in
            self?.model.modifierChanged(held: held)
        }
        modifiers.start(promptForAccessibility: !isDemo)

        rebuildStatusItem()

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
        windowController?.reposition()
        if previous.omniwmctlPath != config.omniwmctlPath || previous.socketPath != config.socketPath {
            if !isDemo {
                client.restart(executablePath: config.omniwmctlPath, socketPath: config.socketPath)
            }
        }
        if previous.behavior.showMenuBarIcon != config.behavior.showMenuBarIcon {
            rebuildStatusItem()
        }
        configErrorMenuItem?.title = configStore.lastError ?? ""
        configErrorMenuItem?.isHidden = configStore.lastError == nil
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
        menu.addItem(makeItem("설정 파일 열기", #selector(openConfig), ","))
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
        let workspaces = zip(names, counts).map { name, count in
            WorkspaceSnapshot(
                id: "ws-\(name)", rawName: name, displayName: name, number: Int(name),
                display: display, isFocused: name == "1", isVisible: name == "1", isCurrent: name == "1",
                counts: .init(total: count, tiled: count, floating: 0, scratchpad: 0)
            )
        }
        tracker.handle(.workspaces(WorkspacesPayload(workspaces: workspaces)))
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
        accessibilityMenuItem?.isHidden = ModifierMonitor.isTrusted(prompt: false)
        if !isDemo { statusMenuItem?.title = client.status.label }
    }
}
