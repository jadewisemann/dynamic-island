import AppKit
import ApplicationServices

/// Reads the red notification badges ("3", "•", …) that apps show on their
/// Dock icons. The Dock exposes them through Accessibility as the
/// `AXStatusLabel` of each application tile, so this needs the same
/// Accessibility permission the modifier monitor asks for.
enum DockBadgeReader {
    /// bundle id (lower-cased) → badge label, for every badged Dock tile.
    static func readAll() -> [String: String] {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [:] }

        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)

        var labels: [String: String] = [:]
        for list in children(of: root) where string(list, "AXRole") == "AXList" {
            for tile in children(of: list) {
                guard string(tile, "AXSubrole") == "AXApplicationDockItem",
                      let label = string(tile, "AXStatusLabel"), !label.isEmpty,
                      let bundleId = bundleId(of: tile)
                else { continue }
                labels[bundleId] = label
            }
        }
        return labels
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var bundleIdByURL: [URL: String] = [:]

    private static func bundleId(of tile: AXUIElement) -> String? {
        guard let value = copy(tile, "AXURL") else { return nil }
        let url: URL?
        if CFGetTypeID(value) == CFURLGetTypeID() {
            url = (value as! CFURL) as URL
        } else {
            url = (value as? String).flatMap(URL.init(string:))
        }
        guard let url else { return nil }
        cacheLock.lock()
        let cached = bundleIdByURL[url]
        cacheLock.unlock()
        if let cached { return cached }
        guard let id = Bundle(url: url)?.bundleIdentifier?.lowercased() else { return nil }
        cacheLock.lock()
        bundleIdByURL[url] = id
        cacheLock.unlock()
        return id
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = copy(element, "AXChildren"),
              CFGetTypeID(value) == CFArrayGetTypeID()
        else { return [] }
        return (value as? [AXUIElement]) ?? []
    }
}

/// Polls the Dock on a background queue and reports badge changes on the
/// main actor. Polling runs only while it is enabled and permission exists.
@MainActor
final class DockBadgeMonitor {
    var onChange: (([String: String]) -> Void)?
    private(set) var labels: [String: String] = [:]

    private let queue = DispatchQueue(label: "omni-island.dock-badges", qos: .utility)
    private var timer: Timer?
    private var interval: TimeInterval = 3
    private var enabled = false
    private var reading = false

    func configure(enabled: Bool, intervalMs: Double) {
        let newInterval = max(intervalMs, 500) / 1000
        guard enabled != self.enabled || newInterval != interval || (enabled && timer == nil) else { return }
        self.enabled = enabled
        interval = newInterval
        timer?.invalidate()
        timer = nil
        guard enabled else {
            publish([:])
            return
        }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    /// Reads now (e.g. right when the island is about to appear).
    func refresh() {
        guard enabled, !reading, ModifierMonitor.isTrusted(prompt: false) else { return }
        reading = true
        queue.async { [weak self] in
            let result = DockBadgeReader.readAll()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reading = false
                    self.publish(result)
                }
            }
        }
    }

    private func publish(_ result: [String: String]) {
        guard result != labels else { return }
        labels = result
        onChange?(result)
    }
}
