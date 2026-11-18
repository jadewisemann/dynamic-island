import AppKit
import EventKit

/// One calendar event, copied out of EventKit so SwiftUI can compare it.
struct CalendarEvent: Identifiable, Equatable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var calendarTitle: String
    /// Calendar color as `#RRGGBB`.
    var colorHex: String?

    func isOngoing(at now: Date = Date()) -> Bool { start <= now && now < end }
}

/// Reads today's and tomorrow's events with EventKit and raises an alert a few
/// minutes before each one starts.
///
/// Needs the "Full Access" calendar permission (macOS 14+). Access is only
/// requested when the calendar feature is turned on.
@MainActor
final class CalendarProvider {
    enum Access: Equatable {
        case notDetermined, granted, denied
    }

    var onChange: (([CalendarEvent]) -> Void)?
    /// An event is about to start; the Int is the minutes before its start.
    var onAlert: ((CalendarEvent, Int) -> Void)?
    var onAccessChange: ((Access) -> Void)?

    private(set) var events: [CalendarEvent] = []
    private(set) var access: Access = CalendarProvider.currentAccess()

    private let store = EKEventStore()
    private var enabled = false
    private var calendarFilter: [String] = []
    private var alertMinutes: [Int] = [5, 0]
    private var includeAllDay = false
    private var tickTimer: Timer?
    private var lastRefresh = Date.distantPast
    private var firedAlerts: Set<String> = []
    private var storeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// - Parameters:
    ///   - calendars: calendar titles or identifiers to include; empty means all.
    ///   - alertMinutes: alert this many minutes before each start (0 = at start).
    func configure(enabled: Bool, calendars: [String], alertMinutes: [Int], includeAllDay: Bool) {
        let changed = enabled != self.enabled || calendars != calendarFilter || includeAllDay != self.includeAllDay
        self.enabled = enabled
        calendarFilter = calendars
        self.alertMinutes = Array(Set(alertMinutes.filter { $0 >= 0 })).sorted(by: >)
        self.includeAllDay = includeAllDay
        guard enabled else {
            stopTimers()
            publish([])
            return
        }
        startTimers()
        if access == .notDetermined {
            requestAccess()
        } else if changed {
            refresh()
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.access = Self.currentAccess()
                    self.onAccessChange?(self.access)
                    self.refresh()
                }
            }
        }
    }

    /// The next event that has not ended yet (ongoing events included).
    func nextEvent(after now: Date = Date()) -> CalendarEvent? {
        events.first { !$0.isAllDay && $0.end > now }
    }

    /// Events still to come today (ongoing ones included).
    func remainingToday(now: Date = Date()) -> [CalendarEvent] {
        let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        return events.filter { $0.end > now && $0.start < endOfDay }
    }

    func refresh() {
        lastRefresh = Date()
        access = Self.currentAccess()
        guard enabled, access == .granted else {
            publish([])
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = start.addingTimeInterval(2 * 86_400)
        let calendars = selectedCalendars()
        guard calendars == nil || !(calendars!.isEmpty) else {
            publish([])
            return
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let result = store.events(matching: predicate)
            .filter { includeAllDay || !$0.isAllDay }
            .filter { !Self.isDeclined($0) && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map(Self.makeEvent)
        publish(result)
    }

    // MARK: - Private

    private func selectedCalendars() -> [EKCalendar]? {
        guard !calendarFilter.isEmpty else { return nil }
        let wanted = Set(calendarFilter.map { $0.lowercased() })
        return store.calendars(for: .event).filter {
            wanted.contains($0.title.lowercased()) || wanted.contains($0.calendarIdentifier.lowercased())
        }
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        guard let me = event.attendees?.first(where: \.isCurrentUser) else { return false }
        return me.participantStatus == .declined
    }

    private static func makeEvent(_ event: EKEvent) -> CalendarEvent {
        let start = event.startDate ?? Date()
        let id = (event.eventIdentifier ?? event.calendarItemIdentifier) + "@\(Int(start.timeIntervalSince1970))"
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let color: NSColor? = event.calendar?.color
        return CalendarEvent(
            id: id,
            title: event.title?.isEmpty == false ? event.title! : "(제목 없음)",
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            location: location?.isEmpty == false ? location : nil,
            calendarTitle: event.calendar?.title ?? "",
            colorHex: color.flatMap(hex)
        )
    }

    private static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func publish(_ result: [CalendarEvent]) {
        guard result != events else { return }
        events = result
        let live = Set(result.map(\.id))
        firedAlerts = firedAlerts.filter { key in live.contains { key.hasPrefix($0) } }
        onChange?(result)
    }

    private func startTimers() {
        if tickTimer == nil {
            let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 2
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        }
        if storeObserver == nil {
            storeObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    private func stopTimers() {
        tickTimer?.invalidate()
        tickTimer = nil
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        storeObserver = nil
        wakeObserver = nil
    }

    private func tick() {
        let now = Date()
        // Pick up the new day and events added on other devices.
        if now.timeIntervalSince(lastRefresh) > 300
            || !Calendar.current.isDate(now, inSameDayAs: lastRefresh) {
            refresh()
        }
        guard access == .granted else { return }
        for event in events where !event.isAllDay {
            for minutes in alertMinutes {
                let due = event.start.addingTimeInterval(-Double(minutes) * 60)
                // Only alert inside a one-minute window, so waking from sleep
                // does not replay alerts that are long past.
                guard now >= due, now < due.addingTimeInterval(60) else { continue }
                let key = "\(event.id)#\(minutes)"
                guard !firedAlerts.contains(key) else { continue }
                firedAlerts.insert(key)
                onAlert?(event, minutes)
            }
        }
    }
}

extension CalendarEvent {
    /// "14:00–14:30" in the user's locale.
    var timeRangeText: String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return isAllDay ? "종일" : "\(f.string(from: start))–\(f.string(from: end))"
    }

    /// Converts an alert into the island's notification card.
    func alertNotification(minutesBefore: Int) -> IslandNotification {
        let when = minutesBefore == 0 ? "지금 시작" : "\(minutesBefore)분 후"
        return IslandNotification(
            source: .calendar,
            appName: calendarTitle.isEmpty ? "캘린더" : "캘린더 · \(calendarTitle)",
            bundleId: "com.apple.ical",
            title: title,
            subtitle: when,
            body: location,
            detail: timeRangeText
        )
    }
}
