import Foundation

enum BodyScannerModelID: String, CaseIterable, Sendable {
    case personDetector
    case poseEstimator
    case palmDetector
    case handPoseEstimator
}

struct BodyScannerResourceFingerprint: Equatable, Sendable {
    let sha256: String
    let byteCount: Int

    var isWellFormed: Bool {
        byteCount > 0
            && sha256.count == 64
            && sha256.unicodeScalars.allSatisfy {
                ("0"..."9").contains(Character($0)) || ("a"..."f").contains(Character($0))
            }
    }
}

struct BodyScannerModelArtifact: Equatable, Sendable {
    let id: BodyScannerModelID
    let fileName: String
    let expectedSHA256: String
}

enum BodyScannerModelValidationReason: String, Equatable, Sendable {
    case resourceMissing
    case malformedFingerprint
    case fingerprintMismatch
}

struct BodyScannerModelValidationIssue: Equatable, Sendable {
    let model: BodyScannerModelID
    let reason: BodyScannerModelValidationReason
}

struct BodyScannerModelValidation: Equatable, Sendable {
    let issues: [BodyScannerModelValidationIssue]

    var isReady: Bool { issues.isEmpty }
}

struct BodyScannerModelManifest: Equatable, Sendable {
    let openCVVersion: String
    let openCVRevision: String
    let modelZooRevision: String
    let artifacts: [BodyScannerModelArtifact]

    static let openCVZooPinned = BodyScannerModelManifest(
        openCVVersion: "4.13.0",
        openCVRevision: "fe38fc608f6acb8b68953438a62305d8318f4fcd",
        modelZooRevision: "47534e27c9851bb1128ccc0102f1145e27f23f98",
        artifacts: [
            BodyScannerModelArtifact(
                id: .personDetector,
                fileName: "person_detection_mediapipe_2023mar.onnx",
                expectedSHA256: "47fd5599d6fa17608f03e0eb0ae230baa6e597d7e8a2c8199fe00abea55a701f"
            ),
            BodyScannerModelArtifact(
                id: .poseEstimator,
                fileName: "pose_estimation_mediapipe_2023mar.onnx",
                expectedSHA256: "9d89c599319a18fb7d2e28451a883476164543182bafca5f09eb2cf767ed2f3f"
            ),
            BodyScannerModelArtifact(
                id: .palmDetector,
                fileName: "palm_detection_mediapipe_2023feb.onnx",
                expectedSHA256: "78ff51c38496b7fc8b8ebdb6cc8c1abb02fa6c38427c6848254cdaba57fcce7c"
            ),
            BodyScannerModelArtifact(
                id: .handPoseEstimator,
                fileName: "handpose_estimation_mediapipe_2023feb.onnx",
                expectedSHA256: "db0898ae717b76b075d9bf563af315b29562e11f8df5027a1ef07b02bef6d81c"
            ),
        ]
    )

    func validate(
        resources: [String: BodyScannerResourceFingerprint]
    ) -> BodyScannerModelValidation {
        let issues = artifacts.compactMap { artifact -> BodyScannerModelValidationIssue? in
            guard let actual = resources[artifact.fileName] else {
                return BodyScannerModelValidationIssue(model: artifact.id, reason: .resourceMissing)
            }
            guard actual.isWellFormed else {
                return BodyScannerModelValidationIssue(model: artifact.id, reason: .malformedFingerprint)
            }
            guard artifact.expectedSHA256.count == 64,
                  artifact.expectedSHA256.unicodeScalars.allSatisfy({
                      ("0"..."9").contains(Character($0)) || ("a"..."f").contains(Character($0))
                  }) else {
                return BodyScannerModelValidationIssue(model: artifact.id, reason: .malformedFingerprint)
            }
            guard actual.sha256 == artifact.expectedSHA256 else {
                return BodyScannerModelValidationIssue(model: artifact.id, reason: .fingerprintMismatch)
            }
            return nil
        }
        return BodyScannerModelValidation(issues: issues)
    }
}
