import AppKit
import ApplicationServices

/// One notification the island can show: a banner read from macOS
/// Notification Center, or an alert the island makes itself (calendar).
struct IslandNotification: Identifiable, Equatable {
    enum Source: Equatable {
        case system
        case calendar
        /// A coding agent (Claude Code, Codex) reporting through its hooks.
        case agent
        /// Sent by `omni-island notify` or another local client.
        case external
    }

    let id = UUID()
    var source: Source
    var appName: String
    var bundleId: String?
    var title: String
    var subtitle: String?
    var body: String?
    var date = Date()
    /// Extra text shown on the right of the title (e.g. "14:00–14:30").
    var detail: String?
    /// SF Symbol drawn instead of the app icon.
    var symbol: String? = nil
    /// Color of `symbol`, `#RRGGBB`.
    var tint: String? = nil
    /// Buttons on the card (e.g. allow / deny for an agent).
    var actions: [NotificationAction] = []
    /// Overrides notifications.durationMs for this card.
    var durationMs: Double? = nil
    /// OmniWM window to focus when the card is clicked.
    var windowId: String? = nil
    /// Id chosen by the sender: a newer card with the same id replaces this
    /// one, and `omni-island dismiss` removes it.
    var externalId: String? = nil
    /// Overrides the merge key (one agent session per card).
    var group: String? = nil
    /// Opaque value for whoever handles the card's actions.
    var payload: String? = nil

    /// Used to merge repeated banners from the same app.
    var groupKey: String { group ?? (bundleId ?? appName).lowercased() }
}

/// A button on a notification card.
struct NotificationAction: Identifiable, Equatable {
    enum Role: Equatable { case primary, destructive, normal }
    let id: String
    let label: String
    var role: Role = .normal
}

/// What was read from one banner element in Notification Center.
struct BannerItem {
    var element: AXUIElement
    var subrole: String?
    var identifier: String?
    var description: String?
    var texts: [String]

    /// Stable enough to tell "already seen" from "new" between scans.
    var signature: String {
        ([description ?? ""] + texts).joined(separator: "\u{1F}")
    }
}

/// Reads banners out of the NotificationCenter process through Accessibility.
///
/// macOS has no API to read other apps' notifications. Banners are drawn by the
/// `com.apple.notificationcenterui` process, whose windows expose the banner
/// text as AXStaticText elements. The exact tree changes between macOS
/// versions, so this reader looks for the notification subroles first and
/// falls back to "a group that contains text" when they are missing.
enum NotificationBannerReader {
    static let bundleId = "com.apple.notificationcenterui"

    static func process() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    struct Snapshot {
        var items: [BannerItem]
        /// True when the Notification Center history panel is open: every old
        /// notification is on screen then, and none of them is new.
        var panelOpen: Bool
        var windowCount: Int
    }

    static func snapshot(pid: pid_t) -> Snapshot {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let windows = children(of: app, attribute: "AXWindows")
        var items: [BannerItem] = []
        var panelOpen = false
        let screenHeight = NSScreen.screens.map(\.frame.height).max() ?? 900
        for window in windows {
            var found: [BannerItem] = []
            collectItems(in: window, depth: 0, into: &found)
            // Recent macOS versions draw banners inside a screen-tall,
            // transparent window, so height alone does not mean the history
            // panel is open: it also has to hold more than a banner stack.
            if let size = size(of: window), size.height > screenHeight * 0.6, found.count > 3 {
                panelOpen = true
            }
            items += found
        }
        return Snapshot(items: items, panelOpen: panelOpen, windowCount: windows.count)
    }

    static func windowCount(pid: pid_t) -> Int {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        return children(of: app, attribute: "AXWindows").count
    }

    private static func isNotificationSubrole(_ subrole: String?) -> Bool {
        guard let subrole else { return false }
        return subrole.hasPrefix("AXNotificationCenter")
    }

