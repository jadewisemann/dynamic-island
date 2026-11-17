import AppKit
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        // The panel is larger than the island; pin the island to the top.
        VStack(spacing: 0) {
            IslandView(model: model)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @Namespace private var ns

    private var a: IslandConfig.Appearance { model.config.appearance }
    private var isHidden: Bool { model.phase == .hidden }

    private var background: Color {
        if isHidden && !model.hiddenStyleFades { return .black }
        return Color(hex: a.backgroundColor).opacity(a.backgroundOpacity)
    }

    private var shape: NotchShape {
        NotchShape(
            topRadius: isHidden ? 0 : CGFloat(a.topCornerRadius),
            bottomRadius: isHidden ? min(CGFloat(a.bottomCornerRadius), model.geometry.height * 0.35)
                : CGFloat(a.bottomCornerRadius)
        )
    }

    var body: some View {
        let size = model.currentSize
        let topInset = isHidden ? 0 : CGFloat(a.topCornerRadius)

        VStack(spacing: 0) {
            if !isHidden {
                topStrip
                    .frame(height: model.geometry.height)
                    .transition(fade)
                WorkspaceRow(model: model, ns: ns)
                    .frame(height: model.rowHeight)
                    .transition(fade)
            }
            if model.phase == .expanded, let event = model.event {
                EventHeader(model: model, event: event)
                    .frame(height: CGFloat(a.expandedHeaderHeight))
                    .padding(.horizontal, 18)
                    .id(model.eventSerial)
                    .transition(fade)
            }
        }
        .padding(.horizontal, topInset)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(background)
        .overlay(alignment: .bottom) {
            if model.phase == .expanded && a.showEventProgress {
                EventProgressBar(model: model)
                    .id(model.eventSerial)
                    .transition(.opacity)
            }
        }
        .clipShape(shape)
        .overlay {
            if !isHidden && a.borderOpacity > 0 {
                shape.stroke(Color.white.opacity(a.borderOpacity), lineWidth: 1)
            }
        }
        .shadow(
            color: .black.opacity(a.shadow && !isHidden ? 0.35 : 0),
            radius: isHidden ? 0 : 14, x: 0, y: 6
        )
        .opacity(isHidden && model.hiddenStyleFades ? 0 : 1)
        .modifier(PopEffect(trigger: model.config.motion.popOnEvent ? model.eventSerial : 0))
        .foregroundStyle(Color(hex: a.textColor, fallback: .white))
    }

    private var fade: AnyTransition {
        let blur = model.config.motion.blurTransitions
        return .asymmetric(
            insertion: AnyTransition.modifier(
                active: BlurFade(radius: blur ? 6 : 0, opacity: 0, scale: 0.92),
                identity: BlurFade(radius: 0, opacity: 1, scale: 1)
            ).animation(model.swiftUIAnimation?.delay(0.06)),
            removal: .modifier(
                active: BlurFade(radius: blur ? 4 : 0, opacity: 0, scale: 0.96),
                identity: BlurFade(radius: 0, opacity: 1, scale: 1)
            )
        )
    }

    /// Row at notch height: focused app on the left wing, active workspace on
    /// the right wing. The middle is covered by the hardware notch.
    private var topStrip: some View {
        HStack(spacing: 6) {
            if a.showFocusedApp, let app = model.focusedApp {
                AppIconView(app: app, size: 16)
                Text(app.name ?? "")
                    .font(.system(size: CGFloat(a.fontSize) * 0.85, weight: .medium))
                    .foregroundStyle(Color(hex: a.secondaryTextColor, fallback: .gray))
                    .lineLimit(1)
                    .frame(maxWidth: max(0, (model.currentSize.width - model.geometry.width) / 2 - 40),
                           alignment: .leading)
            }
            Spacer(minLength: model.geometry.width)
            if let label = model.activeWorkspaceLabel {
                Text(label)
                    .font(.system(size: CGFloat(a.fontSize) * 0.9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: a.accentColor, fallback: .blue))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Workspace row

struct WorkspaceRow: View {
    @ObservedObject var model: IslandModel
    let ns: Namespace.ID

    var body: some View {
        let a = model.config.appearance
        HStack(spacing: CGFloat(a.pillSpacing)) {
            ForEach(model.workspaces) { ws in
                if model.usesAppStyle {
                    WorkspaceGroup(model: model, ws: ws, ns: ns)
                } else {
                    WorkspacePill(model: model, ws: ws, ns: ns)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
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
        let accent = Color(hex: model.config.appearance.accentColor, fallback: .blue)
        let isActive = ws.id == model.activeWorkspaceKey
        let isTarget = model.phase == .expanded && model.event?.targetWorkspaceKey == ws.id
        ZStack {
            if isActive {
                shape
                    .fill(accent.opacity(model.usesAppStyle ? 0.32 : 1))
                    .shadow(color: accent.opacity(0.55), radius: 6, x: 0, y: 0)
                    .matchedGeometryEffect(id: "active-workspace", in: ns)
            } else {
                shape.fill(inactiveFill)
            }
            if isTarget && !isActive {
                shape.stroke(accent, lineWidth: 1.5)
            }
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
        ZStack {
            ActiveHighlight(model: model, ws: ws, ns: ns, shape: AnyShape(Capsule()),
                            inactiveFill: Color.white.opacity(ws.windowCount > 0 ? 0.14 : 0.06))
            Text(ws.label)
                .font(model.pillSwiftUIFont)
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(ws.windowCount > 0 ? 0.9 : 0.45))
        }
        .frame(width: model.pillWidth(for: ws.label), height: CGFloat(a.pillSize))
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
        let shown = Array(ws.apps.prefix(model.maxAppsPerWorkspace))
        let hidden = ws.apps.count - shown.count
        let isEmpty = ws.apps.isEmpty && ws.windowCount == 0

        HStack(spacing: IslandModel.appIconGap) {
            Text(ws.label)
                .font(.system(size: CGFloat(a.fontSize) * 1.05,
                              weight: isActive ? .heavy : .semibold,
                              design: .rounded))
                .foregroundStyle(Color.white.opacity(isActive ? 1 : (isEmpty ? 0.35 : 0.6)))
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, shown.isEmpty ? 0 : 2)
            ForEach(shown) { app in
                AppIconView(app: app.appRef, size: iconSize)
                    .opacity(isActive || app.isFocused ? 1 : 0.8)
                    .overlay(alignment: .bottom) {
                        if a.showWindowCount && app.windowCount > 1 {
                            WindowCountDots(count: app.windowCount, iconSize: iconSize)
                                .offset(y: max(3, iconSize * 0.2))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let badge = model.badge(for: app) {
                            BadgeView(label: badge, iconSize: iconSize)
                                .offset(x: iconSize * 0.18, y: -iconSize * 0.18)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(.system(size: CGFloat(a.fontSize) * 0.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize()
            }
        }
        .padding(.horizontal, IslandModel.groupPadding)
        .frame(height: iconSize + 8)
        .background {
            ActiveHighlight(model: model, ws: ws, ns: ns,
                            shape: AnyShape(RoundedRectangle(cornerRadius: (iconSize + 8) / 2.6, style: .continuous)),
                            inactiveFill: Color.white.opacity(isEmpty ? 0 : 0.06))
        }
        .scaleEffect(isTarget ? 1.06 : 1)
    }
}

/// One dot per window (up to three) under an app icon, like the Dock's
/// running indicator, so several windows of one app stay visible.
private struct WindowCountDots: View {
    let count: Int
    let iconSize: CGFloat

    var body: some View {
        let dot = max(2.5, iconSize * 0.14)
        HStack(spacing: dot * 0.7) {
            ForEach(0..<min(count, 3), id: \.self) { _ in
                Circle().fill(Color.white.opacity(0.75)).frame(width: dot, height: dot)
            }
        }
    }
}

/// Red Dock-style notification badge. Numbers up to two digits are shown,
/// anything else becomes a dot.
private struct BadgeView: View {
    let label: String
    let iconSize: CGFloat

    var body: some View {
        let short = label.count <= 2 && Int(label) != nil
        let size = max(8, iconSize * (short ? 0.55 : 0.4))
        ZStack {
            Capsule().fill(Color(red: 1, green: 0.23, blue: 0.19))
            if short {
                Text(label)
                    .font(.system(size: size * 0.68, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
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
        let secondary = Color(hex: a.secondaryTextColor, fallback: .gray)
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: CGFloat(a.fontSize) + 2, weight: .semibold))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: CGFloat(a.fontSize) * 0.85))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            FromToView(model: model, from: from, to: to)
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
            return "워크스페이스 \(to.label)"
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
        let accent = Color(hex: a.accentColor, fallback: .blue)
        HStack(spacing: 6) {
            if let from {
                pill(from.label, fill: Color.white.opacity(0.14))
                Image(systemName: "arrow.right")
                    .font(.system(size: CGFloat(a.fontSize) * 0.85, weight: .bold))
                    .opacity(0.7)
                    .offset(x: arrived ? 0 : -6)
            }
            pill(to.label, fill: accent)
                .scaleEffect(arrived ? 1 : 0.6)
                .opacity(arrived ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.62).delay(0.08)) {
                arrived = true
            }
        }
    }

    private func pill(_ label: String, fill: Color) -> some View {
        Text(label)
            .font(model.pillSwiftUIFont)
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
        let accent = Color(hex: model.config.appearance.accentColor, fallback: .blue)
        let duration = max(model.config.behavior.eventDurationMs, 100) / 1000
        GeometryReader { proxy in
            Capsule()
                .fill(accent.opacity(0.85))
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
