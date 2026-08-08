import Foundation

@main
struct JointProbeMetricsCheck {
    static func main() throws {
        try continuityPassesWithStableCriticalJoints()
        try noSignalIsReported()
        try shortRunIsInsufficient()
        print("Joint capability probe metric checks passed")
    }

    private static func continuityPassesWithStableCriticalJoints() throws {
        var accumulator = JointProbeAccumulator(
            expectedJointCount: 27,
            expectedCriticalJointCount: 4
        )
        accumulator.start(at: 0)
        for index in 0..<60 {
            accumulator.record(
                timestamp: Double(index) * 0.5,
                hand: .right,
                trackedJointCount: 27,
                trackedCriticalJointCount: index < 58 ? 4 : 3
            )
        }
        let report = accumulator.finish(at: 30)
        try require(
            report.verdict == .continuityPass,
            "stable critical joints should pass"
        )
        try require(
            report.right.criticalContinuity > 0.96,
            "critical continuity should be measured"
        )
    }

    private static func noSignalIsReported() throws {
        var accumulator = JointProbeAccumulator(
            expectedJointCount: 27,
            expectedCriticalJointCount: 4
        )
        accumulator.start(at: 0)
        let report = accumulator.finish(at: 30)
        try require(
            report.verdict == .noSignal,
            "no hand updates should report no signal"
        )
    }

    private static func shortRunIsInsufficient() throws {
        var accumulator = JointProbeAccumulator(
            expectedJointCount: 27,
            expectedCriticalJointCount: 4
        )
        accumulator.start(at: 0)
        for index in 0..<10 {
            accumulator.record(
                timestamp: Double(index) * 0.5,
                hand: .left,
                trackedJointCount: 27,
                trackedCriticalJointCount: 4
            )
        }
        let report = accumulator.finish(at: 5)
        try require(
            report.verdict == .insufficientDuration,
            "short run should not pass"
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
