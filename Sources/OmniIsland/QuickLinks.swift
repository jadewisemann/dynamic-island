import AppKit

/// A saved link the launcher finds by name or keyword, like Raycast's Quick
/// Links. `link` is a web address, a URL with any scheme (obsidian://,
/// mailto:), or a file or folder path. `{query}` in it is replaced with what
/// is typed after the keyword or name ("gh owner/repo").
struct QuickLink: Equatable {
    var name = ""
    var link = ""
    /// Short trigger ("gh"). Typing it alone lists the link first; typing it,
    /// a space and some text fills in `{query}`.
    var keyword = ""
    /// App to open the link with: a name ("Safari"), a bundle id, or a path.
    /// Empty uses the default app.
    var app = ""

    static let placeholder = "{query}"

    static let examples = [
        QuickLink(name: "GitHub 저장소", link: "https://github.com/{query}", keyword: "gh"),
        QuickLink(name: "YouTube 검색", link: "https://www.youtube.com/results?search_query={query}", keyword: "yt"),
        QuickLink(name: "다운로드 폴더", link: "~/Downloads", keyword: "dl"),
    ]

    var isValid: Bool { !name.isEmpty && !link.isEmpty }

    /// The link asks for text: it has a `{query}` placeholder.
    var needsInput: Bool { link.range(of: Self.placeholder, options: .caseInsensitive) != nil }

    var isFile: Bool {
        let t = link.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("/") || t.hasPrefix("~") || t.lowercased().hasPrefix("file://")
    }

