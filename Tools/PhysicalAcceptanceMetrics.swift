import Darwin
import Foundation

private struct Trial {
    let trialID: String
    let pose: String
    let elbowErrorMM: Double
    let wristErrorMM: Double
    let jitterRMSMM: Double
    let recoverySeconds: Double
}

@main
struct PhysicalAcceptanceMetrics {
    static func main() throws {
        if CommandLine.arguments.contains("--self-test") {
            let poses = ["neutral", "pronated", "supinated", "flexed"]
            let trials = poses.flatMap { pose in
                (1...3).map { repetition in
                    Trial(
                        trialID: "\(pose)-\(repetition)",
                        pose: pose,
                        elbowErrorMM: 8 + Double(repetition),
                        wristErrorMM: 10 + Double(repetition),
                        jitterRMSMM: 2.4,
                        recoverySeconds: 1.1
                    )
                }
            }
            guard coverageError(for: trials) == nil,
                  evaluate(trials, printReport: false) else {
                fatalError("Physical metric evaluator self-test failed")
            }
            print("Physical metric evaluator self-test passed.")
            return
        }

        guard CommandLine.arguments.count == 2 else {
            print("Usage: PhysicalAcceptanceMetrics <completed-results.csv>")
            exit(2)
        }

        let path = CommandLine.arguments[1]
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let lines = contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard lines.first == "trial,pose,elbow_error_mm,wrist_error_mm,jitter_rms_mm,recovery_seconds" else {
            print("Unexpected CSV header.")
            exit(2)
        }

        let trials = try lines.dropFirst().map(parseTrial)
        guard !trials.isEmpty else {
            print("No physical trial rows were supplied.")
            exit(2)
        }
        if let coverageError = coverageError(for: trials) {
            print(coverageError)
            exit(2)
        }

        exit(evaluate(trials, printReport: true) ? 0 : 1)
    }

    private static func parseTrial(_ line: String) throws -> Trial {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        let values = fields.dropFirst(2).compactMap { Double($0) }
        guard fields.count == 6,
              !fields[0].isEmpty,
              !fields[1].isEmpty,
              values.count == 4,
              values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw MetricError.invalidRow(line)
        }
        return Trial(
            trialID: String(fields[0]),
            pose: String(fields[1]).lowercased(),
            elbowErrorMM: values[0],
            wristErrorMM: values[1],
            jitterRMSMM: values[2],
            recoverySeconds: values[3]
        )
    }

    private static func coverageError(for trials: [Trial]) -> String? {
        let uniqueTrialIDs = Set(trials.map(\.trialID))
        guard uniqueTrialIDs.count == trials.count else {
            return "Trial identifiers must be unique."
        }

        let requiredPoses = ["neutral", "pronated", "supinated", "flexed"]
        let counts = Dictionary(grouping: trials, by: \.pose).mapValues(\.count)
        let missing = requiredPoses.filter { counts[$0, default: 0] < 3 }
        guard missing.isEmpty else {
            return "Need at least three trials for each required pose. Missing: \(missing.joined(separator: ", "))."
        }
        return nil
    }

    private static func evaluate(
        _ trials: [Trial],
        printReport: Bool
    ) -> Bool {
        let endpointErrors = trials.flatMap { [$0.elbowErrorMM, $0.wristErrorMM] }.sorted()
        let median = conventionalMedian(endpointErrors)
        let p95 = percentile(endpointErrors, fraction: 0.95)
        let maxJitter = trials.map(\.jitterRMSMM).max() ?? .infinity
        let maxRecovery = trials.map(\.recoverySeconds).max() ?? .infinity

        let passed = median <= 15 && p95 <= 25 && maxJitter <= 5 && maxRecovery <= 2
        if printReport {
            print(String(format: "Median endpoint error: %.1f mm (target <= 15)", median))
            print(String(format: "95th percentile error: %.1f mm (target <= 25)", p95))
            print(String(format: "Worst RMS jitter: %.1f mm (target <= 5)", maxJitter))
            print(String(format: "Worst recovery: %.2f s (target <= 2)", maxRecovery))
            print(passed ? "PHYSICAL METRICS: PASS" : "PHYSICAL METRICS: FAIL")
        }
        return passed
    }

    private static func percentile(_ sorted: [Double], fraction: Double) -> Double {
        guard !sorted.isEmpty else { return .infinity }
        let rank = max(0, Int(ceil(fraction * Double(sorted.count))) - 1)
        return sorted[min(rank, sorted.count - 1)]
    }

    private static func conventionalMedian(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return .infinity }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

private enum MetricError: LocalizedError {
    case invalidRow(String)

    var errorDescription: String? {
        switch self {
        case .invalidRow(let row):
            "Invalid physical-results row: \(row)"
        }
    }
}
