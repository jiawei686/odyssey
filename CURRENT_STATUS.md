# Current development status

Last verified: 2026-08-08

## Feature

The current integrated prototype combines:

- mixed-reality forearm-and-hand rendering;
- two-marker rigid elbow-to-wrist registration with manual fallback;
- five cross-subject NLM axial reference levels;
- synchronized Vision and iPad/iPhone placement, appearance, and section state;
- deterministic semantic bone guidance and gaze-targeted/pinch-confirmed input;
- a clinician-guided, three-phalanx index-finger kinematic experiment using
  reviewed MCP, PIP, and DIP model landmarks;
- a provider-labelled hybrid landmark contract with a deterministic
  three-point forearm similarity solver and explicit LiDAR/body-joint limits.

GitHub baseline: `main` at `4de2f2d`.

## Environment

- Xcode 27.0 beta (`27A5228h`)
- Swift 6.4 compiler; project source mode Swift 5
- visionOS deployment target 2.0 with guarded newer APIs
- iOS deployment target 18.0
- visionOS 27 and iPadOS 27 simulators installed
- No physical Apple Vision Pro currently connected

## Evidence

- `[AUTO]` `Tools/validate.sh` passed all 13 stages on Xcode 27 beta: invariants,
  snapshot compatibility, overlay-state behavior, hybrid landmark readiness,
  known-transform/degenerate-frame checks, index-finger calibration and
  reacquisition, physical-metric evaluator self-test, resource checks, and two
  analyzers.
- `[BUILD]` Vision simulator, Vision device SDK, companion simulator, and
  companion device SDK targets clean-built successfully.
- `[BUILD]` Fresh strict-concurrency/warnings-as-errors builds pass for the
  Vision and companion simulator targets with Xcode 27 beta.
- `[SIM]` Paired simulator smoke passed the Vision-owned amber, 65%, axial
  slice-4 synchronization assertion on the current branch. The library and
  connected companion were visibly inspected.
- `[SIM]` The immersive bone/section composition has not yet been captured in
  the latest Xcode 27 run because visionOS requires a visible user activation
  and the attempted remote pointer mapping did not activate the launch button.
- `[HUMAN]` Marcel supplied clinician-guided Blender landmark placements. They
  remain reviewed generic-model landmarks, not patient registration truth.
- `[BLOCKED]` Marker tracking, index-finger motion, gaze feel, comfort,
  manipulation, occlusion, registration accuracy, and recovery metrics require
  a physical Vision Pro.

## Active next slice

`HYBRID-LM-001` — **FEATURE**

Pair human-reviewed model points with provider-labelled live landmarks. The
first vertical slice adds a deterministic three-point forearm similarity
solver, reports two-point input as axis-only, rejects a scene-reconstruction
surface as anatomical identity, and explains the current marker/hand providers
inside the status window.

Acceptance evidence:

1. A synthetic known transform is recovered with negligible residual.
2. Collinear points are rejected.
3. ELBOW + wrist observations report axis-only readiness.
4. Elbow + distal-radius + distal-ulna report full-frame readiness.
5. A LiDAR-derived scene surface is rejected as a named joint source.
6. Vision and companion targets clean-build with Xcode 27 beta.

Physical integration remains pending: standard visionOS does not provide an
elbow or whole-body skeleton. The next device implementation must choose either
three visible markers/manual points or an approved enterprise-camera research
provider; ARKit hand tracking remains valid for wrist/finger joints only.

## Human gate

After the simulator composition is visible, Marcel reviews legibility,
comprehension, and demonstration value. Physical registration and movement are
accepted only through the PDD physical acceptance script on Apple Vision Pro.