    private static func collectItems(in element: AXUIElement, depth: Int, into items: inout [BannerItem]) {
        guard depth < 14 else { return }
        let subrole = string(element, "AXSubrole")
        if isNotificationSubrole(subrole) {
            items.append(item(for: element, subrole: subrole))
            return
        }
        let kids = children(of: element)
        // Fallback for trees without the notification subroles: the deepest
        // group that directly holds text is one banner.
        if string(element, "AXRole") == "AXGroup",
           kids.contains(where: { string($0, "AXRole") == "AXStaticText" }),
           !kids.contains(where: { isNotificationSubrole(string($0, "AXSubrole")) }) {
            let candidate = item(for: element, subrole: subrole)
            if !candidate.texts.isEmpty {
                items.append(candidate)
                return
            }
        }
        for child in kids {
            collectItems(in: child, depth: depth + 1, into: &items)
        }
    }

    private static func item(for element: AXUIElement, subrole: String?) -> BannerItem {
        var texts: [String] = []
        collectTexts(in: element, depth: 0, into: &texts)
        return BannerItem(
            element: element,
            subrole: subrole,
            identifier: string(element, "AXIdentifier"),
            description: string(element, "AXDescription"),
            texts: texts
        )
    }

    private static func collectTexts(in element: AXUIElement, depth: Int, into texts: inout [String]) {
        guard depth < 6 else { return }
        for child in children(of: element) {
            if string(child, "AXRole") == "AXStaticText" {
                let value = (string(child, "AXValue") ?? string(child, "AXDescription") ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { texts.append(value) }
            } else {
                collectTexts(in: child, depth: depth + 1, into: &texts)
            }
        }
    }

    // MARK: - Turning a banner into a notification

    static func notification(from item: BannerItem) -> IslandNotification {
        var texts = item.texts
        let descriptionParts = (item.description ?? "")
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // The app name is either one of the texts (stacked banners show it as a
        // header) or the first part of the banner's accessibility description.
        var app: AppMatch?
        for (index, text) in texts.enumerated() {
            if let match = AppMatch.find(named: text) {
                app = match
                texts.remove(at: index)
                break
            }
        }
        if app == nil, let first = descriptionParts.first {
            app = AppMatch.find(named: first)
        }
        texts.removeAll(where: isRelativeTime)

        let appName = app?.name ?? descriptionParts.first ?? "알림"
        let title = texts.first ?? appName
        var subtitle: String?
        var body: String?
        switch texts.count {
        case 0, 1: break
        case 2: body = texts[1]
        default:
            subtitle = texts[1]
            body = texts[2...].joined(separator: "\n")
        }
        return IslandNotification(
            source: .system,
            appName: appName,
            bundleId: app?.bundleId,
            title: title,
            subtitle: subtitle,
            body: body
        )
    }

    /// "now", "지금", "2m ago", "5분 전" and similar banner timestamps.
    private static func isRelativeTime(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        if t == "now" || t == "지금" || t == "방금" { return true }
        let pattern = #"^\d+\s*(m|min|h|hr|d|분|시간|일)(\s*ago|\s*전)?$"#
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    struct AppMatch {
        var name: String
        var bundleId: String?

        private static let lock = NSLock()
        nonisolated(unsafe) private static var cache: [String: AppMatch?] = [:]

        static func find(named rawName: String) -> AppMatch? {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 60 else { return nil }
            lock.lock()
            if let cached = cache[name] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            let match = lookup(name)
            lock.lock()
            cache[name] = match
            lock.unlock()
            return match
        }

        private static func lookup(_ name: String) -> AppMatch? {
            if let running = NSWorkspace.shared.runningApplications.first(where: {
                $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
            }) {
                return AppMatch(name: running.localizedName ?? name, bundleId: running.bundleIdentifier)
            }
            let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                           NSHomeDirectory() + "/Applications"]
            for folder in folders {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".app")
                if let bundle = Bundle(url: url) {
                    return AppMatch(name: name, bundleId: bundle.bundleIdentifier)
                }
            }
            return nil
        }
    }

    // MARK: - Closing the system banner

    /// Closes a banner the way its own close button would.
    @discardableResult
    static func dismiss(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        if AXUIElementCopyActionNames(element, &names) == .success, let actions = names as? [String] {
            // "Close" keeps the notification in Notification Center; "clear"
            // removes it, so it is only the last resort.
            let closeWords = ["close", "닫기", "dismiss", "clear", "지우기"]
            let ranked = closeWords.lazy.compactMap { word in
                actions.first { $0.lowercased().contains(word) }
            }
            if let action = ranked.first {
                return AXUIElementPerformAction(element, action as CFString) == .success
            }
        }
        for child in children(of: element) where string(child, "AXRole") == "AXButton" {
            let label = (string(child, "AXDescription") ?? string(child, "AXTitle") ?? "").lowercased()
            if label.contains("close") || label.contains("닫기") {
                return AXUIElementPerformAction(child, "AXPress" as CFString) == .success
            }
        }
        return false
    }

