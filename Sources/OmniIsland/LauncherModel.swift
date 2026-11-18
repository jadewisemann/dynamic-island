import AppKit
import SwiftUI

/// An OmniWM window offered by the launcher.
struct LauncherWindow: Equatable {
    let id: String
    let appName: String
    let bundleId: String?
    let title: String
    let workspaceLabel: String
}

/// One row of launcher results.
struct LauncherItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case app(AppEntry)
        case window(LauncherWindow)
        case calculation(Double)
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    /// Character offsets of `title` the query matched.
    let hits: [Int]
    let score: Int

    var kindLabel: String {
        switch kind {
        case .app: return "앱"
        case .window: return "창"
        case .calculation: return "계산기"
        }
    }
}

/// Query, results and selection of the launcher (the island's search mode).
@MainActor
final class LauncherModel: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var results: [LauncherItem] = []
    @Published var selection = 0
    /// Bumped when the text field should take the query from the model
    /// (Esc cleared it, Tab completed it).
    @Published private(set) var querySerial = 0

    let apps = AppIndex()
    var config = IslandConfig.Launcher()
    /// Open windows from OmniWM, in workspace order.
    var windowsProvider: (() -> [LauncherWindow])?
    /// The result list changed size; the island resizes with it.
    var onLayoutChange: (() -> Void)?
    /// Asks the island to close.
    var onClose: (() -> Void)?
    var onOpenApp: ((AppEntry) -> Void)?
    var onRevealApp: ((AppEntry) -> Void)?
    var onFocusWindow: ((LauncherWindow) -> Void)?
    var onSummonWindow: ((LauncherWindow) -> Void)?

    init() {
        apps.onUpdate = { [weak self] in self?.refresh() }
    }

    var isShowingRecent: Bool { query.isEmpty && !results.isEmpty }

    // MARK: - Lifecycle

    func begin() {
        apps.refreshIfStale()
        query = ""
        selection = 0
        querySerial &+= 1
        refresh()
    }

    func setQuery(_ text: String) {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        guard cleaned != query else { return }
        query = cleaned
        selection = 0
        refresh()
    }

    /// Esc: clears the query first, closes on an empty one.
    func cancel() {
        if query.isEmpty {
            onClose?()
        } else {
            query = ""
            selection = 0
            querySerial &+= 1
            refresh()
        }
    }

    /// Tab / →: takes the top result's name when it starts with the query.
    func complete() -> Bool {
        guard let first = results.first, !query.isEmpty,
              first.title.lowercased().hasPrefix(query.lowercased()), first.title.count > query.count
        else { return false }
        query = first.title
        querySerial &+= 1
        refresh()
        return true
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    /// Return (or a click): runs a row. `alternate` is ⌘Return.
    func activate(index: Int? = nil, alternate: Bool = false) {
        let i = index ?? selection
        guard results.indices.contains(i) else { return }
        let item = results[i]
        onClose?()
        switch item.kind {
        case .app(let app):
            if alternate {
                onRevealApp?(app)
            } else {
                apps.recordLaunch(app)
                onOpenApp?(app)
            }
        case .window(let window):
            if alternate { onSummonWindow?(window) } else { onFocusWindow?(window) }
        case .calculation(let value):
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(Calculator.plain(value), forType: .string)
        }
    }

    // MARK: - Searching

    private func refresh() {
        results = search(query)
        if selection >= results.count { selection = 0 }
        onLayoutChange?()
    }

    private func search(_ text: String) -> [LauncherItem] {
        let limit = max(1, Int(config.maxResults))
        let q = text.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            guard config.showRecent else { return [] }
            return apps.recentApps(limit: min(Int(config.recentCount), limit)).map { app in
                LauncherItem(id: "app:" + app.path, kind: .app(app), title: app.displayName,
                             subtitle: nil, hits: [], score: 0)
            }
        }

        var items: [LauncherItem] = []
        if config.calculator, let value = Calculator.evaluate(q) {
            items.append(LauncherItem(id: "calc", kind: .calculation(value), title: "= " + Calculator.format(value),
                                      subtitle: "Return를 누르면 결과를 복사합니다", hits: [], score: 2000))
        }

        if config.searchApps {
            for app in apps.apps {
                guard let names = apps.candidates[app.path] else { continue }
                var best: FuzzyMatch?
                var bestIsDisplay = true
                for (n, name) in names.enumerated() {
                    if let m = FuzzyMatcher.match(q, name), m.score > (best?.score ?? -1) {
                        best = m
                        bestIsDisplay = n == 0
                    }
                }
                guard let best else { continue }
                let boost = min(apps.launchCount(app), 20) * 8
                let subtitle = app.fileName != app.displayName ? app.fileName : nil
                items.append(LauncherItem(id: "app:" + app.path, kind: .app(app), title: app.displayName,
                                          subtitle: subtitle, hits: bestIsDisplay ? best.hits : [],
                                          score: best.score + boost))
            }
        }

        if config.searchWindows, let windows = windowsProvider?() {
            for window in windows {
                let appMatch = FuzzyMatcher.match(q, FuzzyMatcher.Candidate(window.appName))
                let titleMatch = window.title.isEmpty ? nil : FuzzyMatcher.match(q, FuzzyMatcher.Candidate(window.title))
                let score = max(appMatch?.score ?? -1, titleMatch?.score ?? -1)
                guard score >= 0 else { continue }
                let title = window.title.isEmpty ? window.appName : window.title
                let hits = window.title.isEmpty ? (appMatch?.hits ?? []) : (titleMatch?.hits ?? [])
                items.append(LauncherItem(
                    id: "window:" + window.id, kind: .window(window), title: title,
                    subtitle: "\(window.appName) · 워크스페이스 \(window.workspaceLabel)",
                    hits: hits, score: score - 40))
            }
        }

        items.sort { a, b in
            a.score != b.score ? a.score > b.score
                : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        return Array(items.prefix(limit))
    }

    // MARK: - Layout

    static let fieldHeight: CGFloat = 40
    static let rowHeight: CGFloat = 40
    static let headerHeight: CGFloat = 22
    static let messageHeight: CGFloat = 34
    static let verticalPadding: CGFloat = 14

    /// Height of the launcher part below the workspace row.
    var bodyHeight: CGFloat {
        var height = Self.fieldHeight + Self.verticalPadding
        if isShowingRecent { height += Self.headerHeight }
        if results.isEmpty && !query.isEmpty {
            height += Self.messageHeight
        } else {
            height += CGFloat(results.count) * Self.rowHeight
        }
        return height
    }

    /// Tallest the launcher can get, for sizing the panel.
    var maximumBodyHeight: CGFloat {
        Self.fieldHeight + Self.verticalPadding + Self.headerHeight
            + CGFloat(max(1, Int(config.maxResults))) * Self.rowHeight
    }
}
