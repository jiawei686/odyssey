# iPhone OpenCV Body Scanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an on-device iPhone 17 Pro Max scanner that uses OpenCV DNN to estimate one participant's upper-limb landmarks, including 21 landmarks on each hand, then freezes a privacy-preserving structured joint observation and supplies the detection side of `UL-INTEGRATION-001`.

**Architecture:** Extend only the existing `UpperLimbCompanion` iOS target. A Swift AVFoundation capture/depth layer feeds pixel buffers to a narrow Objective-C++ bridge containing pinned OpenCV Zoo decoders; pure Swift association and qualification logic produces a versioned `JointScan`; a separate SwiftUI route renders the live result without persisting pixels. OpenCV dependency proof and model-fixture execution are hard gates before the camera UI is connected.

**Tech Stack:** Swift 5 source mode, SwiftUI, AVFoundation, CoreMedia, CoreVideo, Objective-C++/C++17, OpenCV 4.13.0 DNN, four pinned OpenCV Zoo ONNX models, XCTest plus the repository's standalone Swift checks, Xcode 27 beta, iOS 18.

---

## Scope and execution topology

Implement the approved design in `docs/superpowers/specs/2026-08-08-iphone-opencv-body-scanner-design.md`. Do not add Apple Vision body/hand pose APIs, AVP camera access, image export, or a second network stack. Transport and anatomy registration belong to the additive `UL-INTEGRATION-001` plan and must reuse the existing peer/registration primitives while explicitly implementing the missing measured cross-device calibration.

The user requested three specialist tracks:

- **iPhone/OpenCV track:** Tasks 1–6.
- **Scanner UI/UX track:** Task 7 can proceed against the Task 2 contracts and a debug fixture runtime while Tasks 3–6 continue.
- **iPhone–AVP coordination track:** the active `UL-INTEGRATION-001` plan must implement metric projection and measured cross-device calibration before consuming the frozen shared joint-frame contract.

Parallel implementation is safe only after Task 2 is committed. The OpenCV and UI workers must create disjoint files under `UpperLimbPOC/BodyScanner/`; neither may edit `project.pbxproj`, `Tools/validate.sh`, `CompanionApp.swift`, `CompanionContentView.swift`, or `InfoCompanion.plist`. Task 8 is the single integration point for those shared files. Preserve all pre-existing uncommitted AVP joint-probe edits and the signing team `QLYUY93X5V`.

## Pinned dependencies

- OpenCV source tag `4.13.0`, resolved commit `fe38fc608f6acb8b68953438a62305d8318f4fcd`.
- OpenCV Zoo commit `47534e27c9851bb1128ccc0102f1145e27f23f98`.
- `person_detection_mediapipe_2023mar.onnx`: `47fd5599d6fa17608f03e0eb0ae230baa6e597d7e8a2c8199fe00abea55a701f`.
- `pose_estimation_mediapipe_2023mar.onnx`: `9d89c599319a18fb7d2e28451a883476164543182bafca5f09eb2cf767ed2f3f`.
- `palm_detection_mediapipe_2023feb.onnx`: `78ff51c38496b7fc8b8ebdb6cc8c1abb02fa6c38427c6848254cdaba57fcce7c`.
- `handpose_estimation_mediapipe_2023feb.onnx`: `db0898ae717b76b075d9bf563af315b29562e11f8df5027a1ef07b02bef6d81c`.

The pinned MP-HandPose output has one hand-presence confidence and one handedness score, not 21 per-landmark confidence values. Phase 1 must never copy the global hand score onto every finger point. Hand readiness therefore uses global hand confidence, finite/in-frame point count, and temporal stability; MP-Pose arm readiness continues to use per-landmark visibility/presence.

Do not use the downloadable `opencv-4.13.0-ios-framework.zip`. Inspection shows it is a legacy five-architecture fat framework, not an XCFramework with distinct arm64 device and arm64 simulator slices. Build `opencv2.xcframework` from the pinned source with separate `iphoneos arm64` and `iphonesimulator arm64,x86_64` libraries.

## File map

### Dependency and provenance

- Modify `.gitignore` — ignore generated OpenCV/model artifacts.
- Create `Tools/bootstrap_body_scanner_dependencies.sh` — fetch, verify, and build pinned dependencies.
- Create `ThirdParty/BodyScanner/README.md` — versions, hashes, build command, and licences.
- Create `ThirdParty/BodyScanner/models.sha256` — executable model integrity manifest.
- Create `ThirdParty/BodyScanner/LICENSE-OpenCV.txt` — verbatim Apache-2.0 notice from OpenCV 4.13.0.
- Create `ThirdParty/BodyScanner/LICENSE-OpenCV-Zoo.txt` — verbatim Apache-2.0 notice from the pinned Zoo commit.
- Generate, but do not commit, `Vendor/OpenCV/opencv2.xcframework/` and `UpperLimbPOC/BodyScannerModels/*.onnx`.

### Pure domain and inference

- Create `UpperLimbPOC/BodyScanner/BodyScannerJointModels.swift` — stable joint identifiers and `JointScan` schema.
- Create `UpperLimbPOC/BodyScanner/BodyScannerHandAssociation.swift` — participant-side assignment and ambiguity.
- Create `UpperLimbPOC/BodyScanner/BodyScannerQualification.swift` — one-second/ten-frame readiness state machine.
- Create `UpperLimbPOC/BodyScanner/OpenCV/MPPersonDetector.hpp/.cpp` — person detector wrapper.
- Create `UpperLimbPOC/BodyScanner/OpenCV/MPPoseEstimator.hpp/.cpp` — 33-point pose wrapper.
- Create `UpperLimbPOC/BodyScanner/OpenCV/MPPalmDetector.hpp/.cpp` — palm detector wrapper.
- Create `UpperLimbPOC/BodyScanner/OpenCV/MPHandPoseEstimator.hpp/.cpp` — 21-point hand wrapper.
- Create `UpperLimbPOC/BodyScanner/OpenCV/OpenCVBodyScannerBridge.h/.mm` — Swift-safe pixel-buffer bridge.
- Create `UpperLimbPOC/UpperLimbCompanion-Bridging-Header.h` — expose only the bridge header.

### Capture and runtime

