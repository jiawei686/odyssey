# UL-INTEGRATION-001 — Upper-Limb Joint Integration Plan

**Status:** Active, additive scope correction approved 2026-08-08

**Goal:** Detect one participant's upper-limb visual landmarks with OpenCV on iPhone, add a measured metric-depth and iPhone–AVP calibration authority, publish typed AVP-world joints over the existing peer channel, and align the current generic forearm anatomy plus its sectional child on Apple Vision Pro.

**First vertical slice:** iPhone shoulder/elbow/wrist inference → qualified elbow and wrist image observations → measured metric projection and calibrated AVP-world transform → existing peer channel → axis-only forearm alignment → visible `AXIS ONLY` registration state. This slice must pass before distal radius/ulna, palm, fingers, or sectional controls are extended.

## Development checkpoint — 2026-08-08

- `[AUTO]` The typed joint-frame, peer-wire compatibility, spatial bridge, tracking-state, scanner-presentation, inference-contract, and Objective-C++ wrapper checks pass independently.
- `[BUILD]` The pinned OpenCV 4.13.0 arm64 iPhone static library now compiles under Xcode 27 after isolating FP16 kernels in the `NEON_FP16` dispatch path. The earlier `vfmaq_f16 requires target feature fullfp16` compiler failure is resolved for that slice.
- `[BUILD]` Repeatable OpenCV/model bootstrap, both XCFramework slices, iOS-only linking, checksum verification, simulator/device-SDK builds, and standalone contract checks now pass. The corrected scanner build still needs a physical iPhone run.
- `[BLOCKED]` Repository audit found no production iPhone-camera-metric-to-AVP-world calibration, no scanner call site that sends a joint frame, and no immersive consumer that applies the axis-only result. Those are required implementation milestones, not an existing baseline.
- `[NOT YET CLAIMED]` No physical participant scan, finger-joint inference, or anatomical-accuracy result has been established.

## Non-negotiable truth boundary

- Educational/research prototype only; no diagnosis, navigation, treatment, or patient-specific claim.
- Always show `CROSS-SUBJECT • APPROXIMATE • EDUCATIONAL` while anatomy is visible.
- OpenCV points are model-estimated visual landmarks, not verified anatomical joint centres.
- Image pixels, normalized image values, model-relative Z, iPhone-camera metres, AVP-world metres, anatomy-model metres, and sectional-image metres are distinct typed spaces.
- Model-relative Z is unitless and is never relabelled as metric depth.
- The pinned hand model has one global hand confidence and no per-finger confidence. Do not copy the global score onto the 21 hand points.
- Two corresponding points provide axis and length only. Full 3D pose/scale requires three reviewed, non-collinear correspondences: elbow reference, distal radius, and distal ulna.
- The 3D anatomy and sectional plane consume one registration root and one registration state.
- Wrong session, calibration, clock, sequence, unit, coordinate space, or stale/failed state cannot move anatomy. A stale result fades; failed tracking hides it.
- No camera pixel crosses the peer channel and no scan is persisted by default.

## Existing baseline to preserve

- `PeerSession` Bonjour/TCP connection and reconnect behavior.
- `OverlaySnapshot` backward compatibility.
- `LandmarkTrackingService` image-marker elbow/wrist path and hand probe.
- `HybridLandmarkRegistration` axis-only/full-frame distinction and reviewed model landmarks.
- `ImmersiveView` registered anatomy root with `ReferenceSectionRoot` as its child.
- Physical AVP joint-probe navigation/signing changes currently uncommitted on this branch, including team `QLYUY93X5V`.

The baseline is audited and adapted. It is not replaced unless a reproducible defect is recorded.

## Frozen shared transport contract

Lead-owned `UpperLimbPOC/UpperLimbJointFrame.swift` defines:

- schema version, session ID, calibration ID, sender clock ID, sequence, and monotonic capture timestamp;
- laterality and named shoulder/elbow/wrist/distal radius/distal ulna/palm/finger joint;
- exactly one typed position, coordinate space, and unit per observation;
- optional confidence plus its true scope;
- depth source, tracking validity, and observation state;
- hand-global evidence stored separately from finger points; and
- a receiving gate for schema/session/calibration/clock/sequence/age/payload rejection.

The future calibration exchange must supply the measured sender-to-receiver clock offset used by the stale-frame gate. Device-local monotonic timestamps are not compared without that offset, and the first observation packet cannot authorize its own IDs or clock.

## Ownership board

| Owner | Writable scope | Forbidden shared files |
|---|---|---|
| Lead | shared joint contract, `PeerSession`, project file, validator, integration state, docs, commits | none |
| iPhone/OpenCV specialist | new inference/wrapper files under `UpperLimbPOC/BodyScanner/OpenCV/` and `BodyScanner/Inference/`; matching new checks | project, validator, peer, shared contract, app entry, docs |
| Spatial specialist | new `UpperLimbIntegration/SpatialJointBridge.swift`; matching standalone check | existing registration/tracking/peer files, project, validator, shared contract, docs |
| UI/UX specialist | new `BodyScanner/UI/` files; matching presentation check | project, validator, peer, shared contract, app entry, docs |

Only the lead integrates shared files and commits. Agents do not commit independently.

## Milestone 1 — Contract and baseline audit

- [x] Recover branch/worktrees and preserve dirty AVP route/signing work.
- [x] Confirm peer snapshot channel, elbow/wrist marker fit, hybrid solver, and common anatomy/section root.
- [x] Freeze the versioned upper-limb joint-frame contract.
- [x] Add standalone checks for coordinate/unit truth, hand confidence scope, session/calibration/clock, sequence, and staleness.
- [x] Add the contract check to `Tools/validate.sh` and both app targets without changing baseline behavior.

