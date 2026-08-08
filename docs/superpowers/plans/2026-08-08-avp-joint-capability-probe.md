# AVP Joint Capability Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a physical-Apple-Vision-Pro probe that proves which wearer hand joints standard visionOS exposes, measures continuity for 30 seconds, and makes the full-body and LiDAR limitations impossible to misread.

**Architecture:** Extend the existing `UpperLimbPOC` visionOS target with a pure-Swift metrics core, an independent hand-only ARKit start path, a mixed-reality joint-sphere visualizer, and a compact status window. Keep camera/body-pose inference out of this slice because it requires Apple enterprise main-camera access; keep scene reconstruction out because it has no named anatomical joints.

**Tech Stack:** Swift 5 source mode, SwiftUI, RealityKit, ARKit `HandTrackingProvider`, Xcode 27 beta, existing shell validation pipeline.

---

### Task 1: Define and test the continuity report

**Files:**
- Create: `UpperLimbPOC/JointProbeMetrics.swift`
- Create: `Tools/JointProbeMetricsCheck.swift`
- Modify: `Tools/validate.sh`

- [ ] **Step 1: Write the failing metrics check**

Create `Tools/JointProbeMetricsCheck.swift` with three real scenarios:

```swift
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
        var accumulator = JointProbeAccumulator(expectedJointCount: 27, expectedCriticalJointCount: 4)
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
        try require(report.verdict == .continuityPass, "stable critical joints should pass")
        try require(report.right.criticalContinuity > 0.96, "critical continuity should be measured")
    }

    private static func noSignalIsReported() throws {
        var accumulator = JointProbeAccumulator(expectedJointCount: 27, expectedCriticalJointCount: 4)
        accumulator.start(at: 0)
        let report = accumulator.finish(at: 30)
        try require(report.verdict == .noSignal, "no hand updates should report no signal")
    }

    private static func shortRunIsInsufficient() throws {
        var accumulator = JointProbeAccumulator(expectedJointCount: 27, expectedCriticalJointCount: 4)
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
        try require(report.verdict == .insufficientDuration, "short run should not pass")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error { let message: String }
```

- [ ] **Step 2: Run the check to verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer \
  xcrun swiftc -parse-as-library \
  UpperLimbPOC/JointProbeMetrics.swift \
  Tools/JointProbeMetricsCheck.swift \
  -o .build/joint-probe-metrics-check
```

Expected: failure because `JointProbeMetrics.swift` does not exist.

- [ ] **Step 3: Implement the minimal metrics core**

Create `UpperLimbPOC/JointProbeMetrics.swift` with:

```swift
import Foundation