    /// Characters left as they are in a filled-in web address. "/" stays so
    /// "github.com/{query}" takes "owner/repo"; "&", "=", "?", "#" and "+"
    /// are escaped so the text can't break the query string.
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~/:@!$'()*,;")
        return set
    }()

    /// The address to open, with `{query}` replaced by `argument`.
    func url(argument: String? = nil) -> URL? {
        let template = link.trimmingCharacters(in: .whitespaces)
        guard !template.isEmpty else { return nil }
        let arg = (argument ?? "").trimmingCharacters(in: .whitespaces)
        if isFile {
            let text = Self.fill(template, with: arg)
            if text.lowercased().hasPrefix("file://") { return URL(string: text) }
            return URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        }
        let encoded = arg.addingPercentEncoding(withAllowedCharacters: Self.allowed) ?? arg
        var text = Self.fill(template, with: encoded)
        if !Self.hasScheme(text) {
            text = (text.lowercased().hasPrefix("localhost") || text.hasPrefix("127.") ? "http://" : "https://") + text
        }
        return URL(string: text)
    }

    private static func fill(_ template: String, with value: String) -> String {
        template.replacingOccurrences(of: placeholder, with: value, options: .caseInsensitive)
    }

    /// "https://…", "obsidian://…", "mailto:…" have one; "github.com/x" and
    /// "localhost:3000" don't.
    private static func hasScheme(_ text: String) -> Bool {
        if text.contains("://") { return true }
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.first, first.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }),
              !scheme.contains(".") else { return false }
        let rest = text[text.index(after: colon)...]
        return !(rest.first?.isNumber ?? false)
    }

    /// The app chosen in `app`, if it can be found.
    var appURL: URL? {
        let t = app.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let fm = FileManager.default
        if t.hasPrefix("/") || t.hasPrefix("~") {
            let path = (t as NSString).expandingTildeInPath
            return fm.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if t.contains("."), !t.lowercased().hasSuffix(".app"),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: t) {
            return url
        }
        let file = t.lowercased().hasSuffix(".app") ? t : t + ".app"
        let home = fm.homeDirectoryForCurrentUser.path
        for folder in ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       "/Applications/Utilities", home + "/Applications"] {
            let path = folder + "/" + file
            if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// The app that will open the link, for its icon.
    var handlerPath: String? {
        if let appURL { return appURL.path }
        if isFile, let url = url(argument: needsInput ? "" : nil), url.isFileURL {
            let path = url.path
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
        guard let url = url(argument: "x") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)?.path
    }

    func open(argument: String? = nil) {
        guard let url = url(argument: argument) else { return }
        if let appURL {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Plugin

/// Quick Links in the launcher. A link is found by its name or keyword;
/// "gh owner/repo" fills `{query}` of the link whose keyword is "gh". Return
/// on a link that asks for text and has none puts "gh " in the field.
@MainActor
final class QuickLinksPlugin: LauncherPlugin {
    unowned let host: LauncherModel
    init(host: LauncherModel) { self.host = host }

    let id = "quicklinks"
    let name = "Quick Links"
    let symbol = "link"
    let keywords = ["quicklinks", "quick links", "links", "bookmarks", "링크", "바로가기", "북마크"]
    let hasMode = true
    let placeholder = "저장한 링크를 이름이나 키워드로 찾습니다 · ⌘Return은 주소 복사"
    var inRoot: Bool { host.config.searchQuickLinks }

    private var links: [QuickLink] { host.config.quickLinks.filter(\.isValid) }

    /// What to type before the text a link asks for: its keyword, or its name.
    static func trigger(of link: QuickLink) -> String {
        link.keyword.isEmpty ? link.name : link.keyword
    }

    private func key(_ index: Int, _ link: QuickLink) -> String { "\(index):\(link.name)" }

    private func subtitle(_ link: QuickLink, argument: String?) -> String {
        if link.needsInput && (argument ?? "").isEmpty {
            return argument == nil ? "\(Self.trigger(of: link)) 다음에 스페이스를 누르고 입력합니다"
                : "열 내용을 입력합니다 (링크의 {query} 자리에 들어갑니다)"
        }
        let address = link.url(argument: argument).map { url in
            url.isFileURL ? (url.path as NSString).abbreviatingWithTildeInPath : url.absoluteString
        } ?? link.link
        return link.keyword.isEmpty ? address : "\(link.keyword) · \(address)"
    }

    private func linkRow(_ index: Int, _ link: QuickLink, argument: String? = nil, hits: [Int] = [],
                         score: Int = 0, section: String? = nil, group: LauncherItem.Group = .local) -> LauncherItem {
        let filled = argument.map { !$0.isEmpty } ?? false
        return row(key(index, link) + (filled ? ":arg" : ""), .quickLink(link, argument: argument),
                   title: filled ? "\(link.name): \(argument ?? "")" : link.name,
                   subtitle: subtitle(link, argument: argument),
                   hits: hits, score: score, section: section, group: group)
    }

    func search(_ query: String, inMode: Bool) -> [LauncherItem] {
        let saved = links
        guard !saved.isEmpty else { return [] }
        if query.isEmpty {
            guard inMode else { return [] }
            return saved.enumerated().map { i, link in linkRow(i, link) }
        }
        let lower = query.lowercased()

        // "gh owner/repo": the text after a keyword (or a name) fills {query}.
        // The field as typed, so "gh " with its space already counts.
        let typed = String(host.query.drop(while: \.isWhitespace))
        let typedLower = typed.lowercased()
        var filled: [LauncherItem] = []
        for (i, link) in saved.enumerated() where link.needsInput {
            let triggers = [link.keyword, link.name].filter { !$0.isEmpty }.map { $0.lowercased() }
            guard let t = triggers.first(where: { typedLower.hasPrefix($0 + " ") }) else { continue }
            let argument = String(typed.dropFirst(t.count + 1)).trimmingCharacters(in: .whitespaces)
            filled.append(linkRow(i, link, argument: argument, score: 10_000, group: .answer))
        }
        if !filled.isEmpty { return filled }

        var items: [LauncherItem] = []
        for (i, link) in saved.enumerated() {
            if !link.keyword.isEmpty && link.keyword.lowercased() == lower {
                // The keyword typed exactly beats any fuzzy match.
                items.append(linkRow(i, link, score: 5_000))
                continue
            }
            let nameMatch = FuzzyMatcher.match(query, FuzzyMatcher.Candidate(link.name))
            let keywordMatch = link.keyword.isEmpty ? nil
                : FuzzyMatcher.match(query, FuzzyMatcher.Candidate(link.keyword))
            let score = max(nameMatch?.score ?? -1, keywordMatch?.score ?? -1)
            guard score >= (inMode ? 0 : 300) else { continue }
            items.append(linkRow(i, link, hits: nameMatch?.hits ?? [], score: inMode ? score : score - 30))
        }
        return inMode ? ranked(items) : items
    }

    func activate(_ items: [LauncherItem], alternate: Bool) {
        guard case .quickLink(let link, let argument)? = items.first?.kind else { return }
        if alternate {
            guard let url = link.url(argument: argument) else { return }
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(url.isFileURL ? url.path : url.absoluteString, forType: .string)
        } else {
            link.open(argument: argument)
        }
    }
}
