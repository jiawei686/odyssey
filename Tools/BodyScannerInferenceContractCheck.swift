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
private enum BodyScannerInferenceContractCheck {
    static func main() throws {
        try checkPinnedDependencyManifest()
        try checkResourceFingerprinting()
        try checkUpperLimbPoseMapping()
        try checkLowConfidenceAndInvalidLandmarks()
        print("BodyScannerInferenceContractCheck: PASS")
    }

    private static func checkResourceFingerprinting() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("body-scanner-fingerprint-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)

        let fingerprint = try BodyScannerResourceInspector.fingerprint(of: url)
        try require(fingerprint.byteCount == 3, "Fingerprint must bind the exact byte count")
        try require(
            fingerprint.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "Fingerprint must be a lowercase SHA-256 digest"
        )
    }

    private static func checkPinnedDependencyManifest() throws {
        let manifest = BodyScannerModelManifest.openCVZooPinned
        try require(manifest.openCVVersion == "4.13.0", "OpenCV must be pinned to 4.13.0")
        try require(
            manifest.openCVRevision == "fe38fc608f6acb8b68953438a62305d8318f4fcd",
            "The OpenCV 4.13.0 source revision must also be pinned"
        )
        try require(
            manifest.modelZooRevision == "47534e27c9851bb1128ccc0102f1145e27f23f98",
            "OpenCV Zoo must be revision-pinned"
        )
        try require(
            manifest.artifacts.map(\.fileName) == [
                "person_detection_mediapipe_2023mar.onnx",
                "pose_estimation_mediapipe_2023mar.onnx",
                "palm_detection_mediapipe_2023feb.onnx",
                "handpose_estimation_mediapipe_2023feb.onnx",
            ],
            "The exact four FP32 artifact names are part of the runtime contract"
        )
        try require(
            manifest.artifacts.map(\.expectedSHA256) == [
                "47fd5599d6fa17608f03e0eb0ae230baa6e597d7e8a2c8199fe00abea55a701f",
                "9d89c599319a18fb7d2e28451a883476164543182bafca5f09eb2cf767ed2f3f",
                "78ff51c38496b7fc8b8ebdb6cc8c1abb02fa6c38427c6848254cdaba57fcce7c",
                "db0898ae717b76b075d9bf563af315b29562e11f8df5027a1ef07b02bef6d81c",
            ],
            "Every model must have a reviewed SHA-256 pin"
        )

        let missing = manifest.validate(resources: [:])
        try require(missing.isReady == false, "Missing model resources must never report ready")
        try require(missing.issues.count == 4, "Each missing resource should be reported")

        let fakeResources = Dictionary(
            uniqueKeysWithValues: manifest.artifacts.map {
                ($0.fileName, BodyScannerResourceFingerprint(sha256: String(repeating: "0", count: 64), byteCount: 1))
            }
        )
        let unverified = manifest.validate(resources: fakeResources)
        try require(unverified.isReady == false, "Unpinned digests must never report ready")
        try require(
            unverified.issues.allSatisfy { $0.reason == .fingerprintMismatch },
            "The spike must distinguish corrupt or substituted bytes from ready"
        )

        let expectedResources = Dictionary(
            uniqueKeysWithValues: manifest.artifacts.map { artifact in
                (
                    artifact.fileName,
                    BodyScannerResourceFingerprint(sha256: artifact.expectedSHA256, byteCount: 1)
                )
            }
        )
        try require(expectedResources.count == 4, "All four model fingerprints must be pinned")
        try require(manifest.validate(resources: expectedResources).isReady, "Only exact reviewed fingerprints are ready")
    }

