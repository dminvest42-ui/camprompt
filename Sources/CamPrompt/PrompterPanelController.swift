import AppKit
import SwiftUI

/// Edge of the prompter panel that can be dragged to resize it.
enum PanelEdge {
    case left
    case right
    case bottom
}

/// Borderless NSPanel with two extras:
/// - mouse-wheel / trackpad scrolling is forwarded to the prompter, so the
///   script can be wound back and forth by hand;
/// - a thin zone along the left / right / bottom edges resizes the panel by
///   dragging. Handled here, before SwiftUI sees the mouse, so it also works
///   in floating mode where the window is movable by its background.
final class ScrollForwardingPanel: NSPanel {
    var onScrollDelta: ((CGFloat) -> Void)?
    /// (edge, dx, dy — screen points since mouse-down, frame at mouse-down, finished)
    var onEdgeDrag: ((PanelEdge, CGFloat, CGFloat, NSRect, Bool) -> Void)?

    static let resizeMargin: CGFloat = 8

    private var drag: (edge: PanelEdge, start: NSPoint, frame: NSRect)?

    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * 10
        onScrollDelta?(dy)
    }

    /// Edge under a point in window coordinates (origin bottom-left), if any.
    func edge(at point: NSPoint) -> PanelEdge? {
        let m = Self.resizeMargin
        if point.y <= m { return .bottom }
        if point.x <= m { return .left }
        if point.x >= frame.width - m { return .right }
        return nil
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if let hit = edge(at: event.locationInWindow) {
                drag = (edge: hit, start: NSEvent.mouseLocation, frame: frame)
                return
            }
        case .leftMouseDragged:
            if let d = drag {
                let m = NSEvent.mouseLocation
                onEdgeDrag?(d.edge, m.x - d.start.x, m.y - d.start.y, d.frame, false)
                return
            }
        case .leftMouseUp:
            if let d = drag {
                drag = nil
                let m = NSEvent.mouseLocation
                onEdgeDrag?(d.edge, m.x - d.start.x, m.y - d.start.y, d.frame, true)
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// NSHostingView that shows resize cursors over the panel's edge zones.
/// Tracking areas are `activeAlways`, so the cursor changes even though the
/// panel is a non-activating window that never becomes key.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    private var edgeAreas: [NSTrackingArea] = []

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        edgeAreas.forEach(removeTrackingArea)
        let m = ScrollForwardingPanel.resizeMargin
        let b = bounds
        let rects: [NSRect] = [
            NSRect(x: 0, y: 0, width: b.width, height: m),                                  // bottom
            NSRect(x: 0, y: m, width: m, height: max(0, b.height - m)),                     // left
            NSRect(x: max(0, b.width - m), y: m, width: m, height: max(0, b.height - m)),   // right
            b.insetBy(dx: m, dy: m),                                                        // interior → arrow
        ]
        edgeAreas = rects.map {
            NSTrackingArea(rect: $0, options: [.cursorUpdate, .activeAlways], owner: self, userInfo: nil)
        }
        edgeAreas.forEach(addTrackingArea)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let panel = window as? ScrollForwardingPanel else {
            super.cursorUpdate(with: event)
            return
        }
        switch panel.edge(at: event.locationInWindow) {
        case .some(.left), .some(.right):
            NSCursor.resizeLeftRight.set()
        case .some(.bottom):
            NSCursor.resizeUpDown.set()
        case .none:
            NSCursor.arrow.set()
        }
    }
}

/// Borderless always-on-top NSPanel that hosts the prompter text,
/// pinned right under the MacBook camera notch (or free-floating).
@MainActor
final class PrompterPanelController {
    private var panel: ScrollForwardingPanel?
    private unowned let state: AppState

    // Geometry captured when the panel was built (changing these re-creates it).
    private var pinned = true
    private var menuBarHeight: CGFloat = 0
    private var screenFrame: NSRect = .zero

    static let minWidth: CGFloat = 300
    static let minTextHeight: CGFloat = 80
    static let maxTextHeight: CGFloat = 800

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

    /// Re-apply width / text height from settings without recreating the panel
    /// (used by the settings sliders while the panel is on screen).
    func applyGeometry() {
        guard let panel else { return }
        let width = CGFloat(state.settings.panelWidth)
        let textHeight = CGFloat(state.settings.panelTextHeight)
        panel.setFrame(frame(width: width, textHeight: textHeight, current: panel.frame), display: true)
    }

    /// Frame for the given size: pinned → centred under the notch with the top
    /// on the screen edge; floating → keep the panel's current top-left corner.
    private func frame(width: CGFloat, textHeight: CGFloat, current: NSRect) -> NSRect {
        let w = min(max(width, Self.minWidth), screenFrame.width)
        let h = min(max(textHeight, Self.minTextHeight), Self.maxTextHeight) + (pinned ? menuBarHeight : 0)
        if pinned {
            return NSRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
        }
        return NSRect(x: current.minX, y: current.maxY - h, width: w, height: h)
    }

    private func handleEdgeDrag(_ edge: PanelEdge, dx: CGFloat, dy: CGFloat, start: NSRect, finished: Bool) {
        guard let panel else { return }
        let topInset = pinned ? menuBarHeight : 0
        var width = start.width
        var textHeight = start.height - topInset
        switch edge {
        case .right:
            // Pinned: the panel stays centred under the camera, so both edges move.
            width = pinned ? start.width + dx * 2 : start.width + dx
        case .left:
            width = pinned ? start.width - dx * 2 : start.width - dx
        case .bottom:
            textHeight = start.height - topInset - dy   // dy < 0 while dragging down
        }
        let w = min(max(width, Self.minWidth), screenFrame.width)
        let textH = min(max(textHeight, Self.minTextHeight), Self.maxTextHeight)
        var f = start
        f.size = NSSize(width: w, height: textH + topInset)
        if pinned {
            f.origin.x = screenFrame.midX - w / 2
            f.origin.y = screenFrame.maxY - f.height
        } else {
            f.origin.x = edge == .left ? start.maxX - w : start.minX
            f.origin.y = start.maxY - f.height
        }
        panel.setFrame(f, display: true)
        if finished {
            // Persist only at the end: writing settings mid-drag would let the
            // settings popover re-apply geometry under the cursor.
            state.settings.panelWidth = Double(w)
            state.settings.panelTextHeight = Double(textH)
        }
    }

    private func makePanel() -> ScrollForwardingPanel {
        let settings = state.settings
        let screen = Self.notchScreen()
        screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        // Height of the menu-bar strip (the notch lives inside it on notched Macs).
        menuBarHeight = max(0, screenFrame.maxY - visibleFrame.maxY)
        pinned = settings.panelPinnedToNotch

        let width = CGFloat(settings.panelWidth)
        let textHeight = CGFloat(settings.panelTextHeight)
        let height = pinned ? menuBarHeight + textHeight : textHeight
        let initial = NSRect(
            x: screenFrame.midX - width / 2,
            y: pinned
                ? screenFrame.maxY - height
                : screenFrame.maxY - height - menuBarHeight - 8,
            width: width,
            height: height
        )
        let rect = frame(width: width, textHeight: textHeight, current: initial)

        let panel = ScrollForwardingPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let engine = state.engine
        panel.onScrollDelta = { dy in
            // Natural scrolling: fingers down -> back to earlier text.
            engine.jump(by: -dy)
        }
        panel.onEdgeDrag = { [weak self] edge, dx, dy, start, finished in
            self?.handleEdgeDrag(edge, dx: dx, dy: dy, start: start, finished: finished)
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
        panel.contentView = PanelHostingView(rootView: view)
        return panel
    }
}
