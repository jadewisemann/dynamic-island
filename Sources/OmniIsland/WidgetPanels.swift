import SwiftUI

/// Square widget tiles attached to one side of the island (widgets.leftPanel
/// / rightPanel). Each side is sized on its own; its widgets share it.
struct SidePanel: View {
    @ObservedObject var model: IslandModel
    let items: [String]
    let edge: HorizontalEdge

    var body: some View {
        let divider = model.palette.fill.opacity(0.1)
        // Keep content clear of the concave shoulders at the outer top corner.
        let shoulder = model.isFloating ? 0 : CGFloat(model.config.appearance.topCornerRadius)
        // As a separate liquid drop the panel has shoulders on both sides
        // and needs no divider against the island.
        let liquid = model.usesLiquid
        HStack(spacing: 0) {
            if edge == .trailing && !liquid { divider.frame(width: 1).padding(.vertical, 10) }
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { divider.frame(width: 1).padding(.vertical, 12) }
                    WidgetTile(model: model, kind: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(liquid ? Edge.Set.horizontal : (edge == .leading ? Edge.Set.leading : Edge.Set.trailing), shoulder)
            if edge == .leading && !liquid { divider.frame(width: 1).padding(.vertical, 10) }
        }
    }
}

/// One widget inside a side panel. Lays itself out for a square tile or,
/// when it has at least 1.5 squares of width, a wide tile.
struct WidgetTile: View {
    @ObservedObject var model: IslandModel
    let kind: String

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= model.panelUnit * 1.5
            let unit = min(proxy.size.height, model.panelUnit)
            content(wide: wide, unit: unit)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(8)
    }

    @ViewBuilder private func content(wide: Bool, unit: CGFloat) -> some View {
        switch kind.lowercased() {
        case "clock": ClockTile(model: model, wide: wide, unit: unit)
        case "calendar": CalendarTile(model: model, wide: wide, unit: unit)
        case "nextevent": NextEventTile(model: model, wide: wide, unit: unit)
        case "events":
            if wide {
                EventsTile(model: model, unit: unit)
            } else {
                NextEventTile(model: model, wide: false, unit: unit)
            }
        case "notifications": NotificationsTile(model: model, wide: wide, unit: unit)
        case "agents": AgentsTile(model: model, wide: wide, unit: unit)
        case "usage": UsageTile(model: model, wide: wide, unit: unit)
        default: EmptyView()
        }
    }
}

private func formatted(_ date: Date, _ template: String) -> String {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate(template)
    return f.string(from: date)
}

private struct ClockTile: View {
    @ObservedObject var model: IslandModel
    let wide: Bool
    let unit: CGFloat

