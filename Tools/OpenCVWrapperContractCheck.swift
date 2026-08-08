import Foundation

private enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

@main
private enum OpenCVWrapperContractCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CheckFailure.failed("usage: OpenCVWrapperContractCheck <repository-root>")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let directory = root.appendingPathComponent("UpperLimbPOC/BodyScanner/OpenCV", isDirectory: true)
        let header = try read(directory.appendingPathComponent("OpenCVBodyScanner.h"))
        let bridgingHeader = try read(directory.appendingPathComponent("OpenCVBodyScanner-Bridging-Header.h"))
        let bridge = try read(directory.appendingPathComponent("OpenCVBodyScanner.mm"))
        let pipelineHeader = try read(directory.appendingPathComponent("MPPersonPosePipeline.hpp"))
        let pipeline = try read(directory.appendingPathComponent("MPPersonPosePipeline.cpp"))

        try require(header.contains("OCVBodyScannerModelPaths"), "Bridge must accept explicit model paths")
        try require(header.contains("inferBGRA8"), "Bridge must accept a capture-neutral BGRA8 buffer")
        try require(header.contains("visibility"), "Bridge must preserve pose visibility")
        try require(header.contains("presence"), "Bridge must preserve pose presence")
        try require(!header.contains("cv::"), "Objective-C bridge header must not leak OpenCV C++ types")
        try require(!header.contains("AVCapture"), "Capture APIs do not belong in the inference bridge")
        try require(
            bridgingHeader.contains("#import \"OpenCVBodyScanner.h\""),
            "The iPhone target needs a narrow Swift/Objective-C bridging header"
        )

        try require(bridge.contains("readNetFromONNX"), "Dependency spike must exercise ONNX model loading")
        try require(bridge.contains("CV_VERSION_MAJOR == 4"), "Bridge must reject an incompatible OpenCV major")
        try require(bridge.contains("CV_VERSION_MINOR == 13"), "Bridge must pin OpenCV 4.13")
        try require(bridge.contains("CV_VERSION_REVISION == 0"), "Bridge must pin OpenCV 4.13.0 exactly")
        try require(bridge.contains("loadModels"), "Model loading must be explicit and fallible")

        try require(pipelineHeader.contains("PoseLandmark"), "Pipeline must return raw landmark evidence")
        try require(pipelineHeader.contains("personScore"), "Pipeline must preserve person score")
        try require(pipelineHeader.contains("poseScore"), "Pipeline must preserve global pose score")
        try require(pipeline.contains("case 11") && pipeline.contains("case 16"), "Pipeline must emit shoulders through wrists")
        try require(pipeline.contains("sigmoid"), "Decoder must turn pose logits into probabilities")
        try require(pipeline.contains("kPoseThreshold"), "Pipeline must gate the model's global pose confidence")
        try require(
            pipeline.contains("result.poseScore = rawPoseScore[0]"),
            "Global pose confidence is already a probability and must not receive a second sigmoid"
        )
        try require(
            pipeline.contains("throw NoPoseError()"),
            "Low-confidence pose output must not publish landmarks"
        )
        try require(pipeline.contains("NMSBoxes"), "Duplicate person anchors must be suppressed before counting people")
        try require(
            pipeline.contains("throw MultiplePeopleError()"),
            "More than one distinct person must block the consent-scoped scan"
        )
        try require(pipeline.contains("generatePersonAnchors"), "Person decoder must use the MediaPipe anchor contract")

        let allSource = [header, bridge, pipelineHeader, pipeline].joined(separator: "\n")
        try require(!allSource.contains("VNDetectHumanBodyPoseRequest"), "Apple Vision pose inference is out of scope")
        try require(!allSource.contains("confidencePerJoint"), "No per-joint confidence may be fabricated")
        print("OpenCVWrapperContractCheck: PASS")
    }

    private static func read(_ url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CheckFailure.failed("Missing expected source file: \(url.path)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