Gate: standalone contract test, existing 14-stage validator, and both target builds pass.

## Milestone 2 — Pinned OpenCV dependency and elbow/wrist inference

- [x] Build OpenCV `4.13.0` commit `fe38fc608f6acb8b68953438a62305d8318f4fcd` with the official Apple XCFramework builder for `ios-arm64` and `ios-arm64_x86_64-simulator`.
- [x] Pin OpenCV Zoo commit `47534e27c9851bb1128ccc0102f1145e27f23f98` and verify the four recorded ONNX SHA-256 values.
- [x] Link OpenCV only to the iOS companion target, never the visionOS target.
- [x] Load MP-Person and MP-Pose first; emit shoulder, elbow, and wrist points in unmirrored sensor coordinates with per-pose-point confidence.
- [x] Run inference serially off the main actor, discard late capture frames, and convert every C++ exception to a stable error.
- [ ] Verify model load and deterministic decoder shapes on simulator; then verify a signed iPhone build.

Kill gate: stop if the generated XCFramework lacks a required device/simulator slice, `opencv2/dnn.hpp`, model checksum, model load, stable index mapping, or a minimal iOS link. Do not fall back silently to Apple Vision or a floating binary.

## Milestone 3 — Calibrated spatial channel implementation

- [ ] Add synchronized metric depth/intrinsics and map qualified image points into typed iPhone-camera metres; model-relative Z is not a substitute.
- [ ] Establish a measured iPhone-camera-to-AVP-world transform plus independently authorized session/calibration/clock IDs. A QR or image marker is only acceptable if both devices' geometric relationship is observable and tested; a screen-only handshake must not imply an unknown camera-to-screen extrinsic.
- [ ] Publish `UpperLimbJointFrame` as a tagged message over `PeerSession` without breaking legacy raw `OverlaySnapshot` decoding.
- [ ] On AVP, gate each frame before it reaches anatomy.
- [ ] Map elbow+wrist AVP-world metre observations into an explicit axis-only forearm result.
- [ ] Add known-transform, wrong-space/unit, wrong-laterality, missing-point, calibration mismatch, sequence, and stale/failure checks.

Gate: deterministic elbow/wrist fixture travels through encode/decode/gate/adapter and produces the expected axis, length, midpoint, and `axisOnly` state. It must not produce a full-frame claim.

## Milestone 4 — AVP anatomy and state presentation

- [ ] Feed the accepted axis result into the existing forearm root while preserving manual and marker paths.
- [ ] Keep the sectional child on the same root; no second transform is computed.
- [ ] Display `AXIS ONLY`, `FULL FRAME`, `PARTIAL`, `STALE`, or `FAILED` and the active source.
- [ ] Fade on stale; hide on failed; never hold a live-looking overlay indefinitely.
- [ ] Keep `CROSS-SUBJECT • APPROXIMATE • EDUCATIONAL` visible.

Gate: simulator fixture shows deterministic state transitions and physical AVP shows the elbow/wrist vertical slice without requiring AVP camera access.

## Milestone 5 — Hand/finger and sectional extension

- [ ] Add MP-Palm and MP-HandPose, preserving hand-global confidence.
- [ ] Associate participant left/right using wrist proximity, handedness, and temporal continuity; ambiguous results do not publish.
- [ ] Add distal radius/ulna or equivalent wrist references. Only three reviewed non-collinear correspondences may enable full-frame registration.
- [ ] Add palm and all 21 finger points to the typed stream.
- [ ] Reuse the common anatomy/section root and name every displayed sectional level.

Gate: fingers and sectional display remain blocked until the elbow/wrist physical slice passes.

## Integration sequence

1. Merge agent-created new files only after their standalone checks pass.
2. Lead updates `PeerSession`, app routes, project references, and validator in one controlled integration pass.
3. Run `git diff --check` and the full `Tools/validate.sh` suite with Xcode 27 beta.
4. Build the iOS companion for simulator/device SDK and the visionOS app for simulator/device SDK with strict concurrency and warnings as errors.
5. Install on the available iPhone and AVP. Human steps are limited to trust/permission, launching the route, consent, and physically framing one participant.

## Evidence labels

- `[AUTO]` deterministic standalone/unit/UI checks.
- `[BUILD]` simulator or device-SDK compilation/link evidence.
- `[SIM]` simulated input or paired simulator flow; never camera truth.
- `[DEVICE]` installed/ran on a named physical device.
- `[HUMAN]` operator observation or consented participant run.
- `[BLOCKED]` concrete entitlement, device, model, calibration, or measurement blocker.

## Physical vertical-slice run card

1. Place iPhone 17 Pro Max approximately 2 m in front of one consenting participant; show upper body, both arms, and hands.
2. Launch the iPhone scanner, accept the no-save educational notice, allow camera, and hold arms separated.
3. Confirm left/right elbow and wrist are stable and the active calibration/session IDs match the AVP.
4. On AVP, launch the upper-limb overlay and confirm `AXIS ONLY` plus the cross-subject disclosure.
5. Move one forearm slowly. Record only non-identifying state, latency, continuity, and visible alignment behavior; do not save participant imagery.
6. Occlude a wrist briefly. Confirm `PARTIAL/STALE` and fade, then recovery; stop if the overlay remains falsely live.

This run demonstrates a technical coordinate/integration slice only. It does not establish anatomical accuracy or clinical suitability.