    // MARK: - Diagnostics

    /// Text dump of every Notification Center window, for fixing the reader
    /// when a macOS update changes the tree.
    static func dumpTree(pid: pid_t) -> String {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var out = ""
        for (index, window) in children(of: app, attribute: "AXWindows").enumerated() {
            out += "window[\(index)]\n"
            dump(window, depth: 1, into: &out)
        }
        return out.isEmpty ? "(no Notification Center windows)\n" : out
    }

    private static func dump(_ element: AXUIElement, depth: Int, into out: inout String) {
        guard depth < 18 else { return }
        var parts: [String] = [string(element, "AXRole") ?? "?"]
        for attribute in ["AXSubrole", "AXIdentifier", "AXTitle", "AXDescription", "AXValue", "AXHelp"] {
            if let value = string(element, attribute), !value.isEmpty {
                parts.append("\(attribute.dropFirst(2))=\(value.debugDescription)")
            }
        }
        if let size = size(of: element) {
            parts.append("size=\(Int(size.width))x\(Int(size.height))")
        }
        var names: CFArray?
        if AXUIElementCopyActionNames(element, &names) == .success, let actions = names as? [String], !actions.isEmpty {
            let short = actions.map { $0.replacingOccurrences(of: "\n", with: " ") }
            parts.append("actions=\(short)")
        }
        out += String(repeating: "  ", count: depth) + parts.joined(separator: " ") + "\n"
        for child in children(of: element) {
            dump(child, depth: depth + 1, into: &out)
        }
    }

    // MARK: - AX helpers

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    private static func size(of element: AXUIElement) -> CGSize? {
        guard let value = copy(element, "AXSize"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func children(of element: AXUIElement, attribute: String = "AXChildren") -> [AXUIElement] {
        guard let value = copy(element, attribute), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as? [AXUIElement]) ?? []
    }
}

/// Watches Notification Center for new banners and reports each one once.
///
/// Event driven through an AXObserver on the NotificationCenter process, with
/// a slow fallback poll in case a macOS version reuses banner windows without
/// posting "window created". Needs the Accessibility permission.
@MainActor
final class NotificationWatcher {
    var onNotification: ((IslandNotification) -> Void)?

    private(set) var isRunning = false
    private var dismissSystemBanner = false

    private let queue = DispatchQueue(label: "omni-island.notifications", qos: .userInitiated)
    private var observer: AXObserver?
    private var observedPid: pid_t = 0
    private var pollTimer: Timer?
    private var scanScheduled = false
    private var scanning = false
    private var primed = false
    /// Banner signature → last time it was on screen.
    private var seen: [String: Date] = [:]
    private var diagnosticsUntil: Date?

    static let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/OmniIsland", isDirectory: true)
        return dir.appendingPathComponent("notification-banners.log")
    }()

    func configure(enabled: Bool, dismissSystemBanner: Bool) {
        self.dismissSystemBanner = dismissSystemBanner
        if enabled { start() } else { stop() }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        primed = false
        attach()
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        detach()
        seen.removeAll()
    }

    /// For the next `seconds`, every scan appends the Notification Center tree
    /// to `logURL`. Returns the log location.
    @discardableResult
    func recordDiagnostics(seconds: TimeInterval = 60, context: [String] = []) -> URL {
        diagnosticsUntil = Date().addingTimeInterval(seconds)
        if !isRunning { start() }
        var lines = [
            "=== OmniIsland notification diagnostics \(Date()) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) ===",
            "accessibility: \(ModifierMonitor.isTrusted(prompt: false))",
            "notification center pid: \(NotificationBannerReader.process().map { String($0.processIdentifier) } ?? "not running")",
            "observer attached: \(observer != nil) (pid \(observedPid))",
        ]
        lines += context
        appendLog(lines.joined(separator: "\n") + "\n")
        scheduleScan(after: 0)
        return Self.logURL
    }