    private static func checkUpperLimbPoseMapping() throws {
        let landmarks = [
            BodyScannerPoseLandmark(index: 11, imageX: 110, imageY: 120, modelRelativeZ: -0.1, visibility: 0.90, presence: 0.80),
            BodyScannerPoseLandmark(index: 12, imageX: 210, imageY: 120, modelRelativeZ: -0.1, visibility: 0.95, presence: 0.85),
            BodyScannerPoseLandmark(index: 13, imageX: 95, imageY: 180, modelRelativeZ: -0.2, visibility: 0.75, presence: 0.70),
            BodyScannerPoseLandmark(index: 14, imageX: 225, imageY: 180, modelRelativeZ: -0.2, visibility: 0.80, presence: 0.78),
            BodyScannerPoseLandmark(index: 15, imageX: 80, imageY: 240, modelRelativeZ: -0.3, visibility: 0.65, presence: 0.60),
            BodyScannerPoseLandmark(index: 16, imageX: 240, imageY: 240, modelRelativeZ: -0.3, visibility: 0.70, presence: 0.68),
        ]
        let observations = BodyScannerUpperLimbPoseMapper.map(
            landmarks: landmarks,
            imageWidth: 320,
            imageHeight: 480,
            minimumConfidence: 0.5
        )

        try require(observations.count == 6, "All six upper-limb joints should map")
        let identity = Set(observations.map { "\($0.laterality.rawValue):\($0.joint.rawValue)" })
        try require(
            identity == [
                "left:shoulder", "right:shoulder",
                "left:elbow", "right:elbow",
                "left:wrist", "right:wrist",
            ],
            "MediaPipe pose indices must map to the correct laterality and joint"
        )

        let leftShoulder = try requireObservation(observations, .left, .shoulder)
        try require(leftShoulder.confidence == 0.80, "Landmark confidence is min(visibility, presence)")
        try require(leftShoulder.confidenceScope == .landmark, "Pose confidence is landmark-scoped")
        try require(leftShoulder.position.space == .imagePixels, "Pose output is reported in image pixels")
        try require(leftShoulder.position.z == nil, "Model-relative Z must not be mixed into pixel coordinates")
        try require(leftShoulder.depthSource == .none, "The 2D pose mapper must not claim metric depth")
        try require(leftShoulder.state == .observed && leftShoulder.validity == .live, "Qualified joints are live observations")
        try require(leftShoulder.isTruthful, "Mapped observations must satisfy the frozen truth contract")
    }

    private static func checkLowConfidenceAndInvalidLandmarks() throws {
        let landmarks = [
            BodyScannerPoseLandmark(index: 11, imageX: 10, imageY: 20, modelRelativeZ: nil, visibility: 0.8, presence: 0.2),
            BodyScannerPoseLandmark(index: 12, imageX: .nan, imageY: 20, modelRelativeZ: nil, visibility: 0.9, presence: 0.9),
            BodyScannerPoseLandmark(index: 13, imageX: 700, imageY: 20, modelRelativeZ: nil, visibility: 0.9, presence: 0.9),
        ]
        let observations = BodyScannerUpperLimbPoseMapper.map(
            landmarks: landmarks,
            imageWidth: 640,
            imageHeight: 480,
            minimumConfidence: 0.5
        )

        try require(observations.count == 1, "Non-finite and out-of-image coordinates must be omitted, not fabricated")
        let shoulder = try requireObservation(observations, .left, .shoulder)
        try require(shoulder.confidence == 0.2, "Low confidence must be preserved, not raised to threshold")
        try require(shoulder.state == .estimated, "Below-threshold pose points are estimates")
        try require(shoulder.validity == .partial, "Below-threshold pose points are partial")
        try require(shoulder.isTruthful, "Low-confidence estimates must still satisfy the truth contract")
    }

    private static func requireObservation(
        _ observations: [UpperLimbJointObservation],
        _ laterality: UpperLimbLaterality,
        _ joint: UpperLimbJointName
    ) throws -> UpperLimbJointObservation {
        guard let observation = observations.first(where: { $0.laterality == laterality && $0.joint == joint }) else {
            throw CheckFailure.failed("Missing \(laterality.rawValue) \(joint.rawValue)")
        }
        return observation
    }
}
