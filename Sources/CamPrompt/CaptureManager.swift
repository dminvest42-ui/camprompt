import Foundation
import AVFoundation
import AppKit
import CoreMedia
import os
import ObjCExceptionCatcher

private let log = Logger(subsystem: "ru.olya.camprompt", category: "capture")

/// Owns the AVCaptureSession: device discovery, preview, movie recording.
/// The session is configured on a private serial queue; all @Published
/// state is mutated on the main thread.
final class CaptureManager: NSObject, ObservableObject, @unchecked Sendable {
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var cameras: [AVCaptureDevice] = []
    @Published var microphones: [AVCaptureDevice] = []
    @Published var lastError: String?
    @Published var permissionDenied = false
    /// What the session actually delivers (camera, resolution, preset) —
    /// shown in the camera settings so a black preview is explainable.
    @Published var activeFormatInfo: String = "—"
    /// What the current / last recording was actually told to use.
    @Published var recordingFormatInfo: String = "—"
    /// Measured result of the last finished recording (size, length, rate).
    @Published var lastRecordingStats: String?

    weak var settings: SettingsStore?
    var onRecordingFinished: ((URL?, Error?) -> Void)?

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "ru.olya.camprompt.session")
    private var currentVideoInput: AVCaptureDeviceInput?
    private var currentAudioInput: AVCaptureDeviceInput?
    /// Notes from the last configure pass, for the diagnostics report.
    private var lastConfigureNotes: [String] = []

    static var recordingsDirectory: URL {
        let choice = UserDefaults.standard.string(forKey: "recordingsFolder") ?? "downloads"
        let base: FileManager.SearchPathDirectory
        switch choice {
        case "documents": base = .documentDirectory
        case "movies": base = .moviesDirectory
        default: base = .downloadsDirectory
        }
        let root = FileManager.default.urls(for: base, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent("Teleprompter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Discovery (main thread)

    @MainActor
    func refreshDevices() {
        let videoDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        cameras = videoDiscovery.devices
        let audioDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        microphones = audioDiscovery.devices
    }

    @MainActor
    private func cameraDevice() -> AVCaptureDevice? {
        if let id = settings?.selectedCameraID, !id.isEmpty,
           let d = cameras.first(where: { $0.uniqueID == id }) {
            return d
        }
        // Prefer the built-in FaceTime camera (it sits in the notch).
        return cameras.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? cameras.first
    }

    @MainActor
    private func micDevice() -> AVCaptureDevice? {
        if let id = settings?.selectedMicID, !id.isEmpty,
           let d = microphones.first(where: { $0.uniqueID == id }) {
            return d
        }
        return AVCaptureDevice.default(for: .audio) ?? microphones.first
    }

    // MARK: - Format helpers

    private static func dimensions(of format: AVCaptureDevice.Format) -> (Int, Int) {
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return (Int(d.width), Int(d.height))
    }

    private static func maxResolution(of device: AVCaptureDevice) -> String {
        let dims = device.formats.map { CaptureManager.dimensions(of: $0) }
        guard let best = dims.max(by: { $0.0 * $0.1 < $1.0 * $1.1 }) else { return "?" }
        return "\(best.0)×\(best.1)"
    }

    private static func presetName(_ preset: AVCaptureSession.Preset) -> String {
        preset.rawValue.replacingOccurrences(of: "AVCaptureSessionPreset", with: "")
    }

    // MARK: - Session lifecycle

    @MainActor
    func startCamera() {
        lastError = nil
        Task { @MainActor in
            let cam = await AVCaptureDevice.requestAccess(for: .video)
            let mic = await AVCaptureDevice.requestAccess(for: .audio)
            guard cam else {
                self.permissionDenied = true
                self.lastError = "Нет доступа к камере. Разрешите в Системных настройках → Конфиденциальность и безопасность → Камера."
                return
            }
            if !mic {
                self.lastError = "Нет доступа к микрофону — видео запишется без звука. Разрешить: Системные настройки → Конфиденциальность."
            }
            self.permissionDenied = false
            self.refreshDevices()
            guard let camera = self.cameraDevice() else {
                self.lastError = "Камера не найдена."
                return
            }
            log.info("startCamera: \(camera.localizedName, privacy: .public), cameras found: \(self.cameras.count)")
            let micDevice = mic ? self.micDevice() : nil
            self.configureAndStart(camera: camera, mic: micDevice)
        }
    }

    private func configureAndStart(camera: AVCaptureDevice, mic: AVCaptureDevice?) {
        sessionQueue.async { [self] in
            var notes: [String] = []
            session.beginConfiguration()
            // Start from the universal preset. 1080p is applied only AFTER the
            // inputs are in place: with no inputs every preset looks "supported",
            // and a camera that cannot do 1080p (720p FaceTime HD on MacBook Air
            // M1 / 13" MacBook Pro) is then silently rejected by canAddInput —
            // black preview and audio-only recordings.
            session.sessionPreset = .high

            if let old = currentVideoInput { session.removeInput(old); currentVideoInput = nil }
            if let old = currentAudioInput { session.removeInput(old); currentAudioInput = nil }

            var failure: String?
            do {
                let videoInput = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                    currentVideoInput = videoInput
                    notes.append("video input added: \(camera.localizedName)")
                } else {
                    failure = "Камера «\(camera.localizedName)» не подключается к сессии записи. Выберите другую камеру в настройках (Камера → Камера)."
                    notes.append("canAddInput=false for \(camera.localizedName)")
                }
            } catch {
                failure = "Не удалось открыть камеру «\(camera.localizedName)»: \(error.localizedDescription)"
                notes.append("video input error: \(error.localizedDescription)")
            }

            if let mic {
                do {
                    let audioInput = try AVCaptureDeviceInput(device: mic)
                    if session.canAddInput(audioInput) {
                        session.addInput(audioInput)
                        currentAudioInput = audioInput
                        notes.append("audio input added: \(mic.localizedName)")
                    } else {
                        notes.append("canAddInput=false for mic \(mic.localizedName)")
                    }
                } catch {
                    // A broken microphone must not take the video down with it.
                    notes.append("audio input error: \(error.localizedDescription)")
                }
            }

            if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            if currentVideoInput != nil, session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            }
            notes.append("preset: \(CaptureManager.presetName(session.sessionPreset))")
            session.commitConfiguration()

            if let failure {
                if session.isRunning { session.stopRunning() }
                log.error("configure failed: \(failure, privacy: .public)")
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                    self.activeFormatInfo = "—"
                    self.lastError = failure
                    self.lastConfigureNotes = notes
                }
                return
            }

            if !session.isRunning { session.startRunning() }

            let videoConnection = movieOutput.connection(with: .video)
            let videoActive = videoConnection?.isActive ?? false
            notes.append("video connection: \(videoConnection == nil ? "none" : (videoActive ? "active" : "inactive"))")
            let dims = CaptureManager.dimensions(of: camera.activeFormat)
            let info = "\(camera.localizedName) · \(dims.0)×\(dims.1) · \(CaptureManager.presetName(session.sessionPreset))"
            log.info("session running: \(info, privacy: .public)")
            for note in notes { log.info("\(note, privacy: .public)") }

            DispatchQueue.main.async {
                self.isSessionRunning = true
                self.activeFormatInfo = info
                self.lastConfigureNotes = notes
                if !videoActive {
                    self.lastError = "Камера «\(camera.localizedName)» запущена, но видеосигнал не идёт. Выберите другую камеру или переподключите её."
                }
            }
        }
    }

    @MainActor
    func stopCamera() {
        if isRecording { stopRecording() }
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async {
                self.isSessionRunning = false
                self.activeFormatInfo = "—"
            }
        }
    }

    /// Re-apply device selection from settings (called when pickers change).
    /// If the session is not running (e.g. the previous camera failed), a
    /// fresh start with the newly selected device is attempted instead.
    @MainActor
    func applyDeviceSelection() {
        guard isSessionRunning else {
            startCamera()
            return
        }
        guard let camera = cameraDevice() else { return }
        lastError = nil
        configureAndStart(camera: camera, mic: micDevice())
    }

    func shutdown() {
        sessionQueue.sync { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Recording

    /// Returns false (and sets `lastError`) when the session has no live video
    /// connection — then nothing is written at all instead of an audio-only file.
    @MainActor
    @discardableResult
    func startRecording() -> Bool {
        guard isSessionRunning, !isRecording else { return false }
        guard let connection = movieOutput.connection(with: .video), connection.isActive else {
            lastError = "Нет видеосигнала с камеры — запись не начата. Выберите другую камеру в настройках (Камера → Камера)."
            log.error("startRecording refused: no active video connection")
            return false
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = Self.recordingsDirectory
            .appendingPathComponent("CamPrompt_\(formatter.string(from: Date())).mov")
        let quality = RecordingQuality(rawValue: settings?.recordingQuality ?? "") ?? .standard
        isRecording = true
        sessionQueue.async { [self] in
            let applied = applyOutputSettings(quality)
            log.info("recording with: \(applied, privacy: .public)")
            DispatchQueue.main.async { self.recordingFormatInfo = applied }
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
        return true
    }

    /// Sets codec + bitrate on the video connection, trying the preferred
    /// settings first and stepping down if the Mac rejects them. Runs on
    /// sessionQueue. macOS has no `supportedOutputSettingsKeys(for:)` (it is
    /// iOS-only) and signals rejection with an NSException, so every attempt
    /// goes through CPTryObjC. Returns a human label of what took effect.
    private func applyOutputSettings(_ quality: RecordingQuality) -> String {
        guard let connection = movieOutput.connection(with: .video) else {
            return "по умолчанию (нет видео-соединения)"
        }
        let codecs = movieOutput.availableVideoCodecTypes
        let dims = currentVideoInput.map { CaptureManager.dimensions(of: $0.device.activeFormat) } ?? (1920, 1080)

        var attempts: [(label: String, settings: [String: Any])] = []
        if let bitrate = quality.videoBitrate(width: dims.0, height: dims.1) {
            let useHEVC = codecs.contains(.hevc)
            let codec: AVVideoCodecType = useHEVC ? .hevc : .h264
            let name = useHEVC ? "HEVC" : "H.264"
            let mbit = String(format: "%.1f", Double(bitrate) / 1_000_000).replacingOccurrences(of: ".", with: ",")
            attempts.append((
                "\(name) \(mbit) Мбит/с · \(dims.0)×\(dims.1)",
                [AVVideoCodecKey: codec,
                 AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: NSNumber(value: bitrate)]]
            ))
            if useHEVC {
                // HEVC alone still roughly halves the file if the bitrate is refused.
                attempts.append(("HEVC без ограничения (Mac не принял битрейт)", [AVVideoCodecKey: AVVideoCodecType.hevc]))
            }
        }
        attempts.append(("H.264 без ограничения", [AVVideoCodecKey: AVVideoCodecType.h264]))

        for attempt in attempts {
            var error: NSError?
            let ok = CPTryObjC({ self.movieOutput.setOutputSettings(attempt.settings, for: connection) }, &error)
            if ok { return attempt.label }
            log.error("setOutputSettings rejected (\(attempt.label, privacy: .public)): \(error?.localizedDescription ?? "?", privacy: .public)")
        }
        return "по умолчанию (все варианты отклонены)"
    }

    @MainActor
    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [self] in
            if movieOutput.isRecording { movieOutput.stopRecording() }
        }
    }

    // MARK: - Diagnostics

    private static func authStatus(_ type: AVMediaType) -> String {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return "разрешено"
        case .denied: return "запрещено"
        case .restricted: return "ограничено"
        case .notDetermined: return "не запрошено"
        @unknown default: return "?"
        }
    }

    /// Plain-text report for support: devices, formats, session state.
    @MainActor
    func diagnosticsReport() -> String {
        var lines: [String] = []
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        lines.append("CamPrompt \(appVersion) · macOS \(osVersion)")
        lines.append("Разрешения: камера=\(CaptureManager.authStatus(.video)), микрофон=\(CaptureManager.authStatus(.audio))")
        let camChoice = settings?.selectedCameraID ?? ""
        let micChoice = settings?.selectedMicID ?? ""
        lines.append("Выбрано: камера=\(camChoice.isEmpty ? "авто" : camChoice), микрофон=\(micChoice.isEmpty ? "авто" : micChoice)")
        lines.append("")
        lines.append("Камеры (\(cameras.count)):")
        for d in cameras {
            let active = CaptureManager.dimensions(of: d.activeFormat)
            lines.append("  • \(d.localizedName) [\(d.deviceType.rawValue)] id=\(d.uniqueID)")
            lines.append("    макс=\(CaptureManager.maxResolution(of: d)) актив=\(active.0)×\(active.1) занята_другим=\(d.isInUseByAnotherApplication) подключена=\(d.isConnected)")
        }
        lines.append("Микрофоны (\(microphones.count)):")
        for d in microphones {
            lines.append("  • \(d.localizedName) id=\(d.uniqueID)")
        }
        lines.append("")
        lines.append("Сессия: running=\(session.isRunning) preset=\(CaptureManager.presetName(session.sessionPreset)) inputs=\(session.inputs.count) outputs=\(session.outputs.count)")
        for c in movieOutput.connections {
            let media = c.inputPorts.first?.mediaType.rawValue ?? "?"
            lines.append("  соединение \(media): active=\(c.isActive) enabled=\(c.isEnabled)")
        }
        lines.append("Активный формат: \(activeFormatInfo)")
        lines.append("Качество записи: \(settings?.recordingQuality ?? "?") → \(recordingFormatInfo)")
        if let lastRecordingStats {
            lines.append("Последняя запись: \(lastRecordingStats)")
        }
        if let lastError {
            lines.append("Ошибка: \(lastError)")
        }
        if !lastConfigureNotes.isEmpty {
            lines.append("")
            lines.append("Лог последней настройки:")
            lines += lastConfigureNotes.map { "  " + $0 }
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    func copyDiagnosticsToClipboard() {
        let text = diagnosticsReport()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        log.info("diagnostics copied to clipboard")
    }
}

extension CaptureManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        // no-op
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // Real outcome, so "did the Mac honour the bitrate?" is visible in the
        // camera settings without sending the file anywhere.
        let bytes = Double(output.recordedFileSize)
        let seconds = CMTimeGetSeconds(output.recordedDuration)
        let stats: String? = {
            guard seconds.isFinite, seconds > 0, bytes > 0 else { return nil }
            let mb = bytes / 1_000_000
            let mbit = bytes * 8 / seconds / 1_000_000
            let s = Int(seconds.rounded())
            return String(format: "%.0f МБ · %d:%02d · %.1f Мбит/с", mb, s / 60, s % 60, mbit)
                .replacingOccurrences(of: ".", with: ",")
        }()
        if let stats {
            log.info("recording finished: \(stats, privacy: .public)")
        }
        DispatchQueue.main.async {
            if let stats { self.lastRecordingStats = stats }
            self.isRecording = false
            self.onRecordingFinished?(error == nil ? outputFileURL : nil, error)
        }
    }
}
