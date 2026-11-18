import AppKit
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let position = model.horizontalPosition
        let alignment: Alignment = position == "left" ? .topLeading : (position == "right" ? .topTrailing : .top)
        // The panel is larger than the island; pin the island to the top.
        VStack(spacing: 0) {
            IslandView(model: model)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(.horizontal, position == "center" ? 0 : IslandWindowController.panelMargin)
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @Namespace private var ns

    private var a: IslandConfig.Appearance { model.config.appearance }
    private var colors: IslandConfig.ThemeColors { model.colors }
    private var isHidden: Bool { model.phase == .hidden }

    private var shape: NotchShape {
        let floating = model.isFloating && !isHidden
        return NotchShape(
            topRadius: isHidden || floating ? 0 : CGFloat(a.topCornerRadius),
            bottomRadius: isHidden ? min(CGFloat(a.bottomCornerRadius), model.geometry.height * 0.35)
                : CGFloat(a.bottomCornerRadius),
            topConvexRadius: floating ? CGFloat(a.bottomCornerRadius) : 0
        )
    }

    private var showsRow: Bool {
        guard !isHidden else { return false }
        return !(model.phase == .expanded && model.event != nil && model.eventPlacement == .replace)
    }

    var body: some View {
        let size = model.currentSize
        let topInset = isHidden || model.isFloating ? 0 : CGFloat(a.topCornerRadius)

        VStack(spacing: 0) {
            if !isHidden && !model.isFloating {
                topStrip
                    .frame(height: model.geometry.height)
                    .transition(fade)
            }
            if model.eventPlacement == .above {
                eventHeader
            }
            if showsRow {
                rowArea
                    .frame(height: model.rowHeight)
                    .transition(fade)
            }
            if model.eventPlacement != .above {
                eventHeader
            }
        }
        .padding(.horizontal, topInset)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background {
            IslandBackground(model: model, solidBlack: isHidden && !model.hiddenStyleFades)
        }
        .overlay(alignment: .bottom) {
            if model.phase == .expanded && a.showEventProgress {
                EventProgressBar(model: model)
                    .id(model.eventSerial)
                    .transition(.opacity)
            }
        }
        .clipShape(shape)
        .overlay {
            if !isHidden && colors.borderOpacity > 0 {
                shape.stroke(model.palette.fill.opacity(colors.borderOpacity), lineWidth: 1)
            }
        }
        .shadow(
            color: .black.opacity(colors.shadow && !isHidden ? 0.35 : 0),
            radius: isHidden ? 0 : 14, x: 0, y: 6
        )
        .opacity(isHidden && model.hiddenStyleFades ? 0 : 1)
        .modifier(PopEffect(trigger: model.config.motion.popOnEvent ? model.eventSerial : 0))
        .foregroundStyle(model.palette.text)
        .padding(.top, model.currentTopOffset)
    }

    @ViewBuilder private var eventHeader: some View {
        if model.phase == .expanded, let event = model.event {
            EventHeader(model: model, event: event)
                .frame(height: CGFloat(a.expandedHeaderHeight))
                .padding(.horizontal, 18)
                .id(model.eventSerial)
                .transition(fade)
        }
    }

    /// The workspace row; a floating island also carries the wing widgets
    /// at its ends, since there is no strip beside the notch.
    @ViewBuilder private var rowArea: some View {
        if model.isFloating {
            HStack(spacing: 10) {
                if model.config.widgets.leftWing.lowercased() != "none" {
                    WingView(model: model, widget: model.config.widgets.leftWing)
                        .frame(maxWidth: model.leftWingWidth, alignment: .leading)
                }
                WorkspaceRow(model: model, ns: ns)
                if model.config.widgets.rightWing.lowercased() != "none" {
                    WingView(model: model, widget: model.config.widgets.rightWing)
                        .frame(maxWidth: model.rightWingWidth, alignment: .trailing)
                }
            }
            .padding(.horizontal, model.contentPadding)
        } else {
            WorkspaceRow(model: model, ns: ns)
        }
    }

    private var fade: AnyTransition {
        switch model.config.motion.contentTransition.lowercased() {
        case "none":
            return .identity
        case "slide":
            return .asymmetric(
                insertion: AnyTransition.modifier(
                    active: SlideFade(offset: 10, opacity: 0),
                    identity: SlideFade(offset: 0, opacity: 1)
                ).animation(model.swiftUIAnimation?.delay(0.06)),
                removal: .modifier(
                    active: SlideFade(offset: -6, opacity: 0),
                    identity: SlideFade(offset: 0, opacity: 1)
                )
            )
        default:
            let blur = model.config.motion.contentTransition.lowercased() != "fade"
            return .asymmetric(
                insertion: AnyTransition.modifier(
                    active: BlurFade(radius: blur ? 6 : 0, opacity: 0, scale: blur ? 0.92 : 1),
                    identity: BlurFade(radius: 0, opacity: 1, scale: 1)
                ).animation(model.swiftUIAnimation?.delay(0.06)),
                removal: .modifier(
                    active: BlurFade(radius: blur ? 4 : 0, opacity: 0, scale: blur ? 0.96 : 1),
                    identity: BlurFade(radius: 0, opacity: 1, scale: 1)
                )
            )
        }
    }

    /// Row at notch height with a widget on each wing. The middle is covered
    /// by the hardware notch.
    private var topStrip: some View {
        let wingSpace = max(0, (model.currentSize.width - model.geometry.width) / 2 - 20)
        return HStack(spacing: 6) {
            WingView(model: model, widget: model.config.widgets.leftWing)
                .frame(maxWidth: wingSpace, alignment: .leading)
            Spacer(minLength: model.geometry.width)
            WingView(model: model, widget: model.config.widgets.rightWing)
                .frame(maxWidth: wingSpace, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Background

/// Solid color, macOS material or gradient behind the island content.
struct IslandBackground: View {
    @ObservedObject var model: IslandModel
    /// Hidden in the notch: always plain black so it matches the hardware.
    let solidBlack: Bool

    var body: some View {
        let p = model.palette
        let c = p.colors
        if solidBlack {
            Color.black
        } else {
            switch c.backgroundStyle.lowercased() {
            case "material":
                ZStack {
                    VisualEffectBackground(material: c.material, dark: p.isDark, withinWindow: model.isPreview)
                    p.background.opacity(c.backgroundOpacity)
                }
            case "gradient":
                Self.gradient(p)
                    .opacity(c.backgroundOpacity)
            default:
                p.background.opacity(c.backgroundOpacity)
            }
        }
    }

    /// The two-color gradient; 0° runs left → right, 90° top → bottom.
    static func gradient(_ p: IslandPalette) -> LinearGradient {
        let radians = p.colors.gradientAngle * .pi / 180
        let dx = cos(radians) / 2
        let dy = sin(radians) / 2
        return LinearGradient(colors: [p.background, p.gradientEnd],
                              startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                              endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: String
    let dark: Bool
    let withinWindow: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.blendingMode = withinWindow ? .withinWindow : .behindWindow
        switch material.lowercased() {
        case "thin": view.material = .hudWindow
        case "thick": view.material = .windowBackground
        default: view.material = .popover
        }
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}

// MARK: - Wings

/// One widget beside the notch (or at the end of a floating island).
struct WingView: View {
    @ObservedObject var model: IslandModel
    let widget: String

    var body: some View {
        let size = CGFloat(model.config.appearance.fontSize)
        let p = model.palette
        switch widget.lowercased() {
        case "app":
            if let app = model.focusedApp {
                HStack(spacing: 6) {
                    AppIconView(app: app, size: 16)
                    Text(app.name ?? "")
                        .font(model.textFont(size: size * 0.85, weight: .medium))
                        .foregroundStyle(p.secondary)
                        .lineLimit(1)
                }
            }
        case "workspace":
            if let label = model.activeWorkspaceText {
                Text(label)
                    .font(model.numberFont(size: size * 0.9, weight: .bold))
                    .foregroundStyle(p.accent)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        case "clock":
            ClockText(template: ClockText.template(for: model.config.widgets.clockFormat),
                      font: model.textFont(size: size * 0.85, weight: .semibold), color: p.secondary)
        case "date":
            ClockText(template: "MMMdE", font: model.textFont(size: size * 0.85, weight: .medium), color: p.secondary)
        case "windows":
            HStack(spacing: 4) {
                Image(systemName: "macwindow")
                    .font(.system(size: size * 0.8, weight: .semibold))
                Text("\(model.activeWindowCount)")
                    .font(model.numberFont(size: size * 0.85, weight: .semibold))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(p.secondary)
        default:
            EmptyView()
        }
    }
}

/// Current time or date, refreshed every second.
struct ClockText: View {
    let template: String
    let font: Font
    let color: Color

    static func template(for format: String) -> String {
        switch format.lowercased() {
        case "12h": return "hmm"
        case "24hseconds": return "HHmmss"
        default: return "HHmm"
        }
    }

    private static func string(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.string(context.date, template: template))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Workspace row

struct WorkspaceRow: View {
    @ObservedObject var model: IslandModel
    let ns: Namespace.ID

    var body: some View {
        let a = model.config.appearance
        let alignment = model.config.layout.rowAlignment.lowercased()
        let inset: CGFloat = model.isFloating || alignment == "center" ? 0 : model.contentPadding
        HStack(spacing: CGFloat(a.pillSpacing)) {
            ForEach(Array(model.workspaces.enumerated()), id: \.element.id) { index, ws in
                if alignment == "spread" && index > 0 {
                    Spacer(minLength: 0)
                }
                if model.usesAppStyle {
                    WorkspaceGroup(model: model, ws: ws, ns: ns)
                } else {
                    WorkspacePill(model: model, ws: ws, ns: ns)
                }
            }
        }
        .padding(.horizontal, inset)
        .frame(maxWidth: .infinity, alignment: alignment == "leading" ? .leading : .center)
        .padding(.bottom, model.isFloating ? 0 : 4)
    }
}

/// Shared highlight behind the active workspace; slides between workspaces.
private struct ActiveHighlight: View {
    @ObservedObject var model: IslandModel
    let ws: WorkspaceItem
    let ns: Namespace.ID
    let shape: AnyShape
    let inactiveFill: Color

    var body: some View {
        let colors = model.colors
        let accent = model.palette.accent
        let isActive = ws.id == model.activeWorkspaceKey
        let isTarget = model.phase == .expanded && model.event?.targetWorkspaceKey == ws.id
        let glow = accent.opacity(colors.activeGlow ? 0.55 : 0)
        ZStack {
            if !isActive || model.activeStyle != .fill {
                shape.fill(inactiveFill)
            }
            if isActive {
                marker(accent: accent, glow: glow)
                    .matchedGeometryEffect(id: "active-workspace", in: ns)
            }
            if isTarget && !isActive {
                shape.stroke(accent, lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder private func marker(accent: Color, glow: Color) -> some View {
        switch model.activeStyle {
        case .fill:
            shape
                .fill(accent.opacity(model.usesAppStyle ? 0.32 : 1))
                .shadow(color: glow, radius: 6, x: 0, y: 0)
        case .outline:
            shape
                .stroke(accent, lineWidth: 1.5)
                .shadow(color: glow, radius: 6, x: 0, y: 0)
        case .underline:
            Capsule()
                .fill(accent)
                .frame(height: 2)
                .padding(.horizontal, 6)
                .shadow(color: glow, radius: 4, x: 0, y: 0)
                .frame(maxHeight: .infinity, alignment: .bottom)
        case .dot:
            Circle()
                .fill(accent)
                .frame(width: 4, height: 4)
                .shadow(color: glow, radius: 4, x: 0, y: 0)
                .offset(y: 4)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// "pills" style: a numbered capsule per workspace.
private struct WorkspacePill: View {
    @ObservedObject var model: IslandModel
    let ws: WorkspaceItem
    let ns: Namespace.ID

    var body: some View {
        let a = model.config.appearance
        let isActive = ws.id == model.activeWorkspaceKey
        let isTarget = model.phase == .expanded && model.event?.targetWorkspaceKey == ws.id
        let label = model.label(for: ws)
        let activeColor = model.activeStyle == .fill ? model.palette.activeText : model.palette.accent
        ZStack {
            ActiveHighlight(model: model, ws: ws, ns: ns, shape: AnyShape(Capsule()),
                            inactiveFill: model.palette.fill.opacity(ws.windowCount > 0 ? 0.14 : 0.06))
            Text(label)
                .font(model.pillSwiftUIFont)
                .lineLimit(1)
                .foregroundStyle(isActive ? activeColor : model.palette.text.opacity(ws.windowCount > 0 ? 0.9 : 0.45))
        }
        .frame(width: model.pillWidth(for: label), height: CGFloat(a.pillSize))
        .scaleEffect(isTarget ? 1.08 : 1)
    }
}

/// "apps" style: workspace label followed by the icons of its apps, with
/// Dock notification badges, similar to OmniWM's own workspace bar.
private struct WorkspaceGroup: View {
    @ObservedObject var model: IslandModel
    let ws: WorkspaceItem
    let ns: Namespace.ID

    var body: some View {
        let a = model.config.appearance
        let isActive = ws.id == model.activeWorkspaceKey
        let isTarget = model.phase == .expanded && model.event?.targetWorkspaceKey == ws.id
        let iconSize = CGFloat(a.appIconSize)
        let apps = model.displayedApps(for: ws)
        let shown = Array(apps.prefix(model.maxAppsPerWorkspace))
        let hidden = apps.count - shown.count
        let isEmpty = ws.apps.isEmpty && ws.windowCount == 0

        HStack(spacing: IslandModel.appIconGap) {
            labelText(isActive: isActive, isEmpty: isEmpty, hasIcons: !shown.isEmpty)
            ForEach(shown) { app in
                icon(app, isActive: isActive, size: iconSize)
            }
            if hidden > 0 {
                overflowText(hidden)
            }
        }
        .padding(.horizontal, IslandModel.groupPadding)
        .frame(height: iconSize + 8)
        .background {
            highlight(iconSize: iconSize, isEmpty: isEmpty)
        }
        .scaleEffect(isTarget ? 1.06 : 1)
    }

    private func labelText(isActive: Bool, isEmpty: Bool, hasIcons: Bool) -> some View {
        let size = CGFloat(model.config.appearance.fontSize) * 1.05
        let opacity: Double = isActive ? 1 : (isEmpty ? 0.35 : 0.6)
        return Text(model.label(for: ws))
            .font(model.numberFont(size: size, weight: isActive ? .heavy : .semibold))
            .foregroundStyle(model.palette.text.opacity(opacity))
            .lineLimit(1)
            .fixedSize()
            .padding(.trailing, hasIcons ? 2 : 0)
    }

    private func overflowText(_ count: Int) -> some View {
        Text("+\(count)")
            .font(model.numberFont(size: CGFloat(model.config.appearance.fontSize) * 0.8, weight: .semibold))
            .foregroundStyle(model.palette.text.opacity(0.6))
            .fixedSize()
    }

    private func icon(_ app: WorkspaceApp, isActive: Bool, size: CGFloat) -> some View {
        let showDots = model.multiWindowStyle == .dots && app.windowCount > 1
        let badge = model.badge(for: app)
        return AppIconView(app: app.appRef, size: size)
            .opacity(isActive || app.isFocused ? 1 : 0.8)
            .overlay(alignment: .bottom) {
                if showDots {
                    WindowCountDots(count: app.windowCount, iconSize: size, color: model.palette.fill)
                        .offset(y: max(3, size * 0.2))
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge {
                    BadgeView(label: badge, iconSize: size, palette: model.palette)
                        .offset(x: size * 0.18, y: -size * 0.18)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    private func highlight(iconSize: CGFloat, isEmpty: Bool) -> some View {
        let shape = AnyShape(RoundedRectangle(cornerRadius: (iconSize + 8) / 2.6, style: .continuous))
        return ActiveHighlight(model: model, ws: ws, ns: ns, shape: shape,
                               inactiveFill: model.palette.fill.opacity(isEmpty ? 0 : 0.06))
    }
}

/// One dot per window (up to three) under an app icon, like the Dock's
/// running indicator, so several windows of one app stay visible.
private struct WindowCountDots: View {
    let count: Int
    let iconSize: CGFloat
    let color: Color

    var body: some View {
        let dot = max(2.5, iconSize * 0.14)
        HStack(spacing: dot * 0.7) {
            ForEach(0..<min(count, 3), id: \.self) { _ in
                Circle().fill(color.opacity(0.75)).frame(width: dot, height: dot)
            }
        }
    }
}

/// Red Dock-style notification badge. Numbers up to two digits are shown,
/// anything else becomes a dot.
private struct BadgeView: View {
    let label: String
    let iconSize: CGFloat
    let palette: IslandPalette

    var body: some View {
        let short = label.count <= 2 && Int(label) != nil
        let size = max(8, iconSize * (short ? 0.55 : 0.4))
        ZStack {
            Capsule().fill(palette.badge)
            if short {
                Text(label)
                    .font(.system(size: size * 0.68, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.badgeText)
                    .padding(.horizontal, size * 0.22)
            }
        }
        .frame(minWidth: size, maxHeight: size)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: size)
        .overlay(Capsule().stroke(Color.black.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Event header

struct EventHeader: View {
    @ObservedObject var model: IslandModel
    let event: IslandEvent

    var body: some View {
        let a = model.config.appearance
        let w = model.config.widgets
        let secondary = model.palette.secondary
        HStack(spacing: 12) {
            if w.eventIcon {
                icon
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(model.textFont(size: CGFloat(a.fontSize) + 2, weight: .semibold))
                    .lineLimit(1)
                if w.eventSubtitle, let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(model.textFont(size: CGFloat(a.fontSize) * 0.85, weight: .regular))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if w.eventFromTo {
                FromToView(model: model, from: from, to: to)
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch event {
        case .windowMove(let app, _, _, _, _) where model.config.appearance.showAppIcons && app != nil:
            AppIconView(app: app!, size: 30)
        case .windowMove:
            Image(systemName: "macwindow.on.rectangle").font(.system(size: 22))
        case .workspaceSwitch:
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 22))
        }
    }

    private var title: String {
        switch event {
        case .workspaceSwitch(_, let to, _):
            return "워크스페이스 \(model.label(for: to))"
        case .windowMove(let app, _, _, _, let count):
            let name = app?.name ?? "창"
            return count > 1 ? "\(name) 외 \(count - 1)개 창 이동" : "\(name) 이동"
        }
    }

    private var subtitle: String? {
        switch event {
        case .workspaceSwitch(_, _, let app):
            return app?.name.map { "\($0) 포커스" } ?? "워크스페이스 전환"
        case .windowMove(_, let title, _, _, _):
            return title
        }
    }

    private var from: WorkspaceRef? {
        switch event {
        case .workspaceSwitch(let f, _, _): return f
        case .windowMove(_, _, let f, _, _): return f
        }
    }

    private var to: WorkspaceRef {
        switch event {
        case .workspaceSwitch(_, let t, _): return t
        case .windowMove(_, _, _, let t, _): return t
        }
    }
}

struct FromToView: View {
    @ObservedObject var model: IslandModel
    let from: WorkspaceRef?
    let to: WorkspaceRef
    @State private var arrived = false

    var body: some View {
        let a = model.config.appearance
        let accent = model.palette.accent
        HStack(spacing: 6) {
            if let from {
                pill(model.label(for: from), fill: model.palette.fill.opacity(0.14), text: model.palette.text)
                Image(systemName: "arrow.right")
                    .font(.system(size: CGFloat(a.fontSize) * 0.85, weight: .bold))
                    .opacity(0.7)
                    .offset(x: arrived ? 0 : -6)
            }
            pill(model.label(for: to), fill: accent, text: model.palette.activeText)
                .scaleEffect(arrived ? 1 : 0.6)
                .opacity(arrived ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.62).delay(0.08)) {
                arrived = true
            }
        }
    }

    private func pill(_ label: String, fill: Color, text: Color) -> some View {
        Text(label)
            .font(model.pillSwiftUIFont)
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minWidth: CGFloat(model.config.appearance.pillSize),
                   minHeight: CGFloat(model.config.appearance.pillSize))
            .background(Capsule().fill(fill))
    }
}

// MARK: - Helpers

struct AppIconView: View {
    let app: AppRef
    let size: CGFloat

    var body: some View {
        if let image = AppIconCache.shared.icon(for: app) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.8))
                .frame(width: size, height: size)
        }
    }
}

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for app: AppRef) -> NSImage? {
        guard let bundleId = app.bundleId, !bundleId.isEmpty else { return nil }
        if let cached = cache[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleId] = image
        return image
    }
}

/// Blur + fade + scale used for content transitions.
struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
    }
}

/// Fade + small vertical slide used for the "slide" content transition.
struct SlideFade: ViewModifier {
    let offset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
    }
}

/// A short scale "pop" each time `trigger` changes.
struct PopEffect: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { view, scale in
            view.scaleEffect(scale, anchor: .top)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(CGFloat(1.045), duration: 0.16, spring: .snappy)
                SpringKeyframe(CGFloat(1), duration: 0.4, spring: .bouncy)
            }
        }
    }
}

/// Thin accent line along the bottom edge that runs out while the expanded
/// event is on screen.
struct EventProgressBar: View {
    @ObservedObject var model: IslandModel
    @State private var remaining: CGFloat = 1

    var body: some View {
        let color = model.palette.progress
        let duration = max(model.config.behavior.eventDurationMs, 100) / 1000
        GeometryReader { proxy in
            Capsule()
                .fill(color.opacity(0.85))
                .frame(width: proxy.size.width * remaining, height: 2)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 2)
        .padding(.horizontal, CGFloat(model.config.appearance.bottomCornerRadius) + 8)
        .padding(.bottom, 3)
        .onAppear {
            remaining = 1
            withAnimation(.linear(duration: duration)) { remaining = 0 }
        }
    }
}
