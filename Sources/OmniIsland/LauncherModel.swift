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
        case currency(CurrencyAnswer?)
        case file(FileHit)
        case pane(SettingsPane)
        case islandSettings
        /// A web address or search: what to open, and an SF Symbol.
        case web(URL, symbol: String)
        /// Something copied earlier, from the clipboard manager.
        case shelf(ShelfItem)
        /// A built-in app to enter (its id).
        case plugin(String)
        /// A saved link, with the text that fills its `{query}` (nil when
        /// the trigger hasn't been typed yet).
        case quickLink(QuickLink, argument: String?)
    }

    /// Where a row goes at the top level: answers first, the web last.
    enum Group: Equatable { case answer, local, web }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    /// Character offsets of `title` the query matched.
    let hits: [Int]
    var score: Int
    /// Heading drawn above the first row of a group ("최근에 연 앱").
    var section: String? = nil
    var group: Group = .local
    /// The plugin that made the row and runs it.
    var plugin: String = ""

    var kindLabel: String {
        switch kind {
        case .app: return "앱"
        case .window: return "창"
        case .calculation: return "계산기"
        case .currency: return "환율"
        case .file(let f): return f.isDirectory ? "폴더" : "파일"
        case .pane: return "시스템 설정"
        case .islandSettings: return "OmniIsland"
        case .web: return "웹"
        case .shelf: return "클립보드"
        case .plugin: return "내장 앱"
        case .quickLink: return "링크"
        }
    }
}