enum JointProbeHand: String, Sendable { case left, right }
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
    let expectedJointCount: Int
    let expectedCriticalJointCount: Int
    private(set) var startedAt: Double?
    private var samples: [Sample] = []

    mutating func start(at timestamp: Double) { startedAt = timestamp; samples = [] }
    mutating func record(timestamp: Double, hand: JointProbeHand, trackedJointCount: Int, trackedCriticalJointCount: Int)
    mutating func finish(at timestamp: Double) -> JointProbeReport
}
```

Clamp counts into their expected ranges. Calculate per-hand averages and critical-frame continuity. Verdict priority is `noSignal`, then `insufficientDuration` for runs under 25 seconds, then `continuityPass` when either hand has at least 30 samples and at least 90% complete critical frames, otherwise `continuityNeedsWork`.

- [ ] **Step 4: Run the metrics check to verify GREEN**

Run the command from Step 2, then:

```bash
.build/joint-probe-metrics-check
```

Expected: `Joint capability probe metric checks passed`.

- [ ] **Step 5: Add the metrics stage to the validator**

Insert a stage after hybrid landmark registration in `Tools/validate.sh` that compiles and runs the two metrics files. Renumber the stage labels and final message consistently.

### Task 2: Add an independent hand-only tracking and recording path

**Files:**
- Modify: `Tools/validate.sh`
- Modify: `UpperLimbPOC/LandmarkTrackingService.swift`

- [ ] **Step 1: Add failing source-contract assertions**

Before production edits, add validator assertions for:

```bash
rg -q 'func startHandJointProbe' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'HandSkeleton.JointName.allCases' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'JointProbeAccumulator' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'func beginProbeMeasurement' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
```

- [ ] **Step 2: Run the validator and verify the source contract fails**

Run `Tools/validate.sh` and confirm it stops on the first missing source assertion.

- [ ] **Step 3: Expand live hand transforms to all runtime joints**

In `consume(_ anchor: HandAnchor)`, replace the five-joint list with `HandSkeleton.JointName.allCases`. Continue accepting only joints where `joint.isTracked` is true. Do not reinterpret `.forearmArm` as an elbow.

- [ ] **Step 4: Add hand-only provider startup**

Add `startHandJointProbe()` that:

- reports `.simulatorUnavailable` in Simulator;
- checks `HandTrackingProvider.isSupported`;
- requests `HandTrackingProvider.requiredAuthorizations` only;
- starts `ARKitSession` with one `HandTrackingProvider`;
- sets `handPhase = .running` and consumes `anchorUpdates` through the existing path;
- reports denial or failure explicitly.

It must not require the ELBOW/WRIST image markers.

- [ ] **Step 5: Add the 30-second recorder**

Publish:

```swift
@Published private(set) var isProbeRecording = false
@Published private(set) var probeReport: JointProbeReport?
@Published private(set) var probeSecondsRemaining = 30
```

Add `beginProbeMeasurement(durationSeconds: Int = 30)`, `finishProbeMeasurement()`, and `resetProbeMeasurement()`. Use `ProcessInfo.processInfo.systemUptime` for monotonic timestamps. Record one sample for every hand-anchor update, including zero-joint updates. Critical joints are wrist, index knuckle, index intermediate base, and index intermediate tip. Cancel the timer task in `stop()`.

- [ ] **Step 6: Run the pure metrics check and source assertions**

Expected: metrics check passes and all new source-contract assertions are present.

### Task 3: Visualize joints and disclose capability boundaries

**Files:**
- Create: `UpperLimbPOC/JointProbeView.swift`
- Create: `UpperLimbPOC/JointProbeImmersiveView.swift`
- Modify: `UpperLimbPOC/UpperLimbPOCApp.swift`
- Modify: `UpperLimbPOC/ContentView.swift`
- Modify: `RadiographicAnatomyPOC.xcodeproj/project.pbxproj`
- Modify: `Tools/validate.sh`

- [ ] **Step 1: Add failing UI/source assertions**

Add validator assertions for the `JointProbe` window, `JointProbeSpace` mixed immersive space, the two new source files, the phrases `wearer's hands only`, `Whole-body ARKit`, and `LiDAR scene mesh has no joint labels`, and project inclusion in the Vision target.

- [ ] **Step 2: Run the validator and verify RED**

Expected: failure because the new views and scene declarations do not exist.

- [ ] **Step 3: Build the status window**

`JointProbeView` must show:

- provider support/permission/running state;
- live left and right tracked-joint counts against `HandSkeleton.JointName.allCases.count`;
- `Start tracking`, `Run 30-second continuity test`, `Stop & summarize`, and `Reset` controls;
- latest duration, sample count, average joint count, critical continuity, and verdict;
- persistent disclosure that hand tracking covers the wearer's hands only;
- persistent disclosure that standard visionOS has no whole-body ARKit provider;
- persistent disclosure that LiDAR/scene reconstruction has no named joint labels;
- a note that continuity does not prove anatomical accuracy.

Opening the probe starts `JointProbeSpace`; leaving it stops tracking.

- [ ] **Step 4: Build the mixed-reality visualizer**

`JointProbeImmersiveView` creates one 8 mm sphere per runtime joint for both hands. Left-hand joints are cyan and right-hand joints are orange. Each update positions visible spheres from the world transform and hides missing joints. No lines, body mesh, inferred elbow, camera frames, or stored images are added.

- [ ] **Step 5: Wire the scenes and launcher**

Add `WindowGroup(id: "JointProbe")` and `ImmersiveSpace(id: "JointProbeSpace")` with `.mixed` immersion style to `UpperLimbPOCApp`. Add a prominent `Test AVP joint detection` button to `ContentView` that opens the probe window.

