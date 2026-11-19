import SwiftUI

// Gooey ("metaball") rendering: shapes are drawn into a layer, blurred, and
// cut at half opacity. Shapes that are close melt into each other and pull
// apart with a stretching neck. Crisp copies of the shapes are drawn on top
// so the resting outline stays sharp and anti-aliased.

// MARK: - Island silhouette

/// Where the island and its side panels are inside the island frame.
/// `leftProgress` / `rightProgress` run from 0 (panel tucked inside the
/// island) to 1 (panel fully out, separated by the gap).
struct LiquidIslandGeometry {
    var leftProgress: CGFloat
    var rightProgress: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var topConvexRadius: CGFloat
    var leftWidth: CGFloat
    var rightWidth: CGFloat
    var gap: CGFloat
    var panelHeight: CGFloat

    typealias AnimatableData = AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>
    >

    var animatableData: AnimatableData {
        get {
            AnimatablePair(
                AnimatablePair(leftProgress, rightProgress),
                AnimatablePair(AnimatablePair(topRadius, bottomRadius), topConvexRadius)
            )
        }
        set {
            leftProgress = newValue.first.first
            rightProgress = newValue.first.second
            topRadius = newValue.second.first.first
            bottomRadius = newValue.second.first.second
            topConvexRadius = newValue.second.second
        }
    }

    /// True while a panel is on its way, including a spring's overshoot
    /// past fully out. The gooey layer stays on for all of it, so it never
    /// switches on and off mid-animation.
    var isMoving: Bool {
        func resting(_ p: CGFloat) -> Bool { abs(p) < 0.0005 || abs(p - 1) < 0.0005 }
        return !resting(leftProgress) || !resting(rightProgress)
    }

    private var shape: NotchShape {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius, topConvexRadius: topConvexRadius)
    }

    /// A drop is shorter while it is still small, so it swells as it leaves.
    private func dropHeight(_ progress: CGFloat, total: CGFloat) -> CGFloat {
        min(panelHeight, total) * (0.6 + 0.4 * min(max(progress, 0), 1))
    }

    private func rects(in size: CGSize) -> (left: CGRect?, center: CGRect, right: CGRect?) {
        let lp = max(leftProgress, 0), rp = max(rightProgress, 0)
        let leftSpan = leftWidth > 0 ? (leftWidth + gap) * lp : 0
        let rightSpan = rightWidth > 0 ? (rightWidth + gap) * rp : 0
        let center = CGRect(x: leftSpan, y: 0, width: max(size.width - leftSpan - rightSpan, 0), height: size.height)
        var left: CGRect?
        var right: CGRect?
        if leftWidth > 0 && lp > 0.001 {
            left = CGRect(x: 0, y: 0, width: leftWidth * lp, height: dropHeight(lp, total: size.height))
        }
        if rightWidth > 0 && rp > 0.001 {
            let w = rightWidth * rp
            right = CGRect(x: size.width - w, y: 0, width: w, height: dropHeight(rp, total: size.height))
        }
        return (left, center, right)
    }

    /// Simplified bodies for the gooey layer: the outline without the
    /// concave top shoulders (which the blur would fill in and make bulge),
    /// pulled in by a point so the gooey edge never shows past the crisp one,
    /// and run up past the top edge so the blur does not eat it.
    func gooBodies(in size: CGSize) -> [Path] {
        let r = rects(in: size)
        return [r.left, r.center, r.right].compactMap { $0 }.map { rect in
            let w = rect.width, h = rect.height
            let convex = max(0, min(topConvexRadius, w / 2, h / 2))
            if convex > 0 {
                let body = rect.insetBy(dx: 1, dy: 1)
                return Path(roundedRect: body, cornerRadius: max(convex - 1, 0), style: .continuous)
            }
            let top = max(0, min(topRadius, w / 4, h / 2))
            let body = CGRect(x: rect.minX + top + 1, y: rect.minY - islandGooBlur * 3,
                              width: max(w - 2 * top - 2, 0), height: h + islandGooBlur * 3 - 1)
            let bottom = max(0, min(bottomRadius - 1, body.width / 2, h / 2))
            return Path(roundedRect: body, cornerRadii: RectangleCornerRadii(
                topLeading: 0, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: 0))
        }
    }

    /// The island and the panels as separate outlines.
    func blobs(in size: CGSize) -> [Path] {
        let r = rects(in: size)
        return [r.left, r.center, r.right].compactMap { $0 }.map { shape.path(in: $0) }
    }

    /// Bridges between the island and a panel that is still on its way out.
    /// They thin out as the panel separates and vanish before it is done,
    /// which is when the drop visibly snaps off.
    func necks(in size: CGSize) -> [Path] {
        let r = rects(in: size)
        var result: [Path] = []
        func neck(from x0: CGFloat, to x1: CGFloat, height: CGFloat, progress: CGFloat) {
            let thickness = height * 0.62 * (1 - min(max(progress, 0), 1))
            guard thickness > 1 else { return }
            let y = height * 0.5
            let rect = CGRect(x: min(x0, x1) - 6, y: y - thickness / 2, width: abs(x1 - x0) + 12, height: thickness)
            result.append(Path(roundedRect: rect, cornerRadius: thickness / 2))
        }
        if let left = r.left {
            neck(from: left.maxX, to: r.center.minX, height: left.height, progress: leftProgress)
        }
        if let right = r.right {
            neck(from: r.center.maxX, to: right.minX, height: right.height, progress: rightProgress)
        }
        return result
    }
}

