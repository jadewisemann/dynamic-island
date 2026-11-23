import AppKit
import SwiftUI

/// Icon for a notification: the sending app's icon, or a bell.
struct NotificationIcon: View {
    let notification: IslandNotification
    let size: CGFloat

    var body: some View {
        if let symbol = notification.symbol, !symbol.isEmpty {
            Image(systemName: symbol)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(Color(hex: notification.tint ?? "", fallback: .white))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .fill(Color(hex: notification.tint ?? "", fallback: .white).opacity(0.16))
                )
        } else if let bundleId = notification.bundleId, !bundleId.isEmpty {
            AppIconView(app: AppRef(name: notification.appName, bundleId: bundleId), size: size)
        } else {
            Image(systemName: notification.source == .calendar ? "calendar" : "bell.fill")
                .font(.system(size: size * 0.6, weight: .semibold))
                .frame(width: size, height: size)
        }
    }
}

/// The expanded card for one macOS notification or calendar alert.
struct NotificationCard: View {
    @ObservedObject var model: IslandModel
    let notification: IslandNotification

    var body: some View {
        let size = CGFloat(model.config.appearance.fontSize)
        let p = model.palette
        let text = model.visibleText(notification)
        HStack(alignment: .top, spacing: 12) {
            NotificationIcon(notification: notification, size: 34)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(header)
                        .font(model.textFont(size: size * 0.75, weight: .medium))
                        .foregroundStyle(p.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !model.notificationQueue.isEmpty {
                        Text("+\(model.notificationQueue.count)")
                            .font(model.numberFont(size: size * 0.72, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(p.fill.opacity(0.16)))
                            .contentTransition(.numericText())
                    }
                    if !model.notificationQueue.isEmpty {
                        CardButton(model: model, label: "모두 닫기", symbol: nil) {
                            model.closeAllNotifications()
                        }
                        .help("기다리는 알림까지 모두 닫습니다")
                    }
                    CardButton(model: model, label: nil, symbol: "xmark") {
                        model.closeNotification()
                    }
                    .help("이 알림 닫기")
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(text.title)
                        .font(model.textFont(size: size + 1, weight: .semibold))
                        .lineLimit(1)
                    if let detail = notification.detail {
                        Spacer(minLength: 4)
                        Text(detail)
                            .font(model.textFont(size: size * 0.8, weight: .regular))
                            .foregroundStyle(p.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                if let body = bodyText(text) {
                    Text(body)
                        .font(model.textFont(size: size * 0.9, weight: .regular))
                        .foregroundStyle(p.text.opacity(0.78))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !notification.actions.isEmpty {
                VStack(spacing: 6) {
                    ForEach(notification.actions) { action in
                        ActionButton(model: model, notification: notification, action: action)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: String {
        var parts = [notification.appName]
        if notification.source == .calendar, let subtitle = notification.subtitle {
            parts.append(subtitle)
        }
        if model.notificationMergeCount > 0 {
            parts.append("새 알림 \(model.notificationMergeCount + 1)개")
        }
        return parts.joined(separator: " · ")
    }

    private func bodyText(_ text: (title: String, subtitle: String?, body: String?)) -> String? {
        // Calendar alerts show "5분 후" in the header instead.
        let subtitle = notification.source == .calendar ? nil : text.subtitle
        let parts = [subtitle, text.body].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }
}

/// Small close button in the card header: a text capsule or an icon circle.
private struct CardButton: View {
    @ObservedObject var model: IslandModel
    let label: String?
    let symbol: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let p = model.palette
        let size = CGFloat(model.config.appearance.fontSize)
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .bold))
                    .frame(width: size * 1.15, height: size * 1.15)
                    .background(Circle().fill(p.fill.opacity(hovering ? 0.28 : 0.14)))
                    .contentShape(Circle())
            } else if let label {
                Text(label)
                    .font(model.textFont(size: size * 0.7, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(p.fill.opacity(hovering ? 0.28 : 0.14)))
                    .contentShape(Capsule())
            }
        }
        .foregroundStyle(hovering ? p.text : p.secondary)
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

/// A capsule button on a notification card.
private struct ActionButton: View {
    @ObservedObject var model: IslandModel
    let notification: IslandNotification
    let action: NotificationAction
    @State private var hovering = false

    var body: some View {
        let p = model.palette
        let size = CGFloat(model.config.appearance.fontSize)
        let fill: Color = {
            switch action.role {
            case .primary: return p.accent
            case .destructive: return Color(hex: "#FF453A", fallback: .red).opacity(0.85)
            case .normal: return p.fill.opacity(0.16)
            }
        }()
        Text(action.label)
            .font(model.textFont(size: size * 0.82, weight: .semibold))
            .foregroundStyle(action.role == .normal ? p.text : Color.white)
            .lineLimit(1)
            .frame(minWidth: 54)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill.opacity(hovering ? 1 : 0.88)))
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .onTapGesture { model.perform(action, on: notification) }
    }
}

/// Small icons of missed notifications on the left of the notch and their
/// count on the right, while the island is hidden.
struct MissedIndicator: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let apps = Array(model.missedApps.prefix(2))
        let p = model.palette
        HStack(spacing: 0) {
            HStack(spacing: -4) {
                ForEach(apps) { n in
                    NotificationIcon(notification: n, size: 15)
                }
            }
            .frame(width: IslandModel.indicatorEarWidth - 6, alignment: .center)
            Spacer(minLength: model.geometry.width)
            Text("\(model.missedNotifications.count)")
                .font(model.numberFont(size: 11, weight: .bold))
                .foregroundStyle(p.badge)
                .contentTransition(.numericText())
                .frame(width: IslandModel.indicatorEarWidth - 6, alignment: .center)
        }
        .padding(.horizontal, 3)
        .foregroundStyle(.white)
    }
}

/// Clock, the rest of today's events and recent notifications.
struct DashboardView: View {
    @ObservedObject var model: IslandModel

    private var items: [String] { model.config.dashboard.items.map { $0.lowercased() } }

    var body: some View {
        let top = items.filter { $0 == "clock" || $0 == "events" }
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(model.palette.fill.opacity(0.1))
                .frame(height: 1)
            if !top.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(top, id: \.self) { item in
                        if item == "clock" {
                            clock
                        } else {
                            events
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            if items.contains("usage") {
                UsageDashboardRow(model: model)
            }
            if items.contains("notifications") {
                recent
            }
        }
        .padding(.bottom, 10)
    }

    private var clock: some View {
        let size = CGFloat(model.config.appearance.fontSize)
        return VStack(alignment: .leading, spacing: 4) {
            ClockText(template: ClockText.template(for: model.config.widgets.clockFormat),
                      font: model.numberFont(size: size * 2.2, weight: .semibold), color: model.palette.text)
            ClockText(template: "MMMdEEEE", font: model.textFont(size: size * 0.8, weight: .regular),
                      color: model.palette.secondary)
        }
        .fixedSize()
    }

    @ViewBuilder private var events: some View {
        let size = CGFloat(model.config.appearance.fontSize)
        let p = model.palette
        let list = Array(model.remainingTodayEvents.prefix(3))
        VStack(alignment: .leading, spacing: 4) {
            if !model.config.calendar.enabled {
                placeholder("설정의 위젯 탭에서 캘린더를 켜면 오늘 일정이 보입니다.")
            } else if list.isEmpty {
                placeholder("오늘 남은 일정이 없습니다.")
            } else {
                ForEach(list) { event in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: event.colorHex ?? "", fallback: p.accent))
                            .frame(width: 3, height: size * 1.1)
                        Text(time(event))
                            .font(model.textFont(size: size * 0.8, weight: .medium))
                            .foregroundStyle(event.isOngoing() ? p.accent : p.secondary)
                            .monospacedDigit()
                            .frame(width: size * 3.3, alignment: .leading)
                        Text(event.title)
                            .font(model.textFont(size: size * 0.85, weight: .regular))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The last few notifications, newest first; a row opens its app.
    @ViewBuilder private var recent: some View {
        let size = CGFloat(model.config.appearance.fontSize)
        let p = model.palette
        let list = Array(model.recentNotifications.prefix(IslandModel.dashboardHistoryRows))
        if list.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "bell.slash")
                    .font(.system(size: size * 0.75))
                Text("최근 알림이 없습니다")
                    .font(model.textFont(size: size * 0.78, weight: .regular))
            }
            .foregroundStyle(p.secondary)
            .frame(height: IslandModel.dashboardRowHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(list) { n in
                    historyRow(n, size: size)
                }
            }
        }
    }

    private func historyRow(_ n: IslandNotification, size: CGFloat) -> some View {
        let p = model.palette
        let text = model.visibleText(n)
        let detail = [text.subtitle, text.body].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 6) {
            NotificationIcon(notification: n, size: 15)
            Text(text.title)
                .font(model.textFont(size: size * 0.8, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)
            if !detail.isEmpty {
                Text(detail)
                    .font(model.textFont(size: size * 0.78, weight: .regular))
                    .foregroundStyle(p.text.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(relative(n.date))
                .font(model.textFont(size: size * 0.72, weight: .regular))
                .foregroundStyle(p.secondary)
                .fixedSize()
        }
        .frame(height: IslandModel.dashboardRowHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.open(n) }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(model.textFont(size: CGFloat(model.config.appearance.fontSize) * 0.8, weight: .regular))
            .foregroundStyle(model.palette.secondary)
            .lineLimit(2)
    }

    private func time(_ event: CalendarEvent) -> String {
        if event.isOngoing() { return "진행 중" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("HHmm")
        return f.string(from: event.start)
    }

    private func relative(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "방금" }
        if minutes < 60 { return "\(minutes)분 전" }
        return "\(minutes / 60)시간 전"
    }
}
