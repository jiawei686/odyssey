import Foundation
import simd

@main
struct AVPForearmOverlayPoseCheck {
    static func main() {
        let searching = AVPForearmOverlayPoseResolver.resolve(
            forearmArm: nil,
            forearmWrist: nil,
            wrist: nil
        )
        expect(searching.state == .searching, "no points must remain searching")
        expect(searching.pose == nil, "searching must not leave a visible overlay")

        let partial = AVPForearmOverlayPoseResolver.resolve(
            forearmArm: SIMD3<Float>(0, 0, 0),
            forearmWrist: SIMD3<Float>(0, 0.24, 0),
            wrist: nil
        )
        expect(partial.state == .partial, "two points must remain partial")
        expect(partial.trackedPointCount == 2, "partial count must be truthful")
        expect(partial.pose == nil, "partial input must not drive the overlay")

        let live = AVPForearmOverlayPoseResolver.resolve(
            forearmArm: SIMD3<Float>(0, 0, 0),
            forearmWrist: SIMD3<Float>(0, 0.24, 0),
            wrist: SIMD3<Float>(0, 0.26, 0)
        )
        expect(live.state == .live, "three plausible points must resolve live")
        guard let pose = live.pose else {
            fatalError("live resolution must contain a pose")
        }
        expect(approximately(pose.length, 0.24), "forearm endpoints must set length")
        expect(
            approximately(pose.center, SIMD3<Float>(0, 0.12, 0)),
            "overlay center must bisect the resolved forearm"
        )
        expect(
            approximately(pose.sectionCenter, SIMD3<Float>(0, 0.132, 0)),
            "section must sit at the declared 55% forearm level"
        )
        expect(
            approximately(
                pose.rotation.act(SIMD3<Float>(0, 1, 0)),
                SIMD3<Float>(0, 1, 0)
            ),
            "pose rotation must map the cylinder Y axis to the forearm axis"
        )
        guard let rightBone = AVPBoneOverlayTransformResolver.resolve(
            pose: pose,
            isLeft: false
        ) else {
            fatalError("live pose must resolve a right bone transform")
        }
        expect(
            approximately(
                rightBone.transformPoint(
                    AVPBoneOverlayTransformResolver.modelElbow
                ),
                pose.proximalPoint
            ),
            "bone transform must map the model elbow to forearmArm"
        )
        expect(
            approximately(
                rightBone.transformPoint(
                    AVPBoneOverlayTransformResolver.modelWrist
                ),
                pose.distalPoint
            ),
            "bone transform must map the model wrist to forearmWrist"
        )
        guard let leftBone = AVPBoneOverlayTransformResolver.resolve(
            pose: pose,
            isLeft: true
        ) else {
            fatalError("live pose must resolve a left bone transform")
        }
        expect(
            approximately(
                leftBone.transformPoint(
                    AVPBoneOverlayTransformResolver.modelWrist
                ),
                pose.distalPoint
            ),
            "left-hand mirroring must preserve the tracked forearm endpoints"
        )
        let modelSidePoint = AVPBoneOverlayTransformResolver.modelElbow
            + SIMD3<Float>(0.02, 0, 0)
        expect(
            simd_dot(
                rightBone.transformPoint(modelSidePoint) - pose.proximalPoint,
                leftBone.transformPoint(modelSidePoint) - pose.proximalPoint
            ) < 0,
            "left-hand transform must mirror the model across its local X axis"
        )

        let segmentStart = SIMD3<Float>(0.12, -0.04, 0.31)
        let segmentEnd = SIMD3<Float>(-0.08, 0.18, 0.22)
        guard let segment = AVPTrackedBoneSegmentTransformResolver.resolve(
            start: segmentStart,
            end: segmentEnd
        ) else {
            fatalError("expected a valid tracked bone segment")
        }
        expect(
            approximately(
                segment.transformPoint(
                    SIMD3<Float>(0, -segment.length * 0.5, 0)
                ),
                segmentStart
            ),
            "tracked segment must map its local start to the first live joint"
        )
        expect(
            approximately(
                segment.transformPoint(
                    SIMD3<Float>(0, segment.length * 0.5, 0)
                ),
                segmentEnd
            ),
            "tracked segment must map its local end to the second live joint"
        )
        expect(
            AVPTrackedBoneSegmentTransformResolver.resolve(
                start: segmentStart,
                end: segmentStart
            ) == nil,
            "zero-length tracked segments must be rejected"
        )

        let horizontal = AVPForearmOverlayPoseResolver.resolve(
            forearmArm: SIMD3<Float>(0.1, 0.2, -0.3),
            forearmWrist: SIMD3<Float>(0.32, 0.2, -0.3),
            wrist: SIMD3<Float>(0.34, 0.2, -0.3)
        )
        guard let horizontalPose = horizontal.pose else {
            fatalError("horizontal fixture must resolve")
        }
        expect(
            approximately(
                horizontalPose.rotation.act(SIMD3<Float>(0, 1, 0)),
                SIMD3<Float>(1, 0, 0)
            ),
            "rotation must follow an arbitrary world-space forearm axis"
        )

        let tooShort = AVPForearmOverlayPoseResolver.resolve(
            forearmArm: SIMD3<Float>(0, 0, 0),
            forearmWrist: SIMD3<Float>(0, 0.02, 0),
            wrist: SIMD3<Float>(0, 0.03, 0)
        )
        expect(tooShort.state == .failed, "implausibly short geometry must fail")
        expect(tooShort.pose == nil, "invalid geometry must hide the overlay")

        let nonFinite = AVPForearmOverlayPoseResolver.resolve(
            forearmArm: SIMD3<Float>(.nan, 0, 0),
            forearmWrist: SIMD3<Float>(0, 0.24, 0),
            wrist: SIMD3<Float>(0, 0.26, 0)
        )
        expect(nonFinite.state == .failed, "non-finite geometry must fail")

        let inconsistentWrist = AVPForearmOverlayPoseResolver.resolve(
            forearmArm: SIMD3<Float>(0, 0, 0),
            forearmWrist: SIMD3<Float>(0, 0.20, 0),
            wrist: SIMD3<Float>(0.30, 0.20, 0)
        )
        expect(
            inconsistentWrist.state == .failed,
            "widely separated wrist endpoints must not form a plausible forearm"
        )

        var tracker = AVPForearmOverlayTracker(staleWindowSeconds: 0.4)
        let tracked = tracker.update(
            forearmArm: SIMD3<Float>(0, 0, 0),
            forearmWrist: SIMD3<Float>(0, 0.24, 0),
            wrist: SIMD3<Float>(0, 0.26, 0),
            timestamp: 10
        )
        expect(tracked.state == .live, "tracker must publish a complete frame live")

        let stale = tracker.update(
            forearmArm: nil,
            forearmWrist: nil,
            wrist: nil,
            timestamp: 10.2
        )
        expect(stale.state == .stale, "brief loss must enter stale state")
        expect(stale.pose != nil, "stale window may retain only the last pose")

        let expired = tracker.update(
            forearmArm: nil,
            forearmWrist: nil,
            wrist: nil,
            timestamp: 10.5
        )
        expect(expired.state == .failed, "expired signal must become failed")
        expect(expired.pose == nil, "expired signal must hide the overlay")

        let reacquired = tracker.update(
            forearmArm: SIMD3<Float>(0, 0, 0),
            forearmWrist: SIMD3<Float>(0, 0.24, 0),
            wrist: SIMD3<Float>(0, 0.26, 0),
            timestamp: 10.6
        )
        expect(reacquired.state == .live, "complete reacquisition must return live")

        let providerFailure = tracker.fail(detail: "stream ended")
        expect(providerFailure.state == .failed, "provider failure must be explicit")
        expect(providerFailure.pose == nil, "provider failure must hide the overlay")

        print("AVP forearm overlay pose checks passed")
    }

    private static func approximately(_ lhs: Float, _ rhs: Float) -> Bool {
        abs(lhs - rhs) < 0.000_01
    }

    private static func approximately(
        _ lhs: SIMD3<Float>,
        _ rhs: SIMD3<Float>
    ) -> Bool {
        simd_length(lhs - rhs) < 0.000_01
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
