import AppKit
import SwiftUI

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
    let model: IslandModel
    private let panel = IslandPanel()
    private var screenObserver: NSObjectProtocol?
    private(set) var screen: NSScreen?
    private var preferredDisplayName: String?

    init(model: IslandModel) {
        self.model = model
        let host = NSHostingView(rootView: IslandRootView(model: model))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
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
        let margin: CGFloat = 60 // room for the shadow and the pop effect
        let width = min(maxSize.width + margin * 2, target.frame.width)
        let height = maxSize.height + margin
        let centerX = Self.notchCenterX(for: target)
        let frame = NSRect(
            x: centerX - width / 2,
            y: target.frame.maxY - height,
            width: width,
            height: height
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
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