/// Blur radius of the gooey layer for the island. A gap wider than about
/// 1.35 × this keeps two drops apart.
private let islandGooBlur: CGFloat = 6

/// Mask for the liquid island: the island and its panels, melted together
/// while a panel moves in or out.
struct LiquidIslandMask: ViewModifier, Animatable {
    var geometry: LiquidIslandGeometry

    var animatableData: LiquidIslandGeometry.AnimatableData {
        get { geometry.animatableData }
        set { geometry.animatableData = newValue }
    }

    func body(content: Content) -> some View {
        let g = geometry
        return content.overlay {
            Canvas { ctx, size in
                if g.isMoving {
                    ctx.drawLayer { goo in
                        goo.addFilter(.alphaThreshold(min: 0.5, color: .black))
                        goo.addFilter(.blur(radius: islandGooBlur))
                        goo.drawLayer { layer in
                            for path in g.gooBodies(in: size) + g.necks(in: size) {
                                layer.fill(path, with: .color(.black))
                            }
                        }
                    }
                }
                for path in g.blobs(in: size) {
                    ctx.fill(path, with: .color(.black))
                }
            }
        }
    }
}

/// Outline of the liquid island (without the necks), for the border.
struct LiquidIslandShape: Shape {
    var geometry: LiquidIslandGeometry

    var animatableData: LiquidIslandGeometry.AnimatableData {
        get { geometry.animatableData }
        set { geometry.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for blob in geometry.blobs(in: rect.size) {
            p.addPath(blob, transform: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        }
        return p
    }
}

// MARK: - Workspace row

/// Frame of every workspace pill / group in the row, by workspace key.
struct WorkspaceFrameKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Step response of a damped spring: 0 at t = 0, settling at 1.
private func springProgress(_ t: Double, period: Double, damping: Double) -> CGFloat {
    guard t > 0 else { return 0 }
    let omega = 2 * Double.pi / period
    if damping >= 1 {
        return CGFloat(1 - exp(-omega * t) * (1 + omega * t))
    }
    let decay = damping * omega
    let wd = omega * sqrt(1 - damping * damping)
    return CGFloat(1 - exp(-decay * t) * (cos(wd * t) + decay / wd * sin(wd * t)))
}

private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(
        x: a.minX + (b.minX - a.minX) * t,
        y: a.minY + (b.minY - a.minY) * t,
        width: a.width + (b.width - a.width) * t,
        height: a.height + (b.height - a.height) * t
    )
}

/// A head that runs ahead and a tail that lags behind, joined by a neck
/// that thins as they pull apart.
private struct LiquidTrail {
    var head: CGRect
    var tail: CGRect
    var neck: Path?
    var isSettled: Bool

    /// `tailScale` nil gives a single drop with no tail: one shape that
    /// moves and stops, nothing left behind to catch up.
    init(from: CGRect, to: CGRect, elapsed: Double, speed: Double, tailScale: CGFloat?) {
        let t = elapsed * speed
        // Nearly critically damped, so the shapes land without wobbling.
        let hp = springProgress(t, period: 0.36, damping: 0.9)
        head = lerp(from, to, hp)
        guard let tailScale else {
            tail = head
            isSettled = t > Self.settleTime
            return
        }
        let tp = springProgress(t - 0.03, period: 0.5, damping: 1)
        let stretch = min(abs(hp - tp), 1)
        let base = lerp(from, to, tp)
        let scale = 1 - tailScale * stretch
        tail = CGRect(
            x: base.midX - base.width * scale / 2,
            y: base.midY - base.height * scale / 2,
            width: base.width * scale,
            height: base.height * scale
        )
        isSettled = t > Self.settleTime
        let distance = hypot(head.midX - tail.midX, head.midY - tail.midY)
        let thickness = min(head.height, tail.height) * 0.55 * max(0, 1 - distance / 160)
        if thickness > 1, distance > 1 {
            var p = Path()
            p.move(to: CGPoint(x: tail.midX, y: tail.midY))
            p.addLine(to: CGPoint(x: head.midX, y: head.midY))
            neck = p.strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .round))
        }
    }

    /// Time after which both springs are within a pixel of the target.
    static let settleTime: Double = 0.75
}

/// Liquid layer behind the workspace row: the active workspace highlight
/// (fill style) that stretches from one workspace to the next, and a drop
/// that flows from a moved window's old workspace to its new one. The drop
/// carries no app icon: the row already moves the real icon, and a second
/// copy in flight read as a ghost of it.
struct RowLiquid: View {
    @ObservedObject var model: IslandModel
    let frames: [String: CGRect]