- Create `UpperLimbPOC/BodyScanner/BodyScannerFrame.swift` — synchronized video/depth frame value.
- Create `UpperLimbPOC/BodyScanner/BodyScannerDepthAdapter.swift` — optional metric depth sampling/unprojection.
- Create `UpperLimbPOC/BodyScanner/BodyScannerCaptureService.swift` — rear camera session and frame delivery.
- Create `UpperLimbPOC/BodyScanner/BodyScannerRuntime.swift` — throttled inference, association, qualification, and events.
- Create `UpperLimbPOC/BodyScanner/BodyScannerEnvironment.swift` — live/debug dependency assembly.

### UI and presentation

- Create `UpperLimbPOC/BodyScanner/BodyScannerViewModel.swift`.
- Create `UpperLimbPOC/BodyScanner/BodyScannerPresentation.swift`.
- Create `UpperLimbPOC/BodyScanner/BodyScannerScreen.swift`.
- Create `UpperLimbPOC/BodyScanner/BodyScannerIntroView.swift`.
- Create `UpperLimbPOC/BodyScanner/CameraPreviewView.swift`.
- Create `UpperLimbPOC/BodyScanner/PreviewProjection.swift`.
- Create `UpperLimbPOC/BodyScanner/SkeletonRenderPlan.swift`.
- Create `UpperLimbPOC/BodyScanner/SkeletonOverlayView.swift`.
- Create `UpperLimbPOC/BodyScanner/ScanGuidanceResolver.swift`.
- Create `UpperLimbPOC/BodyScanner/ScannerStatusPanel.swift`.
- Create `UpperLimbPOC/BodyScanner/FrozenScanSummaryView.swift`.
- Create `UpperLimbPOC/BodyScanner/ScannerErrorView.swift`.
- Create `UpperLimbPOC/BodyScanner/ScannerFixtureRuntime.swift`.
- Create `UpperLimbPOC/BodyScanner/ScannerAccessibilityID.swift`.

### Tests and integration

- Create `Tools/BodyScannerCoreCheck.swift` — standalone domain regression checks.
- Create `Tools/BodyScannerPresentationCheck.swift` — projection/guidance/render-plan checks.
- Create `UpperLimbCompanionTests/OpenCVBodyScannerPipelineTests.swift` — model load and fixture inference.
- Create `UpperLimbCompanionUITests/BodyScannerFlowUITests.swift` — deterministic route tests.
- Create `Tools/body_scanner_physical_template.csv` and `Tools/BodyScannerPhysicalAcceptance.swift`.
- Modify `UpperLimbPOC/CompanionApp.swift`, `CompanionContentView.swift`, and `InfoCompanion.plist`.
- Modify `RadiographicAnatomyPOC.xcodeproj/project.pbxproj` and `RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbCompanion.xcscheme`.
- Modify `Tools/validate.sh`, `README.md`, `PRODUCT_DEVELOPMENT_DOCUMENT.md`, and `CURRENT_STATUS.md`.

---

### Task 1: Prove and pin OpenCV/model dependencies

**Files:**
- Modify: `.gitignore`
- Create: `Tools/bootstrap_body_scanner_dependencies.sh`
- Create: `ThirdParty/BodyScanner/README.md`
- Create: `ThirdParty/BodyScanner/models.sha256`
- Create: `ThirdParty/BodyScanner/LICENSE-OpenCV.txt`
- Create: `ThirdParty/BodyScanner/LICENSE-OpenCV-Zoo.txt`

- [ ] **Step 1: Add the failing dependency contract**

Insert this block near the start of `Tools/validate.sh`, before any Xcode build:

```bash
BODY_SCANNER_MODELS="$PROJECT_DIR/UpperLimbPOC/BodyScannerModels"
OPENCV_XCFRAMEWORK="$PROJECT_DIR/Vendor/OpenCV/opencv2.xcframework"

test -d "$OPENCV_XCFRAMEWORK" || {
    echo "Missing OpenCV XCFramework; run Tools/bootstrap_body_scanner_dependencies.sh" >&2
    exit 1
}

(
    cd "$PROJECT_DIR"
    shasum -a 256 -c ThirdParty/BodyScanner/models.sha256
)
```

