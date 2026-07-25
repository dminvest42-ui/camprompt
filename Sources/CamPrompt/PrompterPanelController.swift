import AppKit
import SwiftUI

/// NSPanel that forwards mouse-wheel / trackpad scrolling to the prompter,
/// so the script can be wound back and forth by hand.
final class ScrollForwardingPanel: NSPanel {
    var onScrollDelta: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * 10
        onScrollDelta?(dy)
    }
}

/// Borderless always-on-top NSPanel that hosts the prompter text,
/// pinned right under the MacBook camera notch (or free-floating).
@MainActor
final class PrompterPanelController {
    private var panel: NSPanel?
    private unowned let state: AppState

    init(state: AppState) {
        self.state = state
    }

    /// Screen that physically has a notch (safe area inset at the top), else main.
    static func notchScreen() -> NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let settings = state.settings
        let screen = Self.notchScreen()
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        // Height of the menu-bar strip (the notch lives inside it on notched Macs).
        let menuBarHeight = max(0, screenFrame.maxY - visibleFrame.maxY)
        let pinned = settings.panelPinnedToNotch

        let width = CGFloat(settings.panelWidth)
        let textHeight = CGFloat(settings.panelTextHeight)
        let height = pinned ? menuBarHeight + textHeight : textHeight

        let x = screenFrame.midX - width / 2
        let y = pinned
            ? screenFrame.maxY - height
            : screenFrame.maxY - height - menuBarHeight - 8

        let panel = ScrollForwardingPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let engine = state.engine
        panel.onScrollDelta = { dy in
            // Natural scrolling: fingers down -> back to earlier text.
            engine.jump(by: -dy)
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = !pinned
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = !pinned
        panel.sharingType = settings.hideFromScreenCapture ? .none : .readOnly
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let view = PrompterView(
            state: state,
            settings: settings,
            engine: state.engine,
            topInset: pinned ? menuBarHeight : 0,
            pinned: pinned
        )
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
