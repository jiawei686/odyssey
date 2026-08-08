@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct BodyScannerCameraPreview: UIViewRepresentable {
    @ObservedObject var model: BodyScannerCameraModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BodyScannerPreviewView {
        let view = BodyScannerPreviewView()
        view.previewLayer.session = model.session
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        context.coordinator.update(model: model, previewLayer: view.previewLayer)
        return view
    }

    func updateUIView(_ view: BodyScannerPreviewView, context: Context) {
        view.previewLayer.session = model.session
        if let connection = view.previewLayer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        context.coordinator.update(model: model, previewLayer: view.previewLayer)
    }

    final class Coordinator {
        private weak var device: AVCaptureDevice?
        private weak var previewLayer: AVCaptureVideoPreviewLayer?
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

        func update(
            model: BodyScannerCameraModel,
            previewLayer: AVCaptureVideoPreviewLayer
        ) {
            guard let input = model.session.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first else {
                return
            }
            if device !== input.device || self.previewLayer !== previewLayer {
                device = input.device
                self.previewLayer = previewLayer
                rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                    device: input.device,
                    previewLayer: previewLayer
                )
            }
            guard let connection = previewLayer.connection,
                  let rotationCoordinator else {
                return
            }
            let angle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
            guard connection.isVideoRotationAngleSupported(angle) else {
                model.recordUnsupportedPreviewRotation(angle)
                return
            }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
            if connection.videoRotationAngle != angle {
                connection.videoRotationAngle = angle
            }
            if model.previewRotationAngleDegrees != angle {
                model.recordPreviewRotationAngle(angle)
            }
        }
    }
}

final class BodyScannerPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
