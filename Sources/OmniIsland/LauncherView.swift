import AppKit
import SwiftUI

/// Search field and result rows shown under the workspace row while the
/// launcher is open.
struct LauncherView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var launcher: LauncherModel

    private var palette: IslandPalette { model.palette }

    var body: some View {
        VStack(spacing: 0) {
            field
                .frame(height: LauncherModel.fieldHeight)
                .padding(.top, 4)
            if launcher.results.isEmpty && !launcher.query.isEmpty {
                Text("결과가 없습니다")
                    .font(model.textFont(size: 13, weight: .regular))
                    .foregroundStyle(palette.secondary)
                    .frame(height: LauncherModel.messageHeight)
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(launcher.results.enumerated()), id: \.element.id) { index, item in
                            if let section = item.section,
                               index == 0 || launcher.results[index - 1].section != section {
                                Text(section)
                                    .font(model.textFont(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .frame(height: LauncherModel.headerHeight)
                            }
                            row(item, index: index)
                                .id(item.id)
                        }
                    }
                }
                .onChange(of: launcher.selection) { _, selected in
                    guard launcher.results.indices.contains(selected) else { return }
                    proxy.scrollTo(launcher.results[selected].id)
                }
                .onChange(of: launcher.modeId) { _, _ in
                    if let first = launcher.results.first { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    @ViewBuilder private func row(_ item: LauncherItem, index: Int) -> some View {
        let base = LauncherRow(model: model, item: item, index: index, selected: index == launcher.selection,
                               marked: launcher.isMarked(item))
            .frame(height: LauncherModel.rowHeight)
            .contentShape(Rectangle())
            .onHover { inside in if inside { launcher.selection = index } }
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.command) && launcher.allowsMarking {
                    launcher.toggleMark(index: index)
                } else {
                    launcher.activate(index: index)
                }
            }
        if case .shelf = item.kind {
            // Drag a copied item straight into another app.
            base.onDrag { launcher.dragProvider(item) ?? NSItemProvider() }
        } else {
            base
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            if let mode = launcher.mode {
                HStack(spacing: 5) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 11, weight: .semibold))
                    Text(mode.name)
                        .font(model.textFont(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(palette.activeText)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(palette.accent.opacity(0.9)))
                .fixedSize()
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            ZStack(alignment: .leading) {
                if launcher.query.isEmpty {
                    Text(launcher.placeholder)
                        .font(model.textFont(size: 15, weight: .regular))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                LauncherField(launcher: launcher, textColor: NSColor(palette.text),
                              caretColor: NSColor(palette.accent))
                    .frame(height: 22)
            }
            if !launcher.marked.isEmpty {
                Text("\(launcher.marked.count)개 선택")
                    .font(model.textFont(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .fixedSize()
            }
            Text(HotKeyMonitor.symbols(model.config.launcher.hotkey))
                .font(model.textFont(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.fill.opacity(0.09))
        )
    }
}

private struct LauncherRow: View {
    @ObservedObject var model: IslandModel
    let item: LauncherItem
    let index: Int
    let selected: Bool
    var marked = false

    var body: some View {
        let p = model.palette
        let text = selected ? p.activeText : p.text
        let secondary = selected ? p.activeText.opacity(0.75) : p.secondary
        HStack(spacing: 10) {
            icon
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                highlighted(item.title, color: text)
                    .font(model.textFont(size: 13.5, weight: .medium))
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(model.textFont(size: 11, weight: .regular))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let badge = item.badge {
                badgeText(badge, hits: item.badgeHits, color: secondary,
                          highlight: selected ? p.activeText : p.accent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill((selected ? p.activeText : p.fill).opacity(0.14))
                    )
            }
            if marked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? p.activeText : p.accent)
            }
            Text(index < 9 ? "\(item.kindLabel)  ⌘\(index + 1)" : item.kindLabel)
                .font(model.textFont(size: 11, weight: .regular))
                .foregroundStyle(secondary)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? p.accent.opacity(0.9) : marked ? p.accent.opacity(0.22) : .clear)
        )
    }

    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .app(let app):
            LauncherIcon(path: app.path)
        case .window(let window):
            AppIconView(app: AppRef(name: window.appName, bundleId: window.bundleId), size: 26)
        case .calculation:
            symbol("equal.square.fill")
        case .currency:
            symbol("dollarsign.circle.fill")
        case .file(let file):
            LauncherIcon(path: file.path)
        case .pane:
            LauncherIcon(path: SettingsPanes.appPath)
        case .islandSettings:
            symbol("capsule.fill")
        case .web(_, let name):
            symbol(name)
        case .plugin(let id):
            symbol(model.launcher.plugin(id: id)?.symbol ?? "square.grid.2x2")
        case .quickLink(let link, _):
            if let path = QuickLinkIcons.shared.handler(link) {
                LauncherIcon(path: path)
            } else {
                symbol(link.needsInput ? "magnifyingglass" : "link")
            }
        case .shelf(let shelfItem):
            if let image = ShelfThumbnails.image(shelfItem) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: shelfItem.kind == .image ? .fill : .fit)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                symbol("doc.on.clipboard")
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(selected ? model.palette.activeText : model.palette.accent)
    }

    /// A keyword with what was typed of it drawn bold in the accent color.
    private func badgeText(_ text: String, hits: Int, color: Color, highlight: Color) -> Text {
        let typed = Text(String(text.prefix(hits))).foregroundColor(highlight).bold()
        return typed + Text(String(text.dropFirst(hits))).foregroundColor(color)
    }

    /// The title with the matched characters drawn bold.
    private func highlighted(_ title: String, color: Color) -> Text {
        guard !item.hits.isEmpty else { return Text(title).foregroundColor(color) }
        let hits = Set(item.hits)
        var result = Text("")
        for (i, ch) in title.enumerated() {
            let piece = Text(String(ch)).foregroundColor(color)
            result = result + (hits.contains(i) ? piece.bold() : piece)
        }
        return result
    }
}

