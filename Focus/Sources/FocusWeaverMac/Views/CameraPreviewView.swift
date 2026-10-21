import SwiftUI
import AVFoundation

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoLayer.session = session
        view.videoLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.videoLayer.session = session
    }

    final class PreviewView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.addSublayer(videoLayer)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = true
            layer?.addSublayer(videoLayer)
        }

        override func layout() {
            super.layout()
            videoLayer.frame = bounds
        }

        let videoLayer = AVCaptureVideoPreviewLayer()
    }
}