    /// Closes every banner on screen now. Used when the database reported
    /// a notification first, so its banner does not linger on the right.
    func dismissVisibleBanners() {
        guard isRunning, observedPid != 0 else { return }
        let pid = observedPid
        for delay in [0.15, 0.6] {
            queue.asyncAfter(deadline: .now() + delay) {
                let snapshot = NotificationBannerReader.snapshot(pid: pid)
                guard !snapshot.panelOpen, snapshot.items.count <= 3 else { return }
                for item in snapshot.items { NotificationBannerReader.dismiss(item.element) }
            }
        }
    }

    // MARK: - Observer

    private func attach() {
        guard ModifierMonitor.isTrusted(prompt: false),
              let process = NotificationBannerReader.process() else { return }
        let pid = process.processIdentifier
        guard pid != observedPid else { return }
        detach()

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<NotificationWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.axEvent() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification,
                     kAXLayoutChangedNotification] {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        observedPid = pid
        scheduleScan(after: 0)
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPid = 0
    }

    private func axEvent() {
        // Banners slide in; read once right away and once after the text settles.
        scheduleScan(after: 0.12)
        scheduleScan(after: 0.6)
    }

    private func poll() {
        // Re-attach when permission arrives late or Notification Center restarts.
        if let process = NotificationBannerReader.process(), process.processIdentifier != observedPid {
            attach()
        } else if observer == nil {
            attach()
        }
        guard observedPid != 0 else { return }
        let pid = observedPid
        queue.async { [weak self] in
            let count = NotificationBannerReader.windowCount(pid: pid)
            guard count > 0 else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.scheduleScan(after: 0) }
            }
        }
    }

    // MARK: - Scanning

    private func scheduleScan(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    private func scan() {
        guard isRunning, observedPid != 0 else { return }
        guard !scanning else {
            scanScheduled = true
            return
        }
        scanning = true
        let pid = observedPid
        let record = (diagnosticsUntil ?? .distantPast) > Date()
        queue.async { [weak self] in
            let snapshot = NotificationBannerReader.snapshot(pid: pid)
            let dump = record ? NotificationBannerReader.dumpTree(pid: pid) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.scanning = false
                    if let dump {
                        let parsed = snapshot.items.map { "  item [\($0.subrole ?? "-")] " + $0.texts.joined(separator: " | ") }
                        self.appendLog("--- scan \(Date()) windows=\(snapshot.windowCount) items=\(snapshot.items.count) panelOpen=\(snapshot.panelOpen)\n"
                                       + parsed.map { $0 + "\n" }.joined() + dump)
                    }
                    self.handle(snapshot)
                    if self.scanScheduled {
                        self.scanScheduled = false
                        self.scheduleScan(after: 0.05)
                    }
                }
            }
        }
    }

    private func handle(_ snapshot: NotificationBannerReader.Snapshot) {
        let now = Date()
        // Forget banners shortly after they leave the screen, so an identical
        // notification later on counts as new again.
        seen = seen.filter { now.timeIntervalSince($0.value) < 15 }
        let fresh = snapshot.items.filter { seen[$0.signature] == nil && !$0.texts.isEmpty }
        for item in snapshot.items { seen[item.signature] = now }

        // The first scan only learns what is already on screen, and an open
        // history panel or a burst of many items is old notifications, not new.
        guard primed else {
            primed = true
            return
        }
        if !fresh.isEmpty {
            Log.info("notification banners: \(fresh.count) new of \(snapshot.items.count), windows \(snapshot.windowCount), panelOpen \(snapshot.panelOpen)")
        }
        guard !snapshot.panelOpen, fresh.count <= 3 else { return }

        for item in fresh {
            let notification = NotificationBannerReader.notification(from: item)
            onNotification?(notification)
            if dismissSystemBanner {
                let element = item.element
                queue.async { NotificationBannerReader.dismiss(element) }
            }
        }
    }

    private func appendLog(_ text: String) {
        let url = Self.logURL
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = text.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Sends a test banner through `osascript` so the reader can be checked.
    static func sendTestNotification() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", #"display notification "아일랜드에서 이 알림이 보이면 판독이 동작합니다." with title "OmniIsland 테스트" subtitle "알림 판독 확인""#]
        try? process.run()
    }
}
