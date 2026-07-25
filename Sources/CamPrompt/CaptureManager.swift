import Foundation
import AVFoundation
import AppKit

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

    weak var settings: SettingsStore?
    var onRecordingFinished: ((URL?, Error?) -> Void)?

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "ru.olya.camprompt.session")
    private var currentVideoInput: AVCaptureDeviceInput?
    private var currentAudioInput: AVCaptureDeviceInput?

    static var recordingsDirectory: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let dir = movies.appendingPathComponent("Teleprompter")
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

    // MARK: - Session lifecycle

    @MainActor
    func startCamera() {
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
            let micDevice = mic ? self.micDevice() : nil
            self.configureAndStart(camera: camera, mic: micDevice)
        }
    }

    private func configureAndStart(camera: AVCaptureDevice, mic: AVCaptureDevice?) {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high

            if let old = currentVideoInput { session.removeInput(old); currentVideoInput = nil }
            if let old = currentAudioInput { session.removeInput(old); currentAudioInput = nil }

            do {
                let videoInput = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                    currentVideoInput = videoInput
                }
                if let mic {
                    let audioInput = try AVCaptureDeviceInput(device: mic)
                    if session.canAddInput(audioInput) {
                        session.addInput(audioInput)
                        currentAudioInput = audioInput
                    }
                }
                if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
                    session.addOutput(movieOutput)
                }
                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
                DispatchQueue.main.async {
                    self.isSessionRunning = true
                    self.lastError = nil
                }
            } catch {
                session.commitConfiguration()
                DispatchQueue.main.async {
                    self.lastError = "Не удалось настроить камеру: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    func stopCamera() {
        if isRecording { stopRecording() }
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    /// Re-apply device selection from settings (called when pickers change).
    @MainActor
    func applyDeviceSelection() {
        guard isSessionRunning else { return }
        guard let camera = cameraDevice() else { return }
        configureAndStart(camera: camera, mic: micDevice())
    }

    func shutdown() {
        sessionQueue.sync { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Recording

    @MainActor
    func startRecording() {
        guard isSessionRunning, !isRecording else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = Self.recordingsDirectory
            .appendingPathComponent("CamPrompt_\(formatter.string(from: Date())).mov")
        isRecording = true
        sessionQueue.async { [self] in
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    @MainActor
    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [self] in
            if movieOutput.isRecording { movieOutput.stopRecording() }
        }
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
        DispatchQueue.main.async {
            self.isRecording = false
            self.onRecordingFinished?(error == nil ? outputFileURL : nil, error)
        }
    }
}
