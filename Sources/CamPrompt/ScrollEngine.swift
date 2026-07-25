import Foundation
import QuartzCore

/// Drives the prompter scroll offset at ~60 fps.
@MainActor
final class ScrollEngine: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published var isPlaying = false
    @Published var text: String = ""

    /// Total height of the laid-out text, reported by the view.
    var contentHeight: CGFloat = 0
    /// Visible height of the scroll area, reported by the view.
    var viewportHeight: CGFloat = 0

    weak var settings: SettingsStore?

    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.002
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func restart() {
        offset = 0
    }

    func jump(by delta: CGFloat) {
        offset = max(0, offset + delta)
    }

    private func tick() {
        guard isPlaying, let settings else { return }
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        offset += CGFloat(settings.pointsPerSecond * dt)

        let end = max(0, contentHeight)
        if offset > end {
            if settings.loopMode {
                offset = -viewportHeight * 0.5 // brief gap before the loop restarts
            } else {
                offset = end
                pause()
            }
        }
    }
}