/// Query, results and selection of the launcher (the island's search mode).
/// The rows come from built-in plugins (LauncherPlugins.swift).
@MainActor
final class LauncherModel: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var results: [LauncherItem] = []
    @Published var selection = 0
    /// Bumped when the text field should take the query from the model
    /// (Esc cleared it, Tab completed it, a prefix switched the mode).
    @Published private(set) var querySerial = 0
    /// The plugin the launcher is inside ("c " → clipboard manager), or nil
    /// at the top level.
    @Published private(set) var modeId: String?
    /// Rows picked for one action, in the order they were picked.
    @Published private(set) var marked: [LauncherItem] = []

    let apps = AppIndex()
    /// What was picked after typing what; lifts those rows next time.
    lazy var picks = LauncherPicks(seed: { self.apps.pickSeed() })
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
    var onOpenSettings: (() -> Void)?
    /// Clipboard history, newest first.
    var shelfProvider: (() -> [ShelfItem])?
    var onCopyShelf: (([ShelfItem]) -> Void)?
    var onPasteShelf: (([ShelfItem]) -> Void)?
    var onRemoveShelf: ((ShelfItem) -> Void)?
    var shelfDragProvider: ((ShelfItem) -> NSItemProvider)?

    private(set) var plugins: [LauncherPlugin] = []
    private var web: WebPlugin?

    // Answers that arrive later, each for the query it was asked with.
    private var epoch = 0
    private var asyncWork: DispatchWorkItem?

    init() {
        let web = WebPlugin(host: self)
        self.web = web
        // Order matters at the top level: answers in this order, the web last.
        plugins = [
            CalculatorPlugin(host: self), CurrencyPlugin(host: self), AppsPlugin(host: self),
            WindowsPlugin(host: self), SettingsPlugin(host: self), FilesPlugin(host: self),
            ClipboardPlugin(host: self), QuickLinksPlugin(host: self), web,
        ]
        apps.onUpdate = { [weak self] in self?.refresh() }
    }

    // MARK: - Plugins and modes

    var mode: LauncherPlugin? { modeId.flatMap(plugin(id:)) }

    func plugin(id: String) -> LauncherPlugin? { plugins.first { $0.id == id } }

    /// The trigger prefix of a plugin, "" when it has none.
    func prefix(of plugin: LauncherPlugin) -> String {
        guard plugin.hasMode else { return "" }
        return (config.prefixes[plugin.id] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Plugins that can be entered with a prefix, in plugin order.
    var prefixed: [(plugin: LauncherPlugin, prefix: String)] {
        plugins.compactMap { p -> (plugin: LauncherPlugin, prefix: String)? in
            let x = prefix(of: p)
            return x.isEmpty ? nil : (p, x)
        }
    }

    /// The same keys typed with the Korean (2-set) layout, so "ㅊ " works
    /// like "c " without switching input sources.
    private static let hangulKeys: [Character: Character] = [
        "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ", "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ",
        "p": "ㅔ", "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ", "h": "ㅗ", "j": "ㅓ", "k": "ㅏ",
        "l": "ㅣ", "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ", "b": "ㅠ", "n": "ㅜ", "m": "ㅡ",
    ]

    /// A prefix as typed: itself, and its Korean-layout twin for one letter.
    static func forms(of prefix: String) -> [String] {
        guard prefix.count == 1, let c = prefix.first, let twin = hangulKeys[c] else { return [prefix] }
        return [prefix, String(twin)]
    }

    /// "c foo" at the top level → the clipboard manager, searching "foo".
    private func modeTrigger(_ text: String) -> (LauncherPlugin, String)? {
        guard modeId == nil else { return nil }
        let lower = text.lowercased()
        for (plugin, prefix) in prefixed {
            for form in Self.forms(of: prefix) where lower.hasPrefix(form + " ") {
                return (plugin, String(text.dropFirst(form.count + 1)))
            }
        }
        return nil
    }

    func enter(_ plugin: LauncherPlugin, query text: String = "") {
        guard plugin.hasMode else { return }
        modeId = plugin.id
        marked = []
        query = text
        selection = 0
        querySerial &+= 1
        refresh()
        scheduleAsync()
    }

    /// ⌫ on an empty field, or Esc: back to the top level.
    func leaveMode() -> Bool {
        guard modeId != nil else { return false }
        modeId = nil
        marked = []
        query = ""
        selection = 0
        querySerial &+= 1
        refresh()
        return true
    }

    /// Placeholder of the search field.
    var placeholder: String {
        if let mode { return mode.placeholder }
        let keys = prefixed.map { $0.prefix }
        guard !keys.isEmpty else { return "앱, 창, 파일, 설정을 검색하거나 웹에서 찾습니다" }
        return "검색하거나 \(keys.joined(separator: "·")) 다음에 스페이스로 내장 앱을 엽니다"
    }

    // MARK: - Lifecycle

    func begin() {
        apps.refreshIfStale()
        plugins.forEach { $0.reset() }
        modeId = nil
        marked = []
        query = ""
        selection = 0
        querySerial &+= 1
        refresh()
    }

    func setQuery(_ text: String) {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        guard cleaned != query else { return }
        if let trigger = modeTrigger(cleaned) {
            enter(trigger.0, query: trigger.1)
            return
        }
        query = cleaned
        selection = 0
        refresh()
        scheduleAsync()
    }

    /// Esc: drops the picked rows, then the query, then leaves the mode,
    /// then closes.
    func cancel() {
        if !marked.isEmpty {
            marked = []
        } else if !query.isEmpty {
            query = ""
            selection = 0
            querySerial &+= 1
            refresh()
        } else if !leaveMode() {
            onClose?()
        }
    }

    /// Tab: enters a plugin's row, picks a row inside a multi-select mode,
    /// or completes the query.
    func tab() -> Bool {
        if results.indices.contains(selection), case .plugin(let id) = results[selection].kind,
           let target = plugin(id: id) {
            enter(target)
            return true
        }
        if results.indices.contains(selection), fillQuickLink(results[selection]) { return true }
        if allowsMarking {
            toggleMark(advance: true)
            return true
        }
        return complete()
    }

    /// →: takes the top result's name (or Google's first completion) when
    /// it starts with the query.
    func complete() -> Bool {
        guard !query.isEmpty, modeId == nil else { return false }
        let lower = query.lowercased()
        let candidates = results.prefix(1).filter { $0.group != .answer }.map(\.title)
            + (web?.completions(for: trimmedQuery).prefix(1) ?? [])
        guard let pick = candidates.first(where: { $0.lowercased().hasPrefix(lower) && $0.count > query.count })
        else { return false }
        query = pick
        querySerial &+= 1
        refresh()
        scheduleAsync()
        return true
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    // MARK: - Picking several rows

    var allowsMarking: Bool { mode?.multiSelect == true }

    func isMarked(_ item: LauncherItem) -> Bool { marked.contains { $0.id == item.id } }

    func toggleMark(index: Int? = nil, advance: Bool = false) {
        guard allowsMarking else { return }
        let i = index ?? selection
        guard results.indices.contains(i) else { return }
        let item = results[i]
        if let k = marked.firstIndex(where: { $0.id == item.id }) {
            marked.remove(at: k)
        } else {
            marked.append(item)
        }
        if advance && i + 1 < results.count { selection = i + 1 }
    }

    /// ⇧↑ ⇧↓: picks the selected row and the next one.
    func extend(_ delta: Int) -> Bool {
        guard allowsMarking, results.indices.contains(selection) else { return false }
        mark(selection)
        let next = selection + delta
        guard results.indices.contains(next) else { return true }
        selection = next
        mark(next)
        return true
    }

    /// ⌘A on an empty query: picks every row.
    func markAll() -> Bool {
        guard allowsMarking, query.isEmpty, !results.isEmpty else { return false }
        marked = results
        return true
    }

    private func mark(_ index: Int) {
        if !isMarked(results[index]) { marked.append(results[index]) }
    }

    // MARK: - Running rows

    /// Return (or a click): runs a row, or the picked rows. `alternate` is ⌘Return.
    func activate(index: Int? = nil, alternate: Bool = false) {
        let items: [LauncherItem]
        if index == nil && !marked.isEmpty {
            items = marked
        } else {
            let i = index ?? selection
            guard results.indices.contains(i) else { return }
            items = [results[i]]
        }
        guard let first = items.first else { return }
        if case .plugin(let id) = first.kind {
            if let target = plugin(id: id) { enter(target) }
            return
        }
        if fillQuickLink(first) { return }
        guard let target = plugin(id: first.plugin), target.canActivate(first) else { return }
        if config.learnFromPicks {
            for item in items where item.group == .local { picks.record(item.id, query: trimmedQuery) }
        }
        onClose?()
        target.activate(items, alternate: alternate)
    }

    /// A link that asks for text and has none: types its keyword (or name)
    /// and a space, so what comes next fills its `{query}`.
    private func fillQuickLink(_ item: LauncherItem) -> Bool {
        guard case .quickLink(let link, let argument) = item.kind, link.needsInput,
              (argument ?? "").isEmpty else { return false }
        let text = QuickLinksPlugin.trigger(of: link) + " "
        guard query != text else { return true }
        query = text
        selection = 0
        querySerial &+= 1
        refresh()
        scheduleAsync()
        return true
    }

    /// ⌘⌫: removes the selected row where its plugin allows it.
    func removeSelected() -> Bool {
        guard results.indices.contains(selection) else { return false }
        let item = results[selection]
        guard let target = plugin(id: item.plugin), target.remove(item) else { return false }
        marked.removeAll { $0.id == item.id }
        refresh()
        return true
    }

    func dragProvider(_ item: LauncherItem) -> NSItemProvider? {
        plugin(id: item.plugin)?.dragProvider(item)
    }

    // MARK: - Answers that arrive later

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private func scheduleAsync() {
        asyncWork?.cancel()
        epoch &+= 1
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        let asked = epoch
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.ask(q, epoch: asked) }
        }
        asyncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func ask(_ q: String, epoch asked: Int) {
        guard asked == epoch else { return }
        let inMode = mode != nil
        let targets = mode.map { [$0] } ?? plugins.filter { $0.inRoot }
        for plugin in targets {
            plugin.fetch(q, inMode: inMode,
                         isCurrent: { [weak self] in self?.epoch == asked },
                         done: { [weak self] in self?.refresh() })
        }
    }

    // MARK: - Searching

    func refresh() {
        let selectedId = results.indices.contains(selection) ? results[selection].id : nil
        results = search(trimmedQuery)
        if let selectedId, selection != 0, let kept = results.firstIndex(where: { $0.id == selectedId }) {
            selection = kept
        } else if selection >= results.count {
            selection = 0
        }
        onLayoutChange?()
    }

    private func search(_ q: String) -> [LauncherItem] {
        if let mode { return Array(mode.search(q, inMode: true).prefix(300)) }

        let roots = plugins.filter { $0.inRoot }
        let limit = max(3, Int(config.maxResults))
        if q.isEmpty {
            return Array(roots.flatMap { $0.search("", inMode: false) }.prefix(limit))
        }

        var answers: [LauncherItem] = []
        var items: [LauncherItem] = []
        var web: [LauncherItem] = []
        for plugin in roots {
            for item in plugin.search(q, inMode: false) {
                switch item.group {
                case .answer: answers.append(item)
                case .local: items.append(item)
                case .web: web.append(item)
                }
            }
        }
        let entries = pluginRows(q)
        items += entries.matched
        // Rows picked before, above all after typing this same query, rise.
        if config.learnFromPicks {
            for i in items.indices { items[i].score += picks.boost(items[i].id, query: q) }
        }
        items.sort { a, b in
            a.score != b.score ? a.score > b.score
                : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        // Typing exactly a prefix ("c") puts the plugin right under the top
        // match, so Return still opens what was being looked for.
        for entry in entries.exact.reversed() { items.insert(entry, at: min(1, items.count)) }

        // Answers and local rows first; the web keeps at least its first row
        // (a search for what is typed) so Return always does something.
        let reservedForWeb = min(web.count, max(1, limit - answers.count - items.count))
        let localRoom = max(0, limit - answers.count - reservedForWeb)
        var list = answers + items.prefix(localRoom)
        list += web.prefix(max(0, limit - list.count))
        return list
    }

    /// Rows that enter a plugin: for its prefix typed alone, or its name.
    private func pluginRows(_ q: String) -> (exact: [LauncherItem], matched: [LauncherItem]) {
        var exact: [LauncherItem] = []
        var matched: [LauncherItem] = []
        let lower = q.lowercased()
        for plugin in plugins where plugin.hasMode {
            let trigger = prefix(of: plugin)
            let subtitle = trigger.isEmpty ? "Return을 누르면 이 내장 앱으로 들어갑니다"
                : "\(trigger) 다음에 스페이스를 눌러도 바로 들어갑니다"
            func entry(score: Int, hits: [Int] = []) -> LauncherItem {
                LauncherItem(id: "plugin:" + plugin.id, kind: .plugin(plugin.id), title: plugin.name,
                             subtitle: subtitle, hits: hits, score: score, plugin: plugin.id)
            }
            if !trigger.isEmpty && Self.forms(of: trigger).contains(lower) {
                exact.append(entry(score: 0))
                continue
            }
            guard q.count >= 2 else { continue }
            let names = [plugin.name] + plugin.keywords
            var best: (Int, FuzzyMatch)?
            for (n, name) in names.enumerated() {
                guard let m = FuzzyMatcher.match(q, FuzzyMatcher.Candidate(name)), m.score >= 700 else { continue }
                if m.score > (best?.1.score ?? -1) { best = (n, m) }
            }
            if let best {
                matched.append(entry(score: best.1.score - 50, hits: best.0 == 0 ? best.1.hits : []))
            }
        }
        return (exact, matched)
    }

    // MARK: - Layout

    static let fieldHeight: CGFloat = 40
    static let rowHeight: CGFloat = 40
    static let headerHeight: CGFloat = 22
    static let messageHeight: CGFloat = 34
    static let verticalPadding: CGFloat = 14

    /// Number of section headings drawn above the rows.
    var sectionCount: Int {
        var count = 0
        var last: String?
        for item in results where item.section != last {
            last = item.section
            if item.section != nil { count += 1 }
        }
        return count
    }

    /// Rows shown before the list scrolls.
    var visibleRows: Int { max(3, Int(config.maxResults)) }

    private var maximumListHeight: CGFloat {
        CGFloat(visibleRows) * Self.rowHeight + 2 * Self.headerHeight
    }

    /// Height of the launcher part below the workspace row.
    var bodyHeight: CGFloat {
        var height = Self.fieldHeight + Self.verticalPadding
        if results.isEmpty && !query.isEmpty {
            height += Self.messageHeight
        } else {
            let list = CGFloat(sectionCount) * Self.headerHeight + CGFloat(results.count) * Self.rowHeight
            height += min(list, maximumListHeight)
        }
        return height
    }

    /// Tallest the launcher can get, for sizing the panel.
    var maximumBodyHeight: CGFloat {
        Self.fieldHeight + Self.verticalPadding + maximumListHeight
    }
}
