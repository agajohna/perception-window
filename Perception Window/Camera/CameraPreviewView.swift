//
//  CameraPreviewView.swift
//  Perception Window
//

import AVFoundation
import SwiftUI

#if os(iOS)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var perceptualTransform: CGAffineTransform = .identity

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = PerceptionConfiguration.previewVideoGravity
        view.perceptualTransform = perceptualTransform
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.previewLayer.videoGravity = PerceptionConfiguration.previewVideoGravity
        uiView.perceptualTransform = perceptualTransform
    }
}

final class CameraPreviewUIView: UIView {
    var perceptualTransform: CGAffineTransform = .identity {
        didSet {
            guard perceptualTransform != oldValue else { return }
            transform = perceptualTransform
        }
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

#else

struct CameraPreviewView: View {
    let session: AVCaptureSession

    var body: some View {
        Color.black
    }
}

#endif
