import SwiftUI
import AVFoundation
import AppKit

/// NSViewRepresentable hosting AVCaptureVideoPreviewLayer.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.configure(session: session)
        view.setMirrored(mirrored)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.setMirrored(mirrored)
    }

    final class PreviewNSView: NSView {
        private var previewLayer: AVCaptureVideoPreviewLayer?

        func configure(session: AVCaptureSession) {
            wantsLayer = true
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            self.layer = CALayer()
            self.layer?.addSublayer(layer)
            previewLayer = layer
        }

        func setMirrored(_ mirrored: Bool) {
            guard let connection = previewLayer?.connection else { return }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }

        override func layout() {
            super.layout()
            previewLayer?.frame = bounds
        }
    }
}
