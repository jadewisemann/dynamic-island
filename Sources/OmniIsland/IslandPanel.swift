import AppKit
import Combine
import SwiftUI

/// Lets the first click on the (never key) panel reach SwiftUI.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless, transparent, click-through panel that sits over the menu bar
/// at the top-center of a screen and hosts the SwiftUI island.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        // Above the menu bar so the island can grow out of the notch.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// True only while the launcher is open, so the panel can take typing
    /// without activating the app (the frontmost app stays frontmost).
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// Borderless windows would otherwise be pushed below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class IslandWindowController {
    /// Room around the island inside the panel for the shadow and the pop effect.
    static let panelMargin: CGFloat = 60
    let model: IslandModel
    private let panel = IslandPanel()
    private var screenObserver: NSObjectProtocol?
    private(set) var screen: NSScreen?
    private var preferredDisplayName: String?
    private var phaseObserver: AnyCancellable?
    private var mouseTimer: Timer?
    private var resignObserver: NSObjectProtocol?
    private var moveMonitors: [Any] = []
    private var dragMonitor: Any?
    private var drag: DragState?
    private var lastEdgeState = false

    private struct DragState {
        let start: NSPoint
        let startOffset: CGPoint
        var moved = false
    }

    init(model: IslandModel) {
        self.model = model
        let host = IslandHostingView(rootView: IslandRootView(model: model))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        phaseObserver = model.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateMouseTracking()
                    self?.updateKeyFocus()
                }
            }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            // Clicked another app or window: the launcher closes.
            MainActor.assumeIsolated {
                guard let self, self.model.phase == .launcher else { return }
                self.model.closeLauncher()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        installPointerMonitors()
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    /// Called when OmniWM reports a different active display (screen = "active").
    func setPreferredDisplay(name: String?) {
        guard name != preferredDisplayName else { return }
        preferredDisplayName = name
        reposition()
    }

    func reposition() {
        let target = chooseScreen()
        screen = target
        guard let target else { return }

        let geometry = Self.notchGeometry(for: target, config: model.config.appearance)
        if geometry != model.geometry { model.geometry = geometry }
        // A drag in progress already holds the offset; otherwise each
        // screen keeps the place it was last dragged to.
        let moved = drag == nil ? Self.savedOffset(for: target) : model.dragOffset
        model.dragOffset = moved

        let maxSize = model.maximumSize
        let margin = Self.panelMargin
        let width = min(maxSize.width + margin * 2, target.frame.width)
        let height = maxSize.height + margin
        let layout = model.config.layout
        let offset = geometry.hasNotch ? 0 : CGFloat(layout.horizontalOffset)
        let edgeInset: CGFloat = 8
        let x: CGFloat
        switch model.horizontalPosition {
        case "left":
            x = target.frame.minX + edgeInset + offset - margin
        case "right":
            x = target.frame.maxX - edgeInset + offset + margin - width
        default:
            x = Self.notchCenterX(for: target) + offset - width / 2
        }
        let frame = NSRect(
            x: x + moved.x,
            y: target.frame.maxY - height - moved.y,
            width: width,
            height: height
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: - Keyboard

    /// Makes the panel key while the launcher is open, and gives the key
    /// back to the app that had it when the launcher closes.
    private func updateKeyFocus() {
        if model.phase == .launcher {
            guard !panel.isKeyWindow else { return }
            panel.allowsKey = true
            panel.becomesKeyOnlyIfNeeded = false
            panel.makeKeyAndOrderFront(nil)
            if let field = Self.find(LauncherTextView.self, in: panel.contentView) {
                panel.makeFirstResponder(field)
            }
        } else if panel.allowsKey {
            panel.allowsKey = false
            panel.becomesKeyOnlyIfNeeded = true
            if panel.isKeyWindow {
                // Ordering out hands the key back to the frontmost app's window.
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
        }
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for sub in view.subviews {
            if let match = find(type, in: sub) { return match }
        }
        return nil
    }

    // MARK: - Clicks

    /// The panel stays click-through except while the workspace row is open
    /// and the mouse is over the island itself, so the transparent margin
    /// around it never swallows clicks meant for the menu bar or windows.
    private func updateMouseTracking() {
        if model.acceptsClicks {
            if mouseTimer == nil {
                let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.trackMouse() }
                }
                RunLoop.main.add(timer, forMode: .common)
                mouseTimer = timer
            }
            trackMouse()
        } else {
            mouseTimer?.invalidate()
            mouseTimer = nil
            panel.ignoresMouseEvents = true
            model.setPointerInside(false)
        }
    }

    private func trackMouse() {
        var zone = islandFrame()
        if model.hoverRevealed, let top = screen?.frame.maxY, top > zone.maxY {
            // Opened from the top edge: the gap above a floating or moved
            // island counts as inside, so the row stays while the pointer
            // travels down to it.
            zone = zone.union(NSRect(x: zone.minX, y: zone.maxY, width: zone.width, height: top - zone.maxY))
        }
        let inside = zone.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        model.setPointerInside(inside)
    }

    /// The island's rectangle in screen coordinates.
    private func islandFrame() -> NSRect {
        let frame = panel.frame
        let size = model.currentSize
        let margin = Self.panelMargin
        let midX: CGFloat
        switch model.horizontalPosition {
        case "left": midX = frame.minX + margin + size.width / 2
        case "right": midX = frame.maxX - margin - size.width / 2
        default: midX = frame.midX + model.panelOffset
        }
        let top = frame.maxY - model.currentTopOffset
        return NSRect(x: midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }

    // MARK: - Top edge and dragging

    /// Height of the strip at the top edge that opens the row.
    static let edgeHeight: CGFloat = 3
    /// Extra width on each side of the hidden island that still counts.
    static let edgeSlack: CGFloat = 24

    private func installPointerMonitors() {
        let moved: NSEvent.EventTypeMask = [.mouseMoved]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { [weak self] _ in
            MainActor.assumeIsolated { () -> Void in self?.pointerMoved() }
        }) {
            moveMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { [weak self] event in
            MainActor.assumeIsolated { () -> Void in self?.pointerMoved() }
            return event
        }) {
            moveMonitors.append(local)
        }
        // Clicks on the panel only reach this app, so a local monitor sees
        // every press on the island before SwiftUI does.
        dragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard let self else { return event }
                return self.handleDrag(event)
            }
        }
    }

    /// The hidden island's rectangle (where the notch shape sits).
    private func hiddenFrame(on target: NSScreen) -> NSRect {
        let frame = panel.frame
        let size = model.hiddenSize
        let margin = Self.panelMargin
        let midX: CGFloat
        switch model.horizontalPosition {
        case "left": midX = frame.minX + margin + size.width / 2
        case "right": midX = frame.maxX - margin - size.width / 2
        default: midX = frame.midX
        }
        return NSRect(x: midX - size.width / 2, y: frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private func pointerMoved() {
        guard let target = screen else { return }
        let location = NSEvent.mouseLocation
        let top = target.frame.maxY
        let hidden = hiddenFrame(on: target)
        let span = hidden.insetBy(dx: -Self.edgeSlack, dy: 0)
        let onScreen = location.x >= target.frame.minX && location.x < target.frame.maxX
        let nearIsland = location.x >= span.minX && location.x <= span.maxX

        if onScreen, location.y >= top - 0.5, blocksMenuBar(on: target, nearIsland: nearIsland) {
            nudgeBelowTopEdge(location, screen: target)
        }

        let atEdge = onScreen && nearIsland && location.y >= top - Self.edgeHeight
        let overHidden = hidden.insetBy(dx: -4, dy: -4).contains(location)
        let state = atEdge || (model.phase == .hidden && overHidden)
        if state != lastEdgeState {
            lastEdgeState = state
            model.pointerAtTopEdge(state)
        }
    }

    private func blocksMenuBar(on target: NSScreen, nearIsland: Bool) -> Bool {
        switch model.config.behavior.blockMenuBar.lowercased() {
        case "screen": return true
        case "island": return nearIsland
        case "virtualnotch", "virtual": return nearIsland && target.safeAreaInsets.top == 0
        default: return false
        }
    }

    /// macOS slides an auto-hidden menu bar down when the pointer rests on
    /// the screen's top row. There is no public API to stop that for other
    /// apps, so the pointer is moved one point down whenever it reaches
    /// that row on the guarded part of the edge.
    private func nudgeBelowTopEdge(_ location: NSPoint, screen target: NSScreen) {
        guard let primary = NSScreen.screens.first else { return }
        let y = primary.frame.maxY - (target.frame.maxY - 1)
        if let source = CGEventSource(stateID: .combinedSessionState) {
            // Otherwise the warp freezes the pointer for a quarter second.
            source.localEventsSuppressionInterval = 0
        }
        CGWarpMouseCursorPosition(CGPoint(x: location.x, y: y))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Option-press on the open island starts a move; a press that does not
    /// travel stays a normal click.
    private func handleDrag(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            drag = nil
            guard event.window === panel,
                  model.config.behavior.dragToMove,
                  model.phase.isModifierPhase,
                  event.modifierFlags.contains(.option) else { return event }
            drag = DragState(start: NSEvent.mouseLocation, startOffset: model.dragOffset)
            return event
        case .leftMouseDragged:
            guard var state = drag, let target = screen else { return event }
            let now = NSEvent.mouseLocation
            let dx = now.x - state.start.x
            let dy = state.start.y - now.y
            if !state.moved {
                guard hypot(dx, dy) > 4 else { return event }
                state.moved = true
                model.suppressTaps = true
            }
            drag = state
            model.dragOffset = clamped(CGPoint(x: state.startOffset.x + dx, y: state.startOffset.y + dy),
                                       on: target)
            reposition()
            return nil
        case .leftMouseUp:
            guard let state = drag else { return event }
            drag = nil
            if state.moved, let target = screen {
                Self.saveOffset(model.dragOffset, for: target)
                // The tap that SwiftUI sees for this release is ignored.
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.model.suppressTaps = false }
                }
            }
            return event
        default:
            return event
        }
    }

    /// Keeps the island's notch-sized core on the screen.
    private func clamped(_ offset: CGPoint, on target: NSScreen) -> CGPoint {
        let hidden = model.hiddenSize
        let base = hiddenFrame(on: target).midX - model.dragOffset.x
        let minX = target.frame.minX + hidden.width / 2 - base
        let maxX = target.frame.maxX - hidden.width / 2 - base
        let maxY = max(target.frame.height - model.currentSize.height - 20, 0)
        return CGPoint(x: min(max(offset.x, minX), maxX), y: min(max(offset.y, 0), maxY))
    }

    /// Puts the island back where it belongs (menu bar item).
    func resetPosition() {
        if let target = screen { Self.saveOffset(.zero, for: target) }
        model.dragOffset = .zero
        reposition()
    }

    private static func offsetKey(for screen: NSScreen) -> String {
        "islandOffset." + screen.localizedName
    }

    static func savedOffset(for screen: NSScreen) -> CGPoint {
        guard let values = UserDefaults.standard.array(forKey: offsetKey(for: screen)) as? [Double],
              values.count == 2 else { return .zero }
        return CGPoint(x: values[0], y: values[1])
    }

    static func saveOffset(_ offset: CGPoint, for screen: NSScreen) {
        if offset == .zero {
            UserDefaults.standard.removeObject(forKey: offsetKey(for: screen))
        } else {
            UserDefaults.standard.set([Double(offset.x), Double(offset.y)], forKey: offsetKey(for: screen))
        }
    }

    private func chooseScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        switch model.config.behavior.screen.lowercased() {
        case "main":
            return screens.first ?? NSScreen.main
        case "active":
            if let name = preferredDisplayName,
               let match = screens.first(where: { $0.localizedName == name }) {
                return match
            }
            return notched ?? screens.first
        default:
            return notched ?? screens.first
        }
    }

    static func notchGeometry(for screen: NSScreen, config: IslandConfig.Appearance) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let width = screen.frame.width - left - right
            if width > 0 {
                return NotchGeometry(width: width, height: top, hasNotch: true)
            }
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let height = menuBar > 4 ? menuBar : CGFloat(config.fallbackNotchHeight)
        return NotchGeometry(width: CGFloat(config.fallbackNotchWidth), height: height, hasNotch: false)
    }

    static func notchCenterX(for screen: NSScreen) -> CGFloat {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - left.width - right.width
            if notchWidth > 0 {
                return screen.frame.minX + left.width + notchWidth / 2
            }
        }
        return screen.frame.midX
    }
}
