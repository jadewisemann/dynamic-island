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

    override var canBecomeKey: Bool { false }
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

    init(model: IslandModel) {
        self.model = model
        let host = IslandHostingView(rootView: IslandRootView(model: model))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        phaseObserver = model.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMouseTracking() }
            }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
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
            x: x,
            y: target.frame.maxY - height,
            width: width,
            height: height
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
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
        let inside = islandFrame().insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
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