- [ ] **Step 6: Add project references**

Add the three new Swift files (`JointProbeMetrics`, `JointProbeView`, `JointProbeImmersiveView`) to the `UpperLimbPOC` group and Vision target sources. Do not add ARKit/SwiftUI files to the iOS companion target.

- [ ] **Step 7: Run a clean device-SDK build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer \
  xcodebuild -project RadiographicAnatomyPOC.xcodeproj \
  -scheme UpperLimbPOC -sdk xros \
  -derivedDataPath .build/joint-probe-device \
  CODE_SIGNING_ALLOWED=NO clean build
```

Expected: `** BUILD SUCCEEDED **`.

### Task 4: Document the physical experiment and product decision

**Files:**
- Create: `JOINT_CAPABILITY_PROBE.md`
- Modify: `README.md`
- Modify: `CURRENT_STATUS.md`
- Modify: `PRODUCT_DEVELOPMENT_DOCUMENT.md`
- Modify: `Tools/validate.sh`

- [ ] **Step 1: Add failing documentation assertions**

Require the protocol file plus the terms `wearer hand`, `another person`, `enterprise main-camera`, `continuity`, `accuracy`, and `kill criterion`.

- [ ] **Step 2: Write the run card**

Document this exact physical sequence:

1. Connect and trust Apple Vision Pro; enable Developer Mode.
2. Select the user’s Apple Development team for `UpperLimbPOC` in Xcode.
3. Choose the physical Vision Pro destination and Run.
4. Open `Test AVP joint detection`; allow Hands Tracking.
5. Hold both hands visible, then run the 30-second test through neutral, finger flexion, wrist rotation, brief occlusion, and reacquisition.
6. Record the on-screen verdict and screen recording.
7. Interpret `continuityPass` only as a continuity result, not an accuracy result.

The adopt condition is at least one hand with 90% critical-joint continuity over the 30-second run. The kill/reshape condition is failure to reach this on two controlled runs, or inability to maintain a truthful stale/lost state. Full-body/other-person detection remains blocked unless the enterprise-camera entitlement is approved or an external camera provider is adopted.

- [ ] **Step 3: Update product status and backlog**

Record the probe as the next physical research spike. Keep clinical use, internal-bone localization, and another-person full-body detection out of scope.

- [ ] **Step 4: Run documentation/source assertions**

Expected: all static assertions pass.

### Task 5: Full verification and physical handoff

**Files:**
- Verify all modified files

- [ ] **Step 1: Check the diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only planned files changed.

- [ ] **Step 2: Run the full Xcode 27 validation gate**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer ./Tools/validate.sh
```

Expected: all pure logic, source invariants, simulator/device builds, and analyzers pass.

- [ ] **Step 3: Run strict Vision builds**

Run the Vision simulator and device builds with `SWIFT_STRICT_CONCURRENCY=complete`, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, and `GCC_TREAT_WARNINGS_AS_ERRORS=YES`.

Expected: both builds succeed with no warnings promoted to errors.

- [ ] **Step 4: Check physical device visibility**

Run `xcrun devicectl list devices`. If no Vision Pro is connected, label the physical run `[BLOCKED]`, open the Xcode project for Marcel, and provide the six-step run card. Do not claim device behavior from Simulator.

- [ ] **Step 5: Commit the verified slice**

Stage only planned files and commit:

```bash
git commit -m "feat: add AVP joint capability probe"
```

Do not push unless Marcel asks or the existing repository workflow explicitly requires it.

## Self-review

- Spec coverage: the plan tests standard visionOS hand joints, measures continuity, visualizes world transforms, and explicitly rejects unsupported full-body/LiDAR claims.
- Scope: enterprise camera, external iPhone pose, accuracy measurement, patient data, and clinical use remain separate future slices.
- Type consistency: `JointProbeAccumulator`, `JointProbeReport`, and the published service properties use the same names across tests, service, UI, and validator.
- Placeholder scan: no unfinished implementation step or deferred error-handling instruction remains in the executable slice.
