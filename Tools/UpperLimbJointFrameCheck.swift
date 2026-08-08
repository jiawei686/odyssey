import Foundation

@main
struct UpperLimbJointFrameCheck {
    static func main() throws {
        try coordinateSpacesKeepTheirUnits()
        try modelRelativeDepthCannotMasqueradeAsMetres()
        try sessionCalibrationAndSequenceAreGated()
        try staleFramesAreRejected()
        try handConfidenceRemainsHandScoped()
        try peerEnvelopeRoundTripsWithoutSnapshotAmbiguity()
        print("Upper-limb joint-frame checks passed")
    }

    private static func coordinateSpacesKeepTheirUnits() throws {
        let pixel = UpperLimbJointPosition(
            x: 640,
            y: 360,
            z: nil,
            space: .imagePixels,
            unit: .pixels
        )
        let world = UpperLimbJointPosition(
            x: 0.1,
            y: 1.2,
            z: -0.4,
            space: .avpWorld,
            unit: .metres
        )

        try require(pixel.isCoordinateContractValid, "pixel coordinates must remain pixels")
        try require(world.isCoordinateContractValid, "AVP-world coordinates must remain metric 3D")
    }

    private static func modelRelativeDepthCannotMasqueradeAsMetres() throws {
        let mislabeled = UpperLimbJointPosition(
            x: 0.2,
            y: 0.3,
            z: -0.1,
            space: .modelRelative,
            unit: .metres
        )
        try require(!mislabeled.isCoordinateContractValid, "model-relative Z is not measured metres")
    }

    private static func sessionCalibrationAndSequenceAreGated() throws {
        let now = ProcessInfo.processInfo.systemUptime
        let session = UUID()
        let calibration = UUID()
        let clock = UUID()
        var gate = UpperLimbJointFrameGate(
            sessionID: session,
            calibrationID: calibration,
            senderClockID: clock,
            senderToReceiverClockOffsetSeconds: 0,
            maximumAgeSeconds: 0.25
        )

        let first = frame(
            sessionID: session,
            calibrationID: calibration,
            clockID: clock,
            sequence: 7,
            capturedAt: now
        )
        try require(gate.accept(first, now: now) == .accepted, "matching live frame should pass")
        try require(
            gate.accept(first, now: now + 0.01) == .rejected(.nonIncreasingSequence),
            "duplicate sequence must be rejected"
        )

        let wrongCalibration = frame(
            sessionID: session,
            calibrationID: UUID(),
            clockID: clock,
            sequence: 8,
            capturedAt: now + 0.02
        )
        try require(
            gate.accept(wrongCalibration, now: now + 0.02) == .rejected(.calibrationMismatch),
            "calibration mismatch must be rejected"
        )
    }

    private static func staleFramesAreRejected() throws {
        let now = ProcessInfo.processInfo.systemUptime
        let session = UUID()
        let calibration = UUID()
        let clock = UUID()
        var gate = UpperLimbJointFrameGate(
            sessionID: session,
            calibrationID: calibration,
            senderClockID: clock,
            senderToReceiverClockOffsetSeconds: 0,
            maximumAgeSeconds: 0.25
        )
        let old = frame(
            sessionID: session,
            calibrationID: calibration,
            clockID: clock,
            sequence: 1,
            capturedAt: now - 0.30
        )
        try require(gate.accept(old, now: now) == .rejected(.stale), "old frames must not drive anatomy")
    }

    private static func handConfidenceRemainsHandScoped() throws {
        let observation = UpperLimbJointObservation(
            laterality: .left,
            joint: .indexTip,
            position: UpperLimbJointPosition(
                x: 0.4,
                y: 0.5,
                z: -0.02,
                space: .modelRelative,
                unit: .unitless
            ),
            confidence: nil,
            confidenceScope: .unavailable,
            depthSource: .modelRelative,
            validity: .live,
            state: .observed
        )
        try require(observation.isTruthful, "finger points may omit per-point confidence")

        let fabricated = UpperLimbJointObservation(
            laterality: .left,
            joint: .indexTip,
            position: observation.position,
            confidence: 0.9,
            confidenceScope: .hand,
            depthSource: .modelRelative,
            validity: .live,
            state: .observed
        )
        try require(!fabricated.isTruthful, "hand-global confidence must not be attached to one finger point")
    }

    private static func peerEnvelopeRoundTripsWithoutSnapshotAmbiguity() throws {
        let source = frame(
            sessionID: UUID(),
            calibrationID: UUID(),
            clockID: UUID(),
            sequence: 42,
            capturedAt: 10
        )
        let envelope = UpperLimbPeerEnvelope(jointFrame: source)
        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(UpperLimbPeerEnvelope.self, from: encoded)
        try require(decoded == envelope, "tagged joint-frame message must round-trip")
        try require(decoded.messageType == .jointFrame, "joint frame must carry an explicit message tag")
    }

    private static func frame(
        sessionID: UUID,
        calibrationID: UUID,
        clockID: UUID,
        sequence: UInt64,
        capturedAt: TimeInterval
    ) -> UpperLimbJointFrame {
        UpperLimbJointFrame(
            sessionID: sessionID,
            calibrationID: calibrationID,
            senderClockID: clockID,
            sequence: sequence,
            capturedAtMonotonic: capturedAt,
            observations: []
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
