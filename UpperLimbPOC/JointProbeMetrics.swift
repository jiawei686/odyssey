import Foundation

enum JointProbeHand: String, Sendable {
    case left
    case right
}

enum JointProbeVerdict: String, Sendable {
    case continuityPass
    case continuityNeedsWork
    case insufficientDuration
    case noSignal
}

struct JointProbeHandSummary: Equatable, Sendable {
    let sampleCount: Int
    let averageTrackedJointCount: Double
    let criticalContinuity: Double
}

struct JointProbeReport: Equatable, Sendable {
    let durationSeconds: Double
    let left: JointProbeHandSummary
    let right: JointProbeHandSummary
    let verdict: JointProbeVerdict
}

struct JointProbeAccumulator: Sendable {
    private struct Sample: Sendable {
        let timestamp: Double
        let hand: JointProbeHand
        let trackedJointCount: Int
        let trackedCriticalJointCount: Int
    }

    let expectedJointCount: Int
    let expectedCriticalJointCount: Int
    private(set) var startedAt: Double?
    private var samples: [Sample] = []

    init(expectedJointCount: Int, expectedCriticalJointCount: Int) {
        precondition(expectedJointCount > 0)
        precondition(expectedCriticalJointCount > 0)
        self.expectedJointCount = expectedJointCount
        self.expectedCriticalJointCount = expectedCriticalJointCount
    }

    mutating func start(at timestamp: Double) {
        startedAt = timestamp
        samples = []
    }

    mutating func record(
        timestamp: Double,
        hand: JointProbeHand,
        trackedJointCount: Int,
        trackedCriticalJointCount: Int
    ) {
        guard startedAt != nil else { return }
        samples.append(
            Sample(
                timestamp: timestamp,
                hand: hand,
                trackedJointCount: min(max(trackedJointCount, 0), expectedJointCount),
                trackedCriticalJointCount: min(
                    max(trackedCriticalJointCount, 0),
                    expectedCriticalJointCount
                )
            )
        )
    }

    mutating func finish(at timestamp: Double) -> JointProbeReport {
        let duration = max(0, timestamp - (startedAt ?? timestamp))
        let left = summary(for: .left)
        let right = summary(for: .right)
        let trackedSignalExists = samples.contains { $0.trackedJointCount > 0 }

        let verdict: JointProbeVerdict
        if !trackedSignalExists {
            verdict = .noSignal
        } else if duration < 25 {
            verdict = .insufficientDuration
        } else if [left, right].contains(where: {
            $0.sampleCount >= 30 && $0.criticalContinuity >= 0.90
        }) {
            verdict = .continuityPass
        } else {
            verdict = .continuityNeedsWork
        }

        return JointProbeReport(
            durationSeconds: duration,
            left: left,
            right: right,
            verdict: verdict
        )
    }

    private func summary(for hand: JointProbeHand) -> JointProbeHandSummary {
        let handSamples = samples.filter { $0.hand == hand }
        guard !handSamples.isEmpty else {
            return JointProbeHandSummary(
                sampleCount: 0,
                averageTrackedJointCount: 0,
                criticalContinuity: 0
            )
        }

        let averageTrackedJointCount = Double(
            handSamples.reduce(0) { $0 + $1.trackedJointCount }
        ) / Double(handSamples.count)
        let completeCriticalFrames = handSamples.filter {
            $0.trackedCriticalJointCount == expectedCriticalJointCount
        }.count

        return JointProbeHandSummary(
            sampleCount: handSamples.count,
            averageTrackedJointCount: averageTrackedJointCount,
            criticalContinuity: Double(completeCriticalFrames) / Double(handSamples.count)
        )
    }
}
