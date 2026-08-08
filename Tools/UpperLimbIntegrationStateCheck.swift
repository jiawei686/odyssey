import Foundation

@main
struct UpperLimbIntegrationStateCheck {
    static func main() throws {
        try activationAndAxisFrameTrack()
        try delayedFirstPacketCannotAuthorizeItsOwnClock()
        try partialStaleAndFailedStatesFadeOrHide()
        try calibrationMismatchFailsClosed()
        print("Upper-limb integration-state checks passed")
    }

    private static func activationAndAxisFrameTrack() throws {
        let now = 50.0
        let frame = axisFrame(capturedAt: 10, sequence: 1)
        var state = UpperLimbIntegrationState(maximumAgeSeconds: 0.25)
        state.activate(
            authority: authority(senderToReceiverClockOffsetSeconds: 40),
            laterality: .right,
            model: model()
        )
        state.consume(frame, receivedAtMonotonic: now)
        try require(state.phase == .axisOnly, "trusted first frame should enter axis-only state")
        try require(state.commonRoot != nil, "axis-only state needs the shared root")
        try require(state.displayOpacity == 1, "live tracking should be fully visible")
    }

    private static func delayedFirstPacketCannotAuthorizeItsOwnClock() throws {
        let delayed = axisFrame(capturedAt: 10, sequence: 1)
        var state = UpperLimbIntegrationState(maximumAgeSeconds: 0.25)
        state.activate(
            authority: authority(senderToReceiverClockOffsetSeconds: 0),
            laterality: .right,
            model: model()
        )
        state.consume(delayed, receivedAtMonotonic: 50)
        try require(state.phase == .stale, "a delayed first packet must remain stale")
        try require(state.lastRejection == .stale, "stale first-packet reason should remain visible")
    }

    private static func partialStaleAndFailedStatesFadeOrHide() throws {
        let frame = axisFrame(capturedAt: 10, sequence: 1)
        var state = UpperLimbIntegrationState(maximumAgeSeconds: 0.25)
        state.activate(
            authority: authority(senderToReceiverClockOffsetSeconds: 40),
            laterality: .right,
            model: model()
        )
        state.consume(frame, receivedAtMonotonic: 50)
        state.refresh(now: 50.30)
        try require(state.phase == .stale, "silent stream must become stale")
        try require(state.commonRoot != nil && state.displayOpacity < 1, "stale keeps last pose but fades")

        state.fail(reason: .invalidPayload)
        try require(state.phase == .failed, "explicit failure must become failed")
        try require(state.commonRoot == nil && state.displayOpacity == 0, "failed state must hide anatomy")
    }

    private static func calibrationMismatchFailsClosed() throws {
        let first = axisFrame(capturedAt: 10, sequence: 1)
        var state = UpperLimbIntegrationState(maximumAgeSeconds: 0.25)
        state.activate(
            authority: authority(senderToReceiverClockOffsetSeconds: 40),
            laterality: .right,
            model: model()
        )
        state.consume(first, receivedAtMonotonic: 50)
        let wrong = UpperLimbJointFrame(
            sessionID: first.sessionID,
            calibrationID: UUID(),
            senderClockID: first.senderClockID,
            sequence: 2,
            capturedAtMonotonic: 10.05,
            observations: first.observations
        )
        state.consume(wrong, receivedAtMonotonic: 50.05)
        try require(state.phase == .failed, "wrong calibration must fail closed")
        try require(state.lastRejection == .calibrationMismatch, "failure reason should remain visible")
    }

    private static func authority(
        senderToReceiverClockOffsetSeconds: TimeInterval
    ) -> UpperLimbCalibrationAuthority {
        UpperLimbCalibrationAuthority(
            sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            calibrationID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            senderClockID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            senderToReceiverClockOffsetSeconds: senderToReceiverClockOffsetSeconds
        )
    }

    private static func axisFrame(
        capturedAt: TimeInterval,
        sequence: UInt64
    ) -> UpperLimbJointFrame {
        UpperLimbJointFrame(
            sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            calibrationID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            senderClockID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            sequence: sequence,
            capturedAtMonotonic: capturedAt,
            observations: [
                observation(.elbow, .init(x: 0, y: 0, z: 0)),
                observation(.wrist, .init(x: 0, y: 0.3, z: 0))
            ]
        )
    }

    private static func observation(
        _ joint: UpperLimbJointName,
        _ point: LandmarkVector3
    ) -> UpperLimbJointObservation {
        UpperLimbJointObservation(
            laterality: .right,
            joint: joint,
            position: .init(x: point.x, y: point.y, z: point.z, space: .avpWorld, unit: .metres),
            confidence: 0.9,
            confidenceScope: .landmark,
            depthSource: .lidar,
            validity: .live,
            state: .observed
        )
    }

    private static func model() -> SpatialForearmModelDefinition {
        SpatialForearmModelDefinition(
            laterality: .right,
            elbow: .zero,
            wrist: .init(x: 0, y: 0.3, z: 0),
            distalRadius: .init(x: 0.02, y: 0.3, z: 0),
            distalUlna: .init(x: -0.02, y: 0.3, z: 0),
            humanReviewed: true
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
