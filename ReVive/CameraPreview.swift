//
//  CameraPreview.swift
//  Recyclability
//
//  Created by Sidharth Kumar on 1/24/26.
//
import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let videoOrientation: AVCaptureVideoOrientation

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.connection?.videoOrientation = videoOrientation
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if let connection = uiView.previewLayer.connection {
            connection.videoOrientation = videoOrientation
        }
    }
}

/// Minimal UIView that owns the preview layer
final class PreviewUIView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}


