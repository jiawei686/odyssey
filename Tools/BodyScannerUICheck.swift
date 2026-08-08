import Foundation

@main
struct BodyScannerUICheck {
    static func main() throws {
        try guidancePriorityIsDeterministic()
        try previewProjectionIsAspectFitAndUnmirrored()
        try stylesDoNotDependOnColourAlone()
        try countsKeepHandConfidenceSeparate()
        try freezeGenerationInvalidatesImmediately()
        try disclosureAndFailureStatesAreExplicit()
        print("Body scanner UI checks passed")
    }

    private static func guidancePriorityIsDeterministic() throws {
        let guidance = BodyScannerGuidanceResolver.resolve([
            .missingRightHand,
            .multiplePeople,
            .bodyTooSmall
        ])
        try require(guidance == .multiplePeople, "multiple people must take priority")
    }

    private static func previewProjectionIsAspectFitAndUnmirrored() throws {
        let projection = BodyScannerPreviewProjection(
            sensorWidth: 1920,
            sensorHeight: 1080,
            viewWidth: 800,
            viewHeight: 600
        )
        let left = projection.project(normalizedX: 0, normalizedY: 0.5)
        let right = projection.project(normalizedX: 1, normalizedY: 0.5)
        try require(abs(left.x - 0) < 1e-9, "aspect-fit left edge mismatch")
        try require(abs(right.x - 800) < 1e-9, "aspect-fit right edge mismatch")
        try require(left.x < right.x, "participant preview must not mirror sensor coordinates")
        try require(abs(projection.imageRect.minY - 75) < 1e-9, "vertical letterbox mismatch")
    }

    private static func stylesDoNotDependOnColourAlone() throws {
        let left = BodyScannerSkeletonStyle.style(for: .participantLeft)
        let right = BodyScannerSkeletonStyle.style(for: .participantRight)
        try require(left.pointShape != right.pointShape, "sides need distinct shapes")
        try require(left.linePattern != right.linePattern, "sides need distinct line patterns")
    }

    private static func countsKeepHandConfidenceSeparate() throws {
        let counts = BodyScannerVisibleCounts(
            bodyQualified: 6,
            bodyAvailable: 6,
            leftHandFiniteInFrame: 19,
            rightHandFiniteInFrame: 21,
            leftHandConfidence: 0.82,
            rightHandConfidence: 0.91
        )
        try require(counts.summary.contains("Arm joints 6/6 • emitted 6/6"), "arm point count mismatch")
        try require(counts.summary.contains("Participant L 19/21 • hand 82%"), "left hand count/score mismatch")
        try require(counts.summary.contains("Participant R 21/21 • hand 91%"), "right hand count/score mismatch")

        let armOnly = BodyScannerVisibleCounts(
            bodyQualified: 6,
            bodyAvailable: 6,
            leftHandFiniteInFrame: 0,
            rightHandFiniteInFrame: 0,
            leftHandConfidence: nil,
            rightHandConfidence: nil
        )
        try require(armOnly.summary.contains("Hands pending"), "arm-only build must not claim hand observations")
        try require(!armOnly.summary.contains("0/21"), "missing hand inference must not be presented as measured zero points")
    }

    private static func freezeGenerationInvalidatesImmediately() throws {
        var guardState = BodyScannerFreezeGuard()
        guardState.update(phase: .qualified(generation: 4))
        try require(guardState.consumeFreeze(generation: 4), "current qualified generation should freeze")
        guardState.update(phase: .partial)
        try require(!guardState.consumeFreeze(generation: 4), "partial state must invalidate freeze")
    }

    private static func disclosureAndFailureStatesAreExplicit() throws {
        try require(
            BodyScannerPresentation.disclosure == "CROSS-SUBJECT • APPROXIMATE • EDUCATIONAL",
            "disclosure text changed"
        )
        try require(BodyScannerTrackingPhase.stale.label == "STALE", "stale label missing")
        try require(BodyScannerTrackingPhase.failed.label == "FAILED", "failed label missing")
        try require(BodyScannerTrackingPhase.failed.displayOpacity == 0, "failed overlay must hide")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