    @State private var highlightFrom: CGRect?
    @State private var highlightStart = Date.distantPast
    @State private var drop: Drop?
    @State private var animating = false
    @State private var animationToken = 0

    private struct Drop {
        let toKey: String
        let from: CGRect
        let to: CGRect
        let start: Date
    }

    private static let gooBlur: CGFloat = 4
    private static let dropDelay: Double = 0
    private static let duration: Double = LiquidTrail.settleTime

    private var drawsHighlight: Bool { model.usesLiquid && model.activeStyle == .fill }

    private var cornerRadius: CGFloat {
        if model.usesAppStyle {
            return (CGFloat(model.config.appearance.appIconSize) + 8) / 2.6
        }
        return CGFloat(model.config.appearance.pillSize) / 2
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !animating)) { context in
            content(now: context.date)
        }
        .allowsHitTesting(false)
        .onChange(of: model.activeWorkspaceKey) { old, _ in
            // A window that moves with the focus is already shown by the
            // highlight travelling there; a second drop would just crowd it.
            if let new = model.activeWorkspaceKey, drop?.toKey == new { drop = nil }
            guard drawsHighlight, let old, let from = frames[old] else { return }
            highlightFrom = from
            highlightStart = .now
            run()
        }
        .onChange(of: model.eventSerial) { _, _ in
            guard model.config.behavior.windowMoveTrail, let event = model.event,
                  case .windowMove(_, _, let from?, let to, _) = event,
                  let fromRect = frames[from.key], let toRect = frames[to.key], from.key != to.key,
                  !(drawsHighlight && model.activeWorkspaceKey == to.key)
            else { return }
            drop = Drop(toKey: to.key, from: fromRect, to: toRect, start: .now.addingTimeInterval(Self.dropDelay))
            run()
        }
    }

    /// Keeps the timeline ticking for one animation, then lets it rest.
    private func run() {
        animating = true
        animationToken &+= 1
        let token = animationToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration / speed + Self.dropDelay + 0.1) {
            guard token == animationToken else { return }
            animating = false
            drop = nil
        }
    }

    private var speed: Double { min(max(model.config.motion.speed, 0.1), 5) }

    @ViewBuilder private func content(now: Date) -> some View {
        let p = model.palette
        let accent = p.accent
        let opacity = model.usesAppStyle ? 0.32 : 1.0
        let target = model.activeWorkspaceKey.flatMap { frames[$0] }
        let highlight = target.map { to in
            LiquidTrail(from: highlightFrom ?? to, to: to,
                        elapsed: now.timeIntervalSince(highlightStart), speed: speed, tailScale: 0.35)
        }
        let dropTrail = drop.map { d in
            LiquidTrail(from: dropRect(d.from), to: dropRect(d.to),
                        elapsed: now.timeIntervalSince(d.start), speed: speed, tailScale: nil)
        }
        let radius = cornerRadius
        let glow = accent.opacity(model.colors.activeGlow ? 0.55 : 0)

        ZStack(alignment: .topLeading) {
            if drawsHighlight, let highlight {
                Canvas { ctx, _ in
                    Self.draw(highlight, radius: radius, color: accent, settled: highlight.isSettled, in: &ctx)
                }
                .opacity(opacity)
                .shadow(color: glow, radius: 6)
            }
            if let dropTrail, let drop, now >= drop.start {
                let fade = dropFade(dropTrail, drop: drop, now: now)
                Canvas { ctx, _ in
                    Self.draw(dropTrail, radius: nil, color: accent, settled: true, in: &ctx)
                }
                .opacity(0.4 * fade)
            }
        }
    }

    /// The drop fades as it lands.
    private func dropFade(_ trail: LiquidTrail, drop: Drop, now: Date) -> Double {
        let t = now.timeIntervalSince(drop.start) * speed
        return t < 0.35 ? 1 : max(0, 1 - (t - 0.35) / 0.2)
    }

    /// A round drop about the size of an app icon, centered on a workspace.
    private func dropRect(_ frame: CGRect) -> CGRect {
        let d = min(frame.height, CGFloat(model.config.appearance.appIconSize) + 6)
        return CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
    }

    private static func draw(_ trail: LiquidTrail, radius: CGFloat?, color: Color, settled: Bool,
                             in ctx: inout GraphicsContext) {
        func shape(_ rect: CGRect) -> Path {
            let r = min(radius ?? rect.height / 2, rect.height / 2, rect.width / 2)
            return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        }
        if !settled {
            ctx.drawLayer { goo in
                goo.addFilter(.alphaThreshold(min: 0.5, color: color))
                goo.addFilter(.blur(radius: gooBlur))
                goo.drawLayer { layer in
                    layer.fill(shape(trail.head), with: .color(.black))
                    layer.fill(shape(trail.tail), with: .color(.black))
                    if let neck = trail.neck {
                        layer.fill(neck, with: .color(.black))
                    }
                }
            }
        }
        ctx.fill(shape(trail.head), with: .color(color))
    }
}