- [ ] **Step 2: Run the validator and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer Tools/validate.sh
```

Expected: exit non-zero with `Missing OpenCV XCFramework`.

- [ ] **Step 3: Add generated-artifact exclusions**

Append exactly:

```gitignore
.dependencies/
Vendor/OpenCV/opencv2.xcframework/
UpperLimbPOC/BodyScannerModels/*.onnx
UpperLimbCompanionTests/Fixtures/*.webp
```

- [ ] **Step 4: Create the model manifest**

Create `ThirdParty/BodyScanner/models.sha256`:

```text
47fd5599d6fa17608f03e0eb0ae230baa6e597d7e8a2c8199fe00abea55a701f  UpperLimbPOC/BodyScannerModels/person_detection_mediapipe_2023mar.onnx
9d89c599319a18fb7d2e28451a883476164543182bafca5f09eb2cf767ed2f3f  UpperLimbPOC/BodyScannerModels/pose_estimation_mediapipe_2023mar.onnx
78ff51c38496b7fc8b8ebdb6cc8c1abb02fa6c38427c6848254cdaba57fcce7c  UpperLimbPOC/BodyScannerModels/palm_detection_mediapipe_2023feb.onnx
db0898ae717b76b075d9bf563af315b29562e11f8df5027a1ef07b02bef6d81c  UpperLimbPOC/BodyScannerModels/handpose_estimation_mediapipe_2023feb.onnx
```

- [ ] **Step 5: Create the bootstrap script**

The script must:

1. clone OpenCV tag `4.13.0` into `.dependencies/opencv-4.13.0`;
2. reject a source HEAD other than `fe38fc608f6acb8b68953438a62305d8318f4fcd`;
3. run:

```bash
python3 .dependencies/opencv-4.13.0/platforms/apple/build_xcframework.py \
  --out .dependencies/opencv-4.13.0-build \
  --iphoneos_archs arm64 \
  --iphonesimulator_archs arm64,x86_64 \
  --build_only_specified_archs
```

4. copy the resulting `opencv2.xcframework` to `Vendor/OpenCV/`;
5. download the four model URLs from the pinned Zoo commit into `UpperLimbPOC/BodyScannerModels/`;
6. verify `ThirdParty/BodyScanner/models.sha256`; and
7. stop on every clone, build, download, or checksum failure.

Use this download function so partial or corrupt models never become valid inputs:

```bash
download_verified() {
    local url="$1"
    local destination="$2"
    local expected="$3"
    local temporary="${destination}.partial"

    curl -L --fail --silent --show-error "$url" -o "$temporary"
    local actual
    actual="$(shasum -a 256 "$temporary" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        rm -f "$temporary"
        echo "Checksum mismatch for $destination" >&2
        return 1
    fi
    mv "$temporary" "$destination"
}
```

Use raw URLs rooted at:

```text
https://github.com/opencv/opencv_zoo/raw/47534e27c9851bb1128ccc0102f1145e27f23f98/models/
```

- [ ] **Step 6: Record provenance and licences**

`ThirdParty/BodyScanner/README.md` must list the exact pins/hashes above, state that the binaries are generated and not committed, link each upstream model directory, and state that OpenCV and these four model directories are Apache-2.0. Copy each upstream licence verbatim into the two licence files.

- [ ] **Step 7: Run the bootstrap and verify the slices**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer \
  Tools/bootstrap_body_scanner_dependencies.sh

plutil -p Vendor/OpenCV/opencv2.xcframework/Info.plist
```

Expected: two available libraries, one `ios-arm64` and one `ios-arm64_x86_64-simulator`, followed by four successful model checks.

- [ ] **Step 8: Apply the dependency kill criterion**

Stop Phase 1 before UI integration if the XCFramework cannot be produced, does not expose `opencv2/dnn.hpp`, or either iOS slice cannot link in a minimal companion build. Do not fall back to Apple Vision or a floating third-party binary.

- [ ] **Step 9: Commit**

```bash
git add .gitignore Tools/bootstrap_body_scanner_dependencies.sh ThirdParty/BodyScanner Tools/validate.sh
git commit -m "build: pin iPhone OpenCV scanner dependencies"
```

Do not stage `.dependencies/`, the XCFramework, or ONNX binaries.

---

### Task 2: Define the joint schema, association, and qualification core

**Files:**
- Create: `UpperLimbPOC/BodyScanner/BodyScannerJointModels.swift`
- Create: `UpperLimbPOC/BodyScanner/BodyScannerHandAssociation.swift`
- Create: `UpperLimbPOC/BodyScanner/BodyScannerQualification.swift`
- Create: `Tools/BodyScannerCoreCheck.swift`
- Modify: `Tools/validate.sh`

- [ ] **Step 1: Write the failing standalone core check**

Create `Tools/BodyScannerCoreCheck.swift` with these named cases:

```swift
@main
struct BodyScannerCoreCheck {
    static func main() throws {
        try stableIdentifierCountsAreExact()
        try proximityAndHandednessAssociateBothHands()
        try conflictingHandEvidenceIsAmbiguous()
        try nineFramesCannotQualify()
        try lessThanOneSecondCannotQualify()
        try tenStableFramesOverOneSecondQualify()
        try sideSwitchResetsTheWindow()
        try missingDepthRemainsNil()
        print("Body scanner core checks passed")
    }
}
```

`stableIdentifierCountsAreExact` asserts `BodyLandmarkName.allCases.count == 33` and `HandLandmarkName.allCases.count == 21`. Build a qualified frame fixture with six arm points at per-landmark confidence `0.90`, each hand at global confidence `0.90` with 17 finite in-frame points, one participant, a full-frame-safe bounding box, no ambiguity, and stability RMS below the configured limit.

- [ ] **Step 2: Run the check and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer \
  xcrun swiftc -parse-as-library \
  UpperLimbPOC/BodyScanner/BodyScannerJointModels.swift \
  UpperLimbPOC/BodyScanner/BodyScannerHandAssociation.swift \
  UpperLimbPOC/BodyScanner/BodyScannerQualification.swift \
  Tools/BodyScannerCoreCheck.swift \
  -o .build/body-scanner-core-check
```

Expected: failure because the three production files do not exist.

- [ ] **Step 3: Define stable joint and coordinate types**

`BodyScannerJointModels.swift` must define:

```swift
enum ParticipantSide: String, Codable, Sendable { case left, right }
enum LandmarkVisibility: String, Codable, Sendable {
    case observed, estimated, unavailable, ambiguous
}
enum LandmarkSource: String, Codable, Sendable { case mpPose, mpHandPose }
enum ConfidenceScope: String, Codable, Sendable {
    case landmark, hand, unavailable
}
enum SensorOrientation: String, Codable, Sendable {
    case landscapeLeft, landscapeRight
}

struct NormalizedImagePoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

struct MetricPoint3D: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

struct JointObservation<Name: RawRepresentable & Codable & Sendable>: Codable, Sendable
where Name.RawValue == String {
    let name: Name
    let source: LandmarkSource
    let normalizedImagePoint: NormalizedImagePoint?
    let pixelPoint: SIMD2<Double>?
    let modelRelativeZ: Double?
    let depthMeters: Double?
    let cameraPointMeters: MetricPoint3D?
    let confidence: Double?
    let confidenceScope: ConfidenceScope
    let visibility: LandmarkVisibility
    let frameTimestamp: TimeInterval
}
```

Define all 33 MediaPipe body names in model-index order and all 21 hand names in model-index order. Keep unavailable points as `nil`; never substitute `(0, 0)` or a fake depth. Add `HandObservation` with participant side, one global hand confidence, handedness score, and 21 joint observations whose individual confidence is nil/`unavailable`. Add `JointScan.schemaVersion = 1`, UUID, capture timestamp, sensor dimensions/orientation, participant count, body landmarks, two `HandObservation` values, and qualification metadata. Do not make `JointScan` persistable through app storage.

- [ ] **Step 4: Implement deterministic hand association**

Use this public contract:

```swift
struct HandCandidate: Equatable, Sendable {
    let candidateID: Int
    let wrist: NormalizedImagePoint
    let modelSide: ParticipantSide?
    let handednessConfidence: Double
    let landmarks: [HandLandmarkName: RawLandmark]
}

enum HandAssociationResult: Equatable, Sendable {
    case associated(left: HandCandidate, right: HandCandidate)
    case partial(side: ParticipantSide, hand: HandCandidate)
    case ambiguous
    case unavailable
}

struct BodyScannerHandAssociator {
    func associate(
        candidates: [HandCandidate],
        leftBodyWrist: NormalizedImagePoint?,
        rightBodyWrist: NormalizedImagePoint?,
        previous: [ParticipantSide: Int]
    ) -> HandAssociationResult
}
```

Evaluate both two-hand permutations. Cost is normalized wrist distance plus `0.25` for a model-side contradiction above handedness confidence `0.70`, minus `0.05` for temporal candidate continuity. Require the best permutation to beat the alternative by at least `0.05`; otherwise return `ambiguous`. Reject more than two accepted hand candidates instead of silently choosing.

- [ ] **Step 5: Implement the qualification state machine**

Use:

```swift
enum ScanBlockReason: String, Equatable, Sendable {
    case noParticipant, multipleParticipants, bodyClipped, bodyTooSmall
    case missingArmLandmarks, missingLeftHand, missingRightHand
    case sideAmbiguous, unstable
}

enum ScanQualification: Equatable, Sendable {
    case blocked(ScanBlockReason)
    case stabilizing(frameCount: Int, elapsedSeconds: Double, generation: UInt64)
    case qualified(generation: UInt64)
}

struct BodyScannerQualificationAccumulator {
    static let confidenceThreshold = 0.50
    static let handConfidenceThreshold = 0.50
    static let requiredHandLandmarks = 17
    static let requiredFrames = 10
    static let requiredSeconds = 1.0

    mutating func consume(_ frame: BodyScannerFrameObservation) -> ScanQualification
    mutating func reset()
}
```

The six required arm identifiers are left/right shoulder, elbow, and wrist. Reset and increment `generation` immediately for participant-count changes, clipped/small body, body threshold loss, hand-level confidence below `0.50`, fewer than 17 finite in-frame points on either hand, ambiguity, a side switch, or stability failure. Qualify only when both time and frame-count requirements are met. Depth never blocks 2D qualification. A hand point must not gain a fabricated per-point confidence.

- [ ] **Step 6: Run the check and verify GREEN**

Compile with the Step 2 command, then run:

```bash
.build/body-scanner-core-check
```

Expected: `Body scanner core checks passed`.

- [ ] **Step 7: Add the core stage to validation**

Add the exact compile/run command to `Tools/validate.sh` before Xcode builds and update stage numbering without removing any existing checks.

- [ ] **Step 8: Commit**

```bash
git add UpperLimbPOC/BodyScanner/BodyScannerJointModels.swift \
  UpperLimbPOC/BodyScanner/BodyScannerHandAssociation.swift \
  UpperLimbPOC/BodyScanner/BodyScannerQualification.swift \
  Tools/BodyScannerCoreCheck.swift Tools/validate.sh
git commit -m "feat: define body scanner joint qualification core"
```

---

### Task 3: Port the four OpenCV Zoo model wrappers

**Files:**
- Create: `UpperLimbPOC/BodyScanner/OpenCV/MPPersonDetector.hpp`
- Create: `UpperLimbPOC/BodyScanner/OpenCV/MPPersonDetector.cpp`
- Create: `UpperLimbPOC/BodyScanner/OpenCV/MPPoseEstimator.hpp`
- Create: `UpperLimbPOC/BodyScanner/OpenCV/MPPoseEstimator.cpp`
- Create: `UpperLimbPOC/BodyScanner/OpenCV/MPPalmDetector.hpp`
- Create: `UpperLimbPOC/BodyScanner/OpenCV/MPPalmDetector.cpp`
- Create: `UpperLimbPOC/BodyScanner/OpenCV/MPHandPoseEstimator.hpp`
- Create: `UpperLimbPOC/BodyScanner/OpenCV/MPHandPoseEstimator.cpp`

- [ ] **Step 1: Add failing source-contract checks**

Add validator checks for all eight files and these constants:

```bash
rg -q 'cv::Size(224, 224)' "$PROJECT_DIR/UpperLimbPOC/BodyScanner/OpenCV/MPPersonDetector.cpp"
rg -q 'cv::Size(256, 256)' "$PROJECT_DIR/UpperLimbPOC/BodyScanner/OpenCV/MPPoseEstimator.cpp"
rg -q 'cv::Size(192, 192)' "$PROJECT_DIR/UpperLimbPOC/BodyScanner/OpenCV/MPPalmDetector.cpp"
rg -q 'cv::Size(224, 224)' "$PROJECT_DIR/UpperLimbPOC/BodyScanner/OpenCV/MPHandPoseEstimator.cpp"
rg -q 'DNN_TARGET_CPU' "$PROJECT_DIR/UpperLimbPOC/BodyScanner/OpenCV/MPPersonDetector.cpp"
```

- [ ] **Step 2: Run validation and verify RED**

Expected: failure on the first missing wrapper.

- [ ] **Step 3: Port person detection**

Port `models/person_detection_mediapipe/demo.cpp` from Zoo commit `47534e27...` into `MPPersonDetector`. Keep the official 224×224 letterbox preprocessing, `127.5` mean, `1/127.5` scale, BGR-to-RGB swap, MediaPipe anchors, sigmoid clamp, `0.50` score threshold, `0.30` NMS threshold, and maximum two returned candidates. Remove camera, rendering, saving, and command-line code.

Expose:

```cpp
struct PersonDetection {
    cv::Rect2f bounds;
    std::array<cv::Point2f, 4> alignmentLandmarks;
    float confidence;
};

class MPPersonDetector {
public:
    explicit MPPersonDetector(const std::string& modelPath);
    std::vector<PersonDetection> infer(const cv::Mat& bgrImage);
};
```

- [ ] **Step 4: Port pose estimation**

Port the Zoo MP-Pose crop/rotation and inverse transform exactly. The wrapper consumes one accepted `PersonDetection`, uses the 256×256 RGB-normalized input, and returns exactly 33 points when inference succeeds:

```cpp
struct PoseLandmark {
    cv::Point2f imagePoint;
    float modelRelativeZ;
    float visibility;
    float presence;
};

class MPPoseEstimator {
public:
    explicit MPPoseEstimator(const std::string& modelPath);
    std::optional<std::array<PoseLandmark, 33>> infer(
        const cv::Mat& bgrImage,
        const PersonDetection& person
    );
};
```

Use `min(visibility, presence)` as the exported confidence after applying the upstream output activation. Do not export the segmentation mask in Phase 1.

- [ ] **Step 5: Port palm detection**

Port `models/palm_detection_mediapipe/demo.cpp` at the pinned commit. Preserve the 192×192 letterbox transform, MediaPipe anchors, seven palm landmarks, `0.50` score threshold, and `0.30` NMS. Limit accepted results to two and return all detections before body-side association.

- [ ] **Step 6: Port hand pose estimation**

Port the pinned `mp_handpose.py` crop, pad, palm rotation, 224×224 RGB normalization, inverse rotation, and 21-point output transform into C++17. Expose screen-image X/Y, model-relative Z, handedness score, and one global hand-presence confidence. Do not label the model's monocular/world output as measured metres and do not attach the global score to individual points.

```cpp
struct HandPoseResult {
    std::array<cv::Point3f, 21> imageLandmarks;
    float handedness;
    float handConfidence;
};
```

- [ ] **Step 7: Preserve provenance in every port**

Start every ported file with the upstream source URL, pinned commit, and Apache-2.0 SPDX header. Record intentional changes: no visualization/I/O, CPU backend only, typed outputs, and candidate limits.

- [ ] **Step 8: Compile the wrapper translation units for both iOS SDKs**

Run a clean companion simulator and device-SDK build after Task 4 wires the files. At this task boundary, run `clang++ -fsyntax-only` against the simulator slice headers if the Xcode references are not yet present.

- [ ] **Step 9: Commit**

```bash
git add UpperLimbPOC/BodyScanner/OpenCV Tools/validate.sh
git commit -m "feat: port OpenCV Zoo body and hand models"
```

---

### Task 4: Add the Objective-C++ bridge and fixture test target

**Files:**
- Create: `UpperLimbPOC/BodyScanner/OpenCV/OpenCVBodyScannerBridge.h`
- Create: `UpperLimbPOC/BodyScanner/OpenCV/OpenCVBodyScannerBridge.mm`
- Create: `UpperLimbPOC/UpperLimbCompanion-Bridging-Header.h`
- Create: `UpperLimbCompanionTests/OpenCVBodyScannerPipelineTests.swift`
- Create: `UpperLimbCompanionTests/Fixtures/PROVENANCE.md`
- Modify: `RadiographicAnatomyPOC.xcodeproj/project.pbxproj`
- Modify: `RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbCompanion.xcscheme`

- [ ] **Step 1: Write the failing fixture test**

Create a hosted iOS XCTest target `UpperLimbCompanionTests`. Its first test must load the four model URLs from `Bundle.main`, initialize `OpenCVBodyScannerBridge`, and assert `modelStatus.loadedModelCount == 4` and `openCVVersion == "4.13.0"`. A second test invokes decoder-test hooks with deterministic synthetic tensors and asserts person candidate count, 33 pose points, palm candidate count, and 21 hand points.

```swift
func testPinnedModelsLoadAndDecoderShapesAreStable() throws {
    let bridge = try makeBridgeFromMainBundle()
    XCTAssertEqual(bridge.modelStatus.loadedModelCount, 4)
    XCTAssertEqual(bridge.modelStatus.openCVVersion, "4.13.0")
    let report = try bridge.runDeterministicDecoderSelfTest()
    XCTAssertEqual(report.poseLandmarkCount, 33)
    XCTAssertEqual(report.handLandmarkCount, 21)
    XCTAssertTrue(report.coordinateRoundTripPassed)
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer \
  xcodebuild -project RadiographicAnatomyPOC.xcodeproj \
  -scheme UpperLimbCompanion \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath .build/body-scanner-tests \
  CODE_SIGNING_ALLOWED=NO test
```

Expected: fail because the bridge/test target is not implemented.

- [ ] **Step 3: Define the Swift-safe bridge**

The public header imports Foundation, CoreVideo, and CoreMedia only. It must expose `NSObject` result values containing numeric model indices and scalar values; it must not expose `cv::Mat`, C++ containers, or pointers to model objects.

```objc
NS_SWIFT_NAME(OpenCVBodyLandmark)
@interface OCVBodyLandmark : NSObject
@property(nonatomic, readonly) NSInteger modelIndex;
@property(nonatomic, readonly) float x;
@property(nonatomic, readonly) float y;
@property(nonatomic, readonly) float modelRelativeZ;
@property(nonatomic, readonly) float confidence;
@end

NS_SWIFT_NAME(OpenCVHandLandmark)
@interface OCVHandLandmark : NSObject
@property(nonatomic, readonly) NSInteger modelIndex;
@property(nonatomic, readonly) float x;
@property(nonatomic, readonly) float y;
@property(nonatomic, readonly) float modelRelativeZ;
@end

NS_SWIFT_NAME(OpenCVHandResult)
@interface OCVHandResult : NSObject
@property(nonatomic, readonly) NSArray<OCVHandLandmark *> *landmarks;
@property(nonatomic, readonly) float handConfidence;
@property(nonatomic, readonly) float handednessConfidence;
@end

NS_SWIFT_NAME(OpenCVFrameResult)
@interface OCVFrameResult : NSObject
@property(nonatomic, readonly) NSInteger participantCount;
@property(nonatomic, readonly) NSArray<OCVBodyLandmark *> *bodyLandmarks;
@property(nonatomic, readonly) NSArray<OpenCVHandResult *> *handCandidates;
@property(nonatomic, readonly) CFTimeInterval timestamp;
@property(nonatomic, readonly) NSTimeInterval inferenceSeconds;
@end

@interface OpenCVBodyScannerBridge : NSObject
- (nullable instancetype)initWithPersonModelURL:(NSURL *)personURL
                                    poseModelURL:(NSURL *)poseURL
                                    palmModelURL:(NSURL *)palmURL
                                    handModelURL:(NSURL *)handURL
                                             error:(NSError **)error;
- (nullable OCVFrameResult *)processPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                      timestamp:(CFTimeInterval)timestamp
                                          error:(NSError **)error;
@end
```

- [ ] **Step 4: Implement bridge ownership and errors**

Construct all four networks during initialization with `DNN_BACKEND_OPENCV`/`DNN_TARGET_CPU`. Convert supported BGRA or bi-planar full-range pixel buffers to BGR in memory, run one person pipeline, and return no result for zero or multiple accepted people. Convert every C++ exception into a stable `NSError` in domain `BodyScanner.OpenCV` with codes for model load, pixel format, inference, and output shape. The bridge is single-queue only; assert or document non-reentrancy.

- [ ] **Step 5: Add the bridging header and Xcode settings**

`UpperLimbCompanion-Bridging-Header.h` contains only:

```objc
#import "BodyScanner/OpenCV/OpenCVBodyScannerBridge.h"
```

Set companion Debug/Release `SWIFT_OBJC_BRIDGING_HEADER` and `CLANG_CXX_LANGUAGE_STANDARD = "gnu++17"`. Link generated `Vendor/OpenCV/opencv2.xcframework` only to `UpperLimbCompanion` and its hosted test target; do not add it to `UpperLimbPOC` visionOS.

- [ ] **Step 6: Add models as companion resources**

Add the four named ONNX files to the companion Resources phase. Add a build-time check that the bundle contains the exact filenames; runtime startup verifies SHA-256 before model initialization.

- [ ] **Step 7: Run simulator tests and both SDK builds**

Run the Step 2 test plus:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer \
  xcodebuild -project RadiographicAnatomyPOC.xcodeproj \
  -scheme UpperLimbCompanion -sdk iphoneos \
  -derivedDataPath .build/body-scanner-device \
  CODE_SIGNING_ALLOWED=NO clean build
```

Expected: test passes; simulator arm64 and device arm64 link without duplicate-architecture or missing-symbol errors.

- [ ] **Step 8: Commit**

```bash
git add UpperLimbPOC/BodyScanner/OpenCV \
  UpperLimbPOC/UpperLimbCompanion-Bridging-Header.h \
  UpperLimbCompanionTests RadiographicAnatomyPOC.xcodeproj
git commit -m "feat: bridge OpenCV joint inference into iOS"
```

---

### Task 5: Capture rear-camera frames and optional LiDAR depth

**Files:**
- Create: `UpperLimbPOC/BodyScanner/BodyScannerFrame.swift`
- Create: `UpperLimbPOC/BodyScanner/BodyScannerDepthAdapter.swift`
- Create: `UpperLimbPOC/BodyScanner/BodyScannerCaptureService.swift`
- Modify: `UpperLimbPOC/InfoCompanion.plist`
- Create: `UpperLimbCompanionTests/BodyScannerDepthAdapterTests.swift`

- [ ] **Step 1: Write failing depth and orientation tests**

Test that a 2×2 depth neighbourhood rejects NaN/zero/out-of-range samples, returns the median valid depth, and unprojects the principal point to `(0, 0, depth)`. Test landscape-left/right metadata without mirroring.

```swift
func testMissingDepthNeverBecomesMetricPoint() {
    let result = BodyScannerDepthAdapter.sample(
        normalizedPoint: .init(x: 0.5, y: 0.5),
        depth: .allInvalidFixture,
        calibration: .identityFixture
    )
    XCTAssertNil(result.depthMeters)
    XCTAssertNil(result.cameraPointMeters)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run the `UpperLimbCompanionTests` scheme filtered to `BodyScannerDepthAdapterTests`; expect missing-type failures.

- [ ] **Step 3: Define synchronized frame ownership**

```swift
struct BodyScannerFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let depthData: AVDepthData?
    let calibrationData: AVCameraCalibrationData?
    let timestamp: CMTime
    let orientation: SensorOrientation
    let dimensions: CMVideoDimensions
}
```

Document that the capture service retains buffers only until the inference consumer finishes and never writes them.

- [ ] **Step 4: Implement optional depth sampling**

Convert depth to `kCVPixelFormatType_DepthFloat32`, map video-normalized coordinates to the depth map, take the median of valid samples in a 3×3 neighbourhood, and reject depths outside `0.20...5.00` metres. Unproject with the provided intrinsic matrix after scaling intrinsics to the depth resolution. Return optional depth and camera point; do not use model-relative Z as fallback.

- [ ] **Step 5: Implement the capture service**

`BodyScannerCaptureService` owns a private serial session queue and exposes:

```swift
final class BodyScannerCaptureService: NSObject, @unchecked Sendable {
    let session: AVCaptureSession
    var frames: AsyncStream<BodyScannerFrame> { get }

    func authorization() -> AVAuthorizationStatus
    func requestAuthorization() async -> Bool
    func configure() async throws
    func start() async throws
    func stop() async
}
```

Prefer `.builtInLiDARDepthCamera` only when it supplies the rear 1x video view plus a compatible depth format. Otherwise select `.builtInWideAngleCamera` and emit frames with nil depth. Configure `AVCaptureVideoDataOutput` for full-range bi-planar YUV, discard late frames, and use `AVCaptureDataOutputSynchronizer` when depth is active. Never enqueue more than the newest unprocessed frame.

- [ ] **Step 6: Add the camera usage description**

Add to `InfoCompanion.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to estimate model-based body and hand landmarks for an on-device educational scan. Images are not saved or transmitted.</string>
```

- [ ] **Step 7: Run tests and SDK builds**

Expected: depth tests pass, simulator builds with mocked/no camera input, and device SDK compiles without requesting an AVP entitlement.

- [ ] **Step 8: Commit**

```bash
git add UpperLimbPOC/BodyScanner/BodyScannerFrame.swift \
  UpperLimbPOC/BodyScanner/BodyScannerDepthAdapter.swift \
  UpperLimbPOC/BodyScanner/BodyScannerCaptureService.swift \
  UpperLimbPOC/InfoCompanion.plist UpperLimbCompanionTests
git commit -m "feat: capture iPhone body scanner frames and depth"
```

---

### Task 6: Build the live runtime and stale-safe freeze path

**Files:**
- Create: `UpperLimbPOC/BodyScanner/BodyScannerRuntime.swift`
- Create: `UpperLimbPOC/BodyScanner/BodyScannerEnvironment.swift`
- Create: `UpperLimbCompanionTests/BodyScannerRuntimeTests.swift`

- [ ] **Step 1: Write failing runtime tests**

Use fake capture and fake inference dependencies to test:

- stale frames are dropped while one inference is active;
- zero and multiple people clear the previous skeleton;
- ambiguous handedness blocks qualification;
- depth absence still allows 2D qualification;
- a qualification token becomes invalid immediately after condition loss;
- freezing stops capture and returns a pixel-free `JointScan`; and
- reset discards that scan and creates a new generation.

- [ ] **Step 2: Run the runtime tests and verify RED**

Expected: missing runtime/environment types.

- [ ] **Step 3: Define the injected runtime contract**

```swift
protocol BodyScannerRuntimeProtocol: AnyObject {
    @MainActor var previewSession: AVCaptureSession? { get }
    var events: AsyncStream<BodyScannerEvent> { get }

    func requestCameraAuthorization() async -> CameraAuthorization
    func loadModels() async throws
    func start() async throws
    func stop() async
    func freeze(expectedGeneration: UInt64) async throws -> JointScan
    func reset() async
}
```

Events carry presentation-safe observations, qualification, depth availability, inference timing, and stable error codes. They never carry `CVPixelBuffer` outside the runtime.

- [ ] **Step 4: Implement latest-frame inference**

Use one actor or serial executor around the non-reentrant bridge. If inference is active, replace the pending frame with the newest frame; never build a queue. Convert bridge indices to stable enums, perform hand association in unmirrored sensor coordinates, sample optional depth, and feed the qualification accumulator.

- [ ] **Step 5: Implement atomic freeze**

`freeze(expectedGeneration:)` rechecks the accumulator's current qualified generation on the runtime executor. If it differs, throw `qualificationExpired`. On success, build `JointScan`, stop capture/inference, release the last pixel buffer, and emit a frozen event containing only structured landmarks.

- [ ] **Step 6: Implement environment assembly**

`BodyScannerEnvironment.live` constructs capture, four model URLs, checksum verifier, bridge, depth adapter, runtime, and view model dependencies. `BodyScannerEnvironment.fixture(_:)` exists only under `#if DEBUG` and never initializes camera/OpenCV.

- [ ] **Step 7: Run runtime tests and verify GREEN**

Expected: all runtime tests pass with deterministic timestamps and no camera access.

- [ ] **Step 8: Commit**

```bash
git add UpperLimbPOC/BodyScanner/BodyScannerRuntime.swift \
  UpperLimbPOC/BodyScanner/BodyScannerEnvironment.swift \
  UpperLimbCompanionTests/BodyScannerRuntimeTests.swift
git commit -m "feat: add body scanner live runtime"
```

---

### Task 7: Build the scanner UI against the fixture runtime

**Files:**
- Create: UI/presentation files listed in the File map
- Create: `Tools/BodyScannerPresentationCheck.swift`
- Create: `UpperLimbCompanionUITests/BodyScannerFlowUITests.swift`

- [ ] **Step 1: Write the failing presentation check**

Test a 1920×1080 sensor projected aspect-fit into landscape bounds: corners and centre must map within 1 point and no X mirroring occurs. Test guidance priority, render-style differentiation, counts, and freeze state. Required boundary cases are 9 frames/1.1 seconds, 10 frames/0.99 seconds, and 10 frames/1.0 seconds.

- [ ] **Step 2: Run the check and verify RED**

Compile pure presentation files plus `Tools/BodyScannerPresentationCheck.swift`; expect missing-type failures.

- [ ] **Step 3: Define screen state and accessibility IDs**

```swift
enum BodyScannerScreenState: Equatable {
    case consent
    case requestingPermission
    case loadingModels
    case rotateToLandscape
    case live
    case frozen(FrozenScanPresentation)
    case failed(ScannerFailurePresentation)
}

enum FreezeQualificationPresentation: Equatable {
    case blocked(reason: ScanGuidance)
    case stabilizing(frames: Int, elapsedSeconds: Double)
    case qualified(generation: UInt64)
}
```

Centralize the exact identifiers `bodyScanner.entry`, `intro`, `consent`, `continue`, `rotate`, `preview`, `overlay`, `guidance`, `status`, `counts`, `depth`, `freeze`, `multiplePeople`, `error`, `openSettings`, `retry`, `frozenSummary`, and `reset`, each prefixed by `bodyScanner.`.

- [ ] **Step 4: Implement consent and orientation gates**

Before requesting the camera, show on-device/no-save/non-diagnostic disclosure, participant setup at roughly 2 metres, and an in-memory consent toggle. Continue is disabled until consent. Portrait pauses scanning and shows only `Rotate iPhone to landscape`; retain portrait support for the rest of the companion app.

- [ ] **Step 5: Implement preview projection and overlay**

Use an unmirrored `AVCaptureVideoPreviewLayer` with aspect fit. Draw the overlay in the same computed image rectangle and clip to it. Body is white/solid/circle; participant left is amber/solid/triangle; participant right is cyan/dashed/square. Add black halos, dotted/hollow estimated points, and a `?` badge for ambiguity. Hide the Canvas from VoiceOver and expose one combined textual summary.

- [ ] **Step 6: Implement one-instruction guidance**

Priority is exactly: multiple people, no participant, body clipped, body too small, arms not separated, missing participant-left hand, missing participant-right hand, hands not open, side ambiguity, stabilizing, ready. Depth absence is a status chip, never competing guidance.

- [ ] **Step 7: Implement status, Freeze, and frozen summary**

Display `Body 33/33 · Participant L 19/21 · Participant R 21/21`. Count body points only when their per-landmark confidence is ≥0.50. Count hand points when they are finite and in-frame, and display the separate global hand score; never pretend that score is 21 point confidences. Freeze is enabled only for `qualified(generation:)` and passes that generation to the view model. Frozen state removes the preview, shows a skeleton-only neutral background, timestamp/counts/depth status, `Model-estimated visual landmarks`, `Not verified anatomical joint centres`, and Reset. Add no Save/Share/Export action; AVP publication is owned by the integration layer, not this UI.

- [ ] **Step 8: Add deterministic debug fixtures and UI tests**

Support:

```text
--body-scanner-open
--body-scanner-consented
--body-scanner-fixture qualified|partial|multiplePeople|depthUnavailable|frozen|permissionDenied|modelFailure
```

Every fixture preview displays `SIMULATED INPUT`. UI tests cover consent, both landscape orientations, qualified Freeze, partial/multiple-person blocking, non-blocking depth absence, permission/model recovery, frozen Reset, accessibility text size, and minimum 44×44 point controls.

- [ ] **Step 9: Run presentation and UI tests**

Expected: pure presentation checks and XCUITests pass; output remains labelled `[SIM]` and makes no device-camera claim.

- [ ] **Step 10: Commit**

```bash
git add UpperLimbPOC/BodyScanner Tools/BodyScannerPresentationCheck.swift UpperLimbCompanionUITests
git commit -m "feat: add accessible iPhone body scanner interface"
```

Do not stage shared integration files in this UI-track commit.

---

### Task 8: Integrate the scanner route and validation pipeline

**Files:**
- Modify: `UpperLimbPOC/CompanionApp.swift`
- Modify: `UpperLimbPOC/CompanionContentView.swift`
- Modify: `UpperLimbPOC/InfoCompanion.plist`
- Modify: `RadiographicAnatomyPOC.xcodeproj/project.pbxproj`
- Modify: `RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbCompanion.xcscheme`
- Modify: `Tools/validate.sh`

- [ ] **Step 1: Add failing integration assertions**

Assert the scanner entry phrase, camera usage description, all scanner files in companion sources only, four models in companion resources, OpenCV linked only to companion/tests, debug fixture arguments, privacy source scan, core/presentation checks, simulator tests, and device-SDK build.

- [ ] **Step 2: Run validation and verify RED**

Expected: failure on the missing route/project membership.

- [ ] **Step 3: Add the companion navigation entry**

At the top of `CompanionContentView.controlPanel`, add a `NavigationLink` card:

```swift
NavigationLink {
    BodyScannerScreen(environment: .live)
} label: {
    Label {
        VStack(alignment: .leading) {
            Text("OpenCV Body Scanner")
            Text("On-device landmark scan · no images saved")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    } icon: {
        Image(systemName: "figure.arms.open")
    }
}
.accessibilityIdentifier(ScannerAccessibilityID.entry)
```

Use debug launch arguments in `CompanionApp` to open a fixture route without changing release behavior.

- [ ] **Step 4: Merge target membership once**

Add all scanner Swift/Objective-C++/C++ files only to `UpperLimbCompanion`; add pure domain files to the hosted tests as needed. Add models to companion resources. Add unit/UI test targets and scheme entries. Preserve every current Vision target source, shared scheme, signing team, and existing uncommitted route fix.

- [ ] **Step 5: Add the privacy static gate**

Limit the scan to `UpperLimbPOC/BodyScanner` and fail if production scanner sources contain `FileManager`, `Photos`, `PHPhotoLibrary`, `URLSession`, `import Network`, `UserDefaults`, `write(to:`, or `Data(contentsOf:` outside the checksum/model loader allow-list. Assert the frozen summary contains no `UIImage` or `CGImage` property.

- [ ] **Step 6: Run focused tests and full validation**

Run core check, presentation check, hosted unit tests, UI tests, both companion SDK builds, then the complete validator. Expected: all existing 14 stages plus new scanner stages pass with zero failures.

- [ ] **Step 7: Commit**

```bash
git add UpperLimbPOC/CompanionApp.swift UpperLimbPOC/CompanionContentView.swift \
  UpperLimbPOC/InfoCompanion.plist RadiographicAnatomyPOC.xcodeproj Tools/validate.sh
git commit -m "feat: integrate iPhone OpenCV body scanner"
```

---

### Task 9: Add physical feasibility measurement and run the iPhone gate

**Files:**
- Create: `Tools/body_scanner_physical_template.csv`
- Create: `Tools/BodyScannerPhysicalAcceptance.swift`
- Modify: `Tools/validate.sh`

- [ ] **Step 1: Write the failing evaluator self-test**

The evaluator accepts five non-identifying rows with: attempt number, full body boolean, six-arm-joint boolean, left/right qualifying hand counts, laterality stable boolean, freeze seconds, depth status, and failure reason. Its self-test includes four passes/one fail and three passes/two fails.

- [ ] **Step 2: Run the self-test and verify RED**

Expected: missing evaluator file.

- [ ] **Step 3: Implement the acceptance evaluator**

An attempt passes only when full body and arm gates are true, both hands have at least 17 qualifying landmarks, laterality is stable, freeze time is at most 3.0 seconds, and depth is either `metric` or explicitly `unavailable`. Overall feasibility passes at four of five attempts. Do not include names, photos, or identifiers in the CSV.

- [ ] **Step 4: Run the self-test and add it to validation**

Expected: `Body scanner physical acceptance self-test passed`.

- [ ] **Step 5: Build and install on the connected iPhone 17 Pro Max**

Discover the device with `xcrun devicectl list devices`, then run a signed Xcode build using the existing Personal Team and install the resulting `UpperLimbCompanion.app`. Do not alter the AVP app's bundle identifier or signing settings.

- [ ] **Step 6: Execute five controlled scans**

Use one consenting adult, rear camera, landscape, consistent indoor light, approximately 2 metres, full body visible, separated arms, open hands. Record only the template fields. Confirm permission occurs after consent, multiple-person entry clears readiness, both landscape orientations remain aligned, frozen state contains no camera pixels, and Reset starts cleanly.

- [ ] **Step 7: Evaluate the result**

Run:

```bash
.build/body-scanner-physical-acceptance Tools/body_scanner_physical_results.csv
```

Expected for Phase 1 pass: `PASS: at least 4 of 5 controlled scans met the feasibility gate`. If the same gate fails in two rounds, stop Phase 2 and revise framing, resolution, model selection, or thresholds; do not weaken the truth labels.

- [ ] **Step 8: Commit evaluator code, not participant results**

```bash
git add Tools/body_scanner_physical_template.csv \
  Tools/BodyScannerPhysicalAcceptance.swift Tools/validate.sh
git commit -m "test: add iPhone body scanner feasibility gate"
```

Keep completed physical result CSVs outside version control unless separately approved and confirmed non-identifying.

---

### Task 10: Update research status and complete final verification

**Files:**
- Modify: `README.md`
- Modify: `PRODUCT_DEVELOPMENT_DOCUMENT.md`
- Modify: `CURRENT_STATUS.md`

- [ ] **Step 1: Add failing documentation assertions**

Require the phrases `OpenCV Body Scanner`, `33 body landmarks`, `21 landmarks per hand`, `model-estimated visual landmarks`, `no images saved`, `not anatomical joint centres`, and `UL-INTEGRATION-001` in the relevant documents.

- [ ] **Step 2: Run validation and verify RED**

Expected: failure on the new documentation assertions.

- [ ] **Step 3: Document the verified state only**

Describe the exact OpenCV/model pins, iPhone target, privacy boundary, simulator/device evidence, physical pass/fail counts, and integration state. Keep generic anatomy and participant observations separate. Do not call detection registration or report millimetre accuracy.

- [ ] **Step 4: Run fresh complete verification**

Run:

```bash
git diff --check
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer Tools/validate.sh
```

Then rerun the original symptom path on the physical iPhone: consent → camera → one participant → both arms/hands → stable qualification → Freeze → pixel-free summary → Reset.

- [ ] **Step 5: Request two-stage review**

First review for exact compliance with the approved Phase 1 specification, then review code quality, concurrency, pixel-buffer lifetime, coordinate conventions, and privacy. Fix and re-run verification for every finding.

- [ ] **Step 6: Commit**

```bash
git add README.md PRODUCT_DEVELOPMENT_DOCUMENT.md CURRENT_STATUS.md
git commit -m "docs: record iPhone body scanner feasibility"
```

## Final acceptance boundary

Scanner completion means the physical iPhone upper-limb gate has passed or has an explicitly reported failure with evidence. It never means anatomical accuracy, patient registration, AVP overlay accuracy, or clinical suitability. The integration layer may consume only the structured joint values; it may not consume retained camera pixels or claim an AVP-world coordinate unless a separately implemented and verified calibration function emitted that typed coordinate under an independently authorized calibration ID.
