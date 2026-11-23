import SwiftUI

/// Colors for a usage percentage: accent below 70 %, orange, then red.
enum UsageColor {
    static func color(_ percent: Double?, palette p: IslandPalette) -> Color {
        guard let percent else { return p.accent }
        if percent >= 90 { return Color(hex: "#FF453A", fallback: .red) }
        if percent >= 70 { return Color(hex: "#FF9F0A", fallback: .orange) }
        return p.accent
    }
}

/// A thin ring filled to `fraction`.
struct UsageRing: View {
    let fraction: Double
    let color: Color
    let track: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// "5시간 ▓▓▓░░ 42%" for one plan limit.
struct UsageBar: View {
    @ObservedObject var model: IslandModel
    let limit: AIUsage.Limit
    let size: CGFloat

    var body: some View {
        let p = model.palette
        HStack(spacing: 5) {
            Text(limit.label)
                .font(model.textFont(size: size * 0.72, weight: .medium))
                .foregroundStyle(p.secondary)
                .lineLimit(1)
                .fixedSize()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.fill.opacity(0.16))
                    Capsule()
                        .fill(UsageColor.color(limit.percent, palette: p))
                        .frame(width: max(proxy.size.width * limit.percent / 100, limit.percent > 0 ? 3 : 0))
                }
            }
            .frame(height: max(size * 0.32, 4))
            Text("\(Int(limit.percent.rounded()))%")
                .font(model.numberFont(size: size * 0.75, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Side panel tile. Square: ring with the 5-hour percentage (or this
/// session's tokens) and when it resets. Wide: one bar per limit.
struct UsageTile: View {
    @ObservedObject var model: IslandModel
    let wide: Bool
    let unit: CGFloat

    var body: some View {
        let p = model.palette
        if let usage = model.aiUsage {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if wide {
                    wideBody(usage, now: context.date)
                } else {
                    square(usage, now: context.date)
                }
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: unit * 0.22))
                Text(model.config.usage.enabled ? "사용량 읽는 중" : "사용량 꺼짐")
                    .font(model.textFont(size: unit * 0.12, weight: .regular))
            }
            .foregroundStyle(p.secondary)
        }
    }

    private func square(_ usage: AIUsage, now: Date) -> some View {
        let p = model.palette
        let five = usage.fiveHour
        return VStack(spacing: unit * 0.05) {
            ZStack {
                UsageRing(fraction: (five?.percent ?? 0) / 100,
                          color: UsageColor.color(five?.percent, palette: p),
                          track: p.fill.opacity(0.16), lineWidth: unit * 0.05)
                Text(usage.shortText)
                    .font(model.numberFont(size: unit * (five == nil ? 0.13 : 0.16), weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, unit * 0.08)
            }
            .frame(width: unit * 0.52, height: unit * 0.52)
            Text(AIUsage.remaining(until: usage.resetDate, now: now).map { "리셋 \($0)" } ?? "Claude")
                .font(model.textFont(size: unit * 0.1, weight: .regular))
                .foregroundStyle(p.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func wideBody(_ usage: AIUsage, now: Date) -> some View {
        let p = model.palette
        let size = unit * 0.17
        return VStack(alignment: .leading, spacing: unit * 0.07) {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.7, weight: .semibold))
                    .foregroundStyle(Color(hex: "#D97757", fallback: p.accent))
                Text("Claude Code")
                    .font(model.textFont(size: size * 0.8, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let reset = AIUsage.remaining(until: usage.resetDate, now: now) {
                    Text("리셋 \(reset)")
                        .font(model.textFont(size: size * 0.66, weight: .regular))
                        .foregroundStyle(p.secondary)
                        .lineLimit(1)
                }
            }
            if usage.limits.isEmpty {
                Text("이번 세션 \(AIUsage.tokens(usage.blockTokens)) 토큰")
                    .font(model.textFont(size: size * 0.75, weight: .medium))
                    .lineLimit(1)
            } else {
                ForEach(Array(usage.limits.prefix(2))) { limit in
                    UsageBar(model: model, limit: limit, size: size)
                }
            }
            Text("오늘 \(AIUsage.tokens(usage.todayTokens)) 토큰 · 응답 \(usage.todayMessages)개")
                .font(model.textFont(size: size * 0.66, weight: .regular))
                .foregroundStyle(p.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Dashboard row: plan limits as bars, or token counts without them.
struct UsageDashboardRow: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let size = CGFloat(model.config.appearance.fontSize)
        let p = model.palette
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.75, weight: .semibold))
                .foregroundStyle(Color(hex: "#D97757", fallback: p.accent))
            if let usage = model.aiUsage {
                if usage.limits.isEmpty {
                    Text("이번 세션 \(AIUsage.tokens(usage.blockTokens)) · 오늘 \(AIUsage.tokens(usage.todayTokens)) 토큰")
                        .font(model.textFont(size: size * 0.8, weight: .medium))
                        .lineLimit(1)
                } else {
                    ForEach(Array(usage.limits.prefix(2))) { limit in
                        UsageBar(model: model, limit: limit, size: size)
                    }
                }
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let reset = AIUsage.remaining(until: usage.resetDate, now: context.date) {
                        Text("리셋 \(reset)")
                            .font(model.textFont(size: size * 0.72, weight: .regular))
                            .foregroundStyle(p.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            } else {
                Text(model.config.usage.enabled ? "Claude Code 사용량을 읽는 중입니다" : "설정의 에이전트 탭에서 AI 사용량을 켜 주세요")
                    .font(model.textFont(size: size * 0.78, weight: .regular))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .frame(height: IslandModel.dashboardUsageHeight)
    }
}
