import SwiftUI
import AppKit

/// Central coordinator: owns the sub-stores and drives the record flow
/// (countdown -> start capture + start scroll -> stop -> save).
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let settings = SettingsStore()
    let scripts = ScriptStore()
    let engine = ScrollEngine()
    let capture = CaptureManager()
    let recordings = RecordingsStore()

    private var panelController: PrompterPanelController?

    enum RecordingState: Equatable {
        case idle
        case countingDown(Int)
        case recording
    }

    @Published var recordingState: RecordingState = .idle
    @Published var panelVisible = false
    @Published var recordingSeconds: Int = 0

    private var countdownTimer: Timer?
    private var recordingTimer: Timer?

    private init() {
        engine.settings = settings
        capture.settings = settings
        capture.onRecordingFinished = { [weak self] url, error in
            Task { @MainActor in
                self?.recordings.refresh()
                if let error {
                    self?.capture.lastError = "Ошибка сохранения записи: \(error.localizedDescription)"
                } else if let url {
                    self?.recordings.lastRecordingURL = url
                }
            }
        }
    }

    // MARK: - Prompter panel

    func togglePanel() {
        if panelVisible { hidePanel() } else { showPanel() }
    }

    func showPanel() {
        if panelController == nil {
            panelController = PrompterPanelController(state: self)
        }
        engine.text = scripts.selectedScript?.text ?? ""
        panelController?.show()
        panelVisible = true
    }

    func hidePanel() {
        panelController?.hide()
        panelVisible = false
        engine.pause()
    }

    /// Re-create the panel when geometry-affecting settings change.
    func reloadPanelIfVisible() {
        guard panelVisible else { return }
        panelController?.hide()
        panelController = PrompterPanelController(state: self)
        panelController?.show()
    }

    // MARK: - Recording flow

    func toggleRecording() {
        switch recordingState {
        case .idle:
            startRecordingFlow()
        case .countingDown:
            cancelCountdown()
        case .recording:
            stopRecordingFlow()
        }
    }

    private func startRecordingFlow() {
        guard capture.isSessionRunning else {
            capture.lastError = "Сначала включите камеру."
            return
        }
        engine.text = scripts.selectedScript?.text ?? ""
        if !panelVisible && settings.showPanelOnRecord {
            showPanel()
        }
        let n = settings.countdownSeconds
        if n <= 0 {
            beginRecording()
            return
        }
        recordingState = .countingDown(n)
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                if case .countingDown(let value) = self.recordingState {
                    if value <= 1 {
                        timer.invalidate()
                        self.beginRecording()
                    } else {
                        self.recordingState = .countingDown(value - 1)
                    }
                }
            }
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        recordingState = .idle
    }

    private func beginRecording() {
        recordingState = .recording
        recordingSeconds = 0
        capture.startRecording()
        engine.restart()
        engine.play()
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.recordingState == .recording else { return }
                self.recordingSeconds += 1
            }
        }
    }

    private func stopRecordingFlow() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        capture.stopRecording()
        engine.pause()
        recordingState = .idle
    }

    // MARK: - Keyboard

    /// Local key handler. Returns true when the event was consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        // Never steal keystrokes from text editing.
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
            return false
        }
        // Only react when the prompter panel is visible or we are recording.
        guard panelVisible || recordingState != .idle else { return false }
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty == false {
            return false
        }
        switch event.keyCode {
        case 49: // Space
            engine.togglePlay()
            return true
        case 15: // R
            engine.restart()
            return true
        case 53: // Esc
            hidePanel()
            return true
        case 126: // Up — faster
            settings.speed = min(100, settings.speed + 5)
            return true
        case 125: // Down — slower
            settings.speed = max(1, settings.speed - 5)
            return true
        case 123: // Left — jump back
            engine.jump(by: -150)
            return true
        case 124: // Right — jump forward
            engine.jump(by: 150)
            return true
        default:
            return false
        }
    }
}
