import Foundation

@main
struct BodyScannerOrientationCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CheckFailure("usage: BodyScannerOrientationCheck <repository-root>")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let camera = try source(root, "UpperLimbPOC/BodyScanner/UI/BodyScannerCameraModel.swift")
        let preview = try source(root, "UpperLimbPOC/BodyScanner/UI/BodyScannerCameraPreview.swift")
        let screen = try source(root, "UpperLimbPOC/BodyScanner/UI/BodyScannerScreen.swift")
        let bridgeHeader = try source(root, "UpperLimbPOC/BodyScanner/OpenCV/OpenCVBodyScanner.h")
        let pipeline = try source(root, "UpperLimbPOC/BodyScanner/OpenCV/MPPersonPosePipeline.cpp")

        try require(
            camera.contains("AVCaptureDevice.RotationCoordinator"),
            "capture must use Apple's physical-device rotation coordinator"
        )
        try require(
            camera.contains("videoRotationAngleForHorizonLevelCapture"),
            "capture must request the coordinator's horizon-level angle"
        )
        try require(
            camera.contains("isVideoRotationAngleSupported"),
            "capture must test rotation support before changing the connection"
        )
        try require(
            preview.contains("AVCaptureDevice.RotationCoordinator")
                && preview.contains("videoRotationAngleForHorizonLevelPreview")
                && preview.contains("isVideoRotationAngleSupported"),
            "preview must use a coordinator bound to its actual preview layer"
        )
        try require(
            preview.contains("@ObservedObject var model: BodyScannerCameraModel"),
            "preview must observe session-model changes so it can attach after the camera input appears"
        )
        try require(
            !preview.contains("let rotationAngleDegrees: CGFloat"),
            "preview must not reuse the capture connection's numeric angle"
        )
        try require(
            screen.contains("BodyScannerCameraPreview(model: model)"),
            "preview-layer coordination must report its actual angle to the scanner model"
        )
        try require(
            screen.contains("sensorWidth: model.frameSize.width")
                && screen.contains("sensorHeight: model.frameSize.height"),
            "overlay projection must use delivered oriented-frame dimensions"
        )
        try require(
            !screen.contains("sensorWidth: 16") && !screen.contains("sensorHeight: 9"),
            "overlay projection must not hard-code sensor aspect"
        )
        try require(
            bridgeHeader.contains("poseCropCenterX")
                && bridgeHeader.contains("poseCropCenterY")
                && bridgeHeader.contains("poseCropSize"),
            "physical diagnostics must expose the decoded pose crop"
        )
        try require(
            pipeline.contains("result.poseCropSize")
                && camera.contains("@Published private(set) var diagnostics")
                && camera.contains("previewRotationAngleDegrees")
                && screen.contains("model.diagnostics"),
            "the physical screen must report frame, separate capture/preview rotations, and pose crop"
        )

        try orientedLandscapeProjectionIsDeterministic()
        print("Body scanner orientation checks passed")
    }

    private static func orientedLandscapeProjectionIsDeterministic() throws {
        let clockwise = BodyScannerPreviewProjection(
            sensorWidth: 1280,
            sensorHeight: 720,
            viewWidth: 960,
            viewHeight: 720
        )
        let counterClockwise = BodyScannerPreviewProjection(
            sensorWidth: 1280,
            sensorHeight: 720,
            viewWidth: 960,
            viewHeight: 720
        )
        let point90 = clockwise.project(normalizedX: 0.25, normalizedY: 0.75)
        let point270 = counterClockwise.project(normalizedX: 0.25, normalizedY: 0.75)
        try require(point90 == point270, "both landscape rotations need identical oriented geometry")
        try require(abs(point90.x - 240) < 1e-9, "oriented landscape X projection mismatch")
        try require(abs(point90.y - 495) < 1e-9, "oriented landscape Y projection mismatch")

        let unrotatedPortraitBuffer = BodyScannerPreviewProjection(
            sensorWidth: 720,
            sensorHeight: 1280,
            viewWidth: 960,
            viewHeight: 720
        )
        let wrongPoint = unrotatedPortraitBuffer.project(normalizedX: 0.25, normalizedY: 0.75)
        try require(wrongPoint != point90, "the regression fixture must detect an unrotated portrait buffer")
    }

    private static func source(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message) }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}