private struct LauncherIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: LauncherIconCache.shared.icon(path))
            .resizable()
            .interpolation(.high)
    }
}

@MainActor
final class LauncherIconCache {
    static let shared = LauncherIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(_ path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}

/// The app (or file) each link opens, looked up once per link.
@MainActor
final class QuickLinkIcons {
    static let shared = QuickLinkIcons()
    private var cache: [String: String?] = [:]

    func handler(_ link: QuickLink) -> String? {
        let key = link.link + "\u{0}" + link.app
        if let cached = cache[key] { return cached }
        let path = link.handlerPath
        cache[key] = .some(path)
        return path
    }
}

// MARK: - Text field

/// A one-line text view for the query. An NSTextView rather than a SwiftUI
/// TextField so Hangul being composed (marked text) is searched as it is
/// typed, and so arrows, Return, Tab and Esc reach the launcher.
struct LauncherField: NSViewRepresentable {
    let launcher: LauncherModel
    let textColor: NSColor
    let caretColor: NSColor

    func makeNSView(context: Context) -> LauncherTextView {
        let view = LauncherTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.maximumNumberOfLines = 1
        view.textContainer?.lineBreakMode = .byClipping
        view.textContainer?.widthTracksTextView = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.font = NSFont.systemFont(ofSize: 15)
        apply(to: view)
        return view
    }

    func updateNSView(_ view: LauncherTextView, context: Context) {
        apply(to: view)
        if view.serial != launcher.querySerial {
            view.serial = launcher.querySerial
            if view.string != launcher.query && !view.hasMarkedText() {
                view.string = launcher.query
                view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            }
            view.focus()
        }
    }

    private func apply(to view: LauncherTextView) {
        view.textColor = textColor
        view.insertionPointColor = caretColor
        view.typingAttributes = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: textColor]
        let launcher = self.launcher
        view.onChange = { text in launcher.setQuery(text) }
        view.onCommand = { [weak view] selector in
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                launcher.move(-1)
            case #selector(NSResponder.moveDown(_:)):
                launcher.move(1)
            case #selector(NSResponder.moveUpAndModifySelection(_:)):
                return launcher.extend(-1)
            case #selector(NSResponder.moveDownAndModifySelection(_:)):
                return launcher.extend(1)
            case #selector(NSResponder.deleteBackward(_:)):
                // ⌫ on an empty field leaves the built-in app.
                guard let view, view.string.isEmpty, !view.hasMarkedText(), launcher.leaveMode() else { return false }
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
                launcher.activate()
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
                launcher.cancel()
            case #selector(NSResponder.insertTab(_:)):
                _ = launcher.tab()
            case #selector(NSResponder.moveRight(_:)):
                // At the end of the text → takes the completion; else moves the caret.
                guard let view, view.selectedRange().location == (view.string as NSString).length,
                      launcher.complete() else { return false }
            default:
                return false
            }
            return true
        }
        view.onCommandKey = { event in
            guard let chars = event.charactersIgnoringModifiers else { return false }
            if chars == "\r" {
                launcher.activate(alternate: true)
                return true
            }
            if chars == "\u{7F}" || chars == "\u{8}" {
                return launcher.removeSelected()
            }
            if chars.lowercased() == "a" {
                return launcher.markAll()
            }
            if let digit = Int(chars), (1...9).contains(digit), digit <= launcher.results.count {
                launcher.activate(index: digit - 1)
                return true
            }
            return false
        }
    }
}

final class LauncherTextView: NSTextView {
    var onChange: ((String) -> Void)?
    /// Returns true when the launcher handled the command.
    var onCommand: ((Selector) -> Bool)?
    /// ⌘-key presses (⌘Return, ⌘1–⌘9).
    var onCommandKey: ((NSEvent) -> Bool)?
    var serial = -1

    override var acceptsFirstResponder: Bool { true }

    func focus() {
        guard let window else { return }
        if window.firstResponder !== self { window.makeFirstResponder(self) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.focus() }
    }

    override func doCommand(by selector: Selector) {
        if onCommand?(selector) == true { return }
        super.doCommand(by: selector)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), window?.firstResponder === self, onCommandKey?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let text = string as? String, text.contains(where: \.isNewline) {
            super.insertText(text.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " "), replacementRange: replacementRange)
        } else {
            super.insertText(string, replacementRange: replacementRange)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        onChange?(string)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onChange?(self.string)
    }

    override func unmarkText() {
        super.unmarkText()
        onChange?(string)
    }
}