    var body: some View {
        let p = model.palette
        let template = ClockText.template(for: model.config.widgets.clockFormat)
        let seconds = template.contains("ss")
        TimelineView(.periodic(from: .now, by: seconds ? 1 : 5)) { context in
            VStack(spacing: unit * 0.06) {
                Text(formatted(context.date, template))
                    .font(model.numberFont(size: unit * (wide ? 0.42 : (seconds ? 0.24 : 0.32)), weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(formatted(context.date, wide ? "MMMMdEEEE" : "MMMdE"))
                    .font(model.textFont(size: unit * 0.14, weight: .regular))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// Square: "11월 / 18 / next event". Wide: two-week calendar.
private struct CalendarTile: View {
    @ObservedObject var model: IslandModel
    let wide: Bool
    let unit: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if wide {
                twoWeeks(now: context.date)
            } else {
                square(now: context.date)
            }
        }
    }

    private func square(now: Date) -> some View {
        let p = model.palette
        return VStack(spacing: unit * 0.02) {
            Text(formatted(now, "MMM").uppercased())
                .font(model.textFont(size: unit * 0.13, weight: .bold))
                .foregroundStyle(p.badge)
            Text(formatted(now, "d"))
                .font(model.numberFont(size: unit * 0.34, weight: .semibold))
                .monospacedDigit()
            if let event = model.nextEvent {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(hex: event.colorHex ?? "", fallback: p.accent))
                        .frame(width: 4, height: 4)
                    Text("\(formatted(event.start, "HHmm")) \(event.title)")
                        .lineLimit(1)
                }
                .font(model.textFont(size: unit * 0.12, weight: .regular))
                .foregroundStyle(p.secondary)
            }
        }
    }

    private func twoWeeks(now: Date) -> some View {
        let p = model.palette
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        let days = (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let symbols = calendar.veryShortWeekdaySymbols
        let ordered = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
        let eventDays = Set(model.calendarEvents.map { calendar.startOfDay(for: $0.start) })
        let cell = unit * 0.15
        let columns = Array(repeating: GridItem(.fixed(cell), spacing: 2), count: 7)
        return VStack(spacing: unit * 0.03) {
            Text(formatted(now, "MMMM"))
                .font(model.textFont(size: unit * 0.12, weight: .bold))
                .foregroundStyle(p.badge)
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(model.textFont(size: cell * 0.6, weight: .medium))
                        .foregroundStyle(p.secondary)
                }
                ForEach(days, id: \.self) { day in
                    let isToday = day == today
                    ZStack {
                        if isToday { Circle().fill(p.badge) }
                        Text(formatted(day, "d"))
                            .font(model.numberFont(size: cell * 0.6, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? p.badgeText : (day < today ? p.secondary : p.text))
                    }
                    .frame(width: cell, height: cell)
                    .overlay(alignment: .bottom) {
                        if eventDays.contains(day) && !isToday {
                            Circle().fill(p.accent).frame(width: 2.5, height: 2.5).offset(y: 1.5)
                        }
                    }
                }
            }
        }
    }
}

private struct NextEventTile: View {
    @ObservedObject var model: IslandModel
    let wide: Bool
    let unit: CGFloat

    var body: some View {
        let p = model.palette
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let event = model.nextEvent {
                VStack(alignment: wide ? .leading : .center, spacing: unit * 0.04) {
                    Text(NextEventText.relative(event, now: context.date) == "진행 중"
                         ? "진행 중" : formatted(event.start, "HHmm"))
                        .font(model.numberFont(size: unit * 0.26, weight: .semibold))
                        .foregroundStyle(event.isOngoing(at: context.date) ? p.accent : p.text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(event.title)
                        .font(model.textFont(size: unit * 0.14, weight: .medium))
                        .lineLimit(wide ? 1 : 2)
                        .multilineTextAlignment(wide ? .leading : .center)
                    if wide, let location = event.location {
                        Text(location)
                            .font(model.textFont(size: unit * 0.12, weight: .regular))
                            .foregroundStyle(p.secondary)
                            .lineLimit(1)
                    } else if !event.isOngoing(at: context.date) {
                        Text("\(NextEventText.relative(event, now: context.date)) 후")
                            .font(model.textFont(size: unit * 0.12, weight: .regular))
                            .foregroundStyle(p.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: wide ? .leading : .center)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: unit * 0.22))
            Text(model.config.calendar.enabled ? "일정 없음" : "캘린더 꺼짐")
                .font(model.textFont(size: unit * 0.12, weight: .regular))
                .lineLimit(1)
        }
        .foregroundStyle(model.palette.secondary)
    }
}

private struct EventsTile: View {
    @ObservedObject var model: IslandModel
    let unit: CGFloat

    var body: some View {
        let p = model.palette
        let list = Array(model.remainingTodayEvents.prefix(3))
        if list.isEmpty {
            Text(model.config.calendar.enabled ? "오늘 남은 일정이 없습니다" : "캘린더가 꺼져 있습니다")
                .font(model.textFont(size: unit * 0.13, weight: .regular))
                .foregroundStyle(p.secondary)
                .multilineTextAlignment(.center)
        } else {
            VStack(alignment: .leading, spacing: unit * 0.06) {
                ForEach(list) { event in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: event.colorHex ?? "", fallback: p.accent))
                            .frame(width: 3, height: unit * 0.17)
                        Text(event.isOngoing() ? "지금" : formatted(event.start, "HHmm"))
                            .font(model.textFont(size: unit * 0.13, weight: .medium))
                            .foregroundStyle(event.isOngoing() ? p.accent : p.secondary)
                            .monospacedDigit()
                            .frame(width: unit * 0.5, alignment: .leading)
                        Text(event.title)
                            .font(model.textFont(size: unit * 0.14, weight: .regular))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NotificationsTile: View {
    @ObservedObject var model: IslandModel
    let wide: Bool
    let unit: CGFloat

    var body: some View {
        let p = model.palette
        let recent = model.recentNotifications
        if recent.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "bell.slash")
                    .font(.system(size: unit * 0.22))
                Text("알림 없음")
                    .font(model.textFont(size: unit * 0.12, weight: .regular))
            }
            .foregroundStyle(p.secondary)
        } else if wide {
            VStack(alignment: .leading, spacing: unit * 0.08) {
                ForEach(Array(recent.prefix(2))) { n in
                    HStack(spacing: 6) {
                        NotificationIcon(notification: n, size: unit * 0.24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(model.visibleText(n).title)
                                .font(model.textFont(size: unit * 0.14, weight: .medium))
                                .lineLimit(1)
                            Text("\(n.appName) · \(formatted(n.date, "HHmm"))")
                                .font(model.textFont(size: unit * 0.11, weight: .regular))
                                .foregroundStyle(p.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: unit * 0.08) {
                HStack(spacing: -unit * 0.05) {
                    ForEach(Array(recent.prefix(3))) { n in
                        NotificationIcon(notification: n, size: unit * 0.24)
                    }
                }
                Text("알림 \(model.missedNotifications.isEmpty ? recent.count : model.missedNotifications.count)")
                    .font(model.textFont(size: unit * 0.12, weight: .regular))
                    .foregroundStyle(p.secondary)
            }
        }
    }
}

/// Coding agent sessions: their state and project; a row opens its terminal.
private struct AgentsTile: View {
    @ObservedObject var model: IslandModel
    let wide: Bool
    let unit: CGFloat

    var body: some View {
        let p = model.palette
        let sessions = model.agentSessions
        if sessions.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: unit * 0.22))
                Text("에이전트 없음")
                    .font(model.textFont(size: unit * 0.12, weight: .regular))
            }
            .foregroundStyle(p.secondary)
        } else if wide {
            VStack(alignment: .leading, spacing: unit * 0.07) {
                ForEach(Array(sessions.prefix(3))) { s in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: s.state.color, fallback: p.accent))
                            .frame(width: unit * 0.07, height: unit * 0.07)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.project)
                                .font(model.textFont(size: unit * 0.14, weight: .medium))
                                .lineLimit(1)
                            Text(s.detail.map { "\(s.state.label) · \($0)" } ?? s.state.label)
                                .font(model.textFont(size: unit * 0.11, weight: .regular))
                                .foregroundStyle(p.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.openAgent(s) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let top = AgentSession.mostUrgent(sessions) {
            VStack(spacing: unit * 0.06) {
                HStack(spacing: 3) {
                    ForEach(Array(sessions.prefix(4))) { s in
                        Circle()
                            .fill(Color(hex: s.state.color, fallback: p.accent))
                            .frame(width: unit * 0.09, height: unit * 0.09)
                    }
                }
                Text(top.project)
                    .font(model.textFont(size: unit * 0.13, weight: .medium))
                    .lineLimit(1)
                Text(top.state.label)
                    .font(model.textFont(size: unit * 0.11, weight: .regular))
                    .foregroundStyle(Color(hex: top.state.color, fallback: p.secondary))
            }
            .contentShape(Rectangle())
            .onTapGesture { model.openAgent(top) }
        }
    }
}
