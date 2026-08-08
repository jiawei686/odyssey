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
  reviewed MCP, PIP, and DIP model landmarks.

GitHub baseline: `main` at `69e8d55`.

## Environment

- Xcode 27.0 beta (`27A5228h`)
- Swift 6.4 compiler; project source mode Swift 5
- visionOS deployment target 2.0 with guarded newer APIs
- iOS deployment target 18.0
- visionOS 27 and iPadOS 27 simulators installed
- No physical Apple Vision Pro currently connected

## Evidence

- `[AUTO]` `Tools/validate.sh` passed all 12 stages on Xcode 27 beta: invariants,
  snapshot compatibility, overlay-state behavior, index-finger calibration and
  reacquisition, physical-metric evaluator self-test, resource checks, and two
  analyzers.
- `[BUILD]` Vision simulator, Vision device SDK, companion simulator, and
  companion device SDK targets clean-built successfully.
- `[SIM]` Paired simulator smoke passed the Vision-owned amber, 65%, axial
  slice-4 synchronization assertion. The library and connected companion were
  visibly inspected.
- `[SIM]` The immersive bone/section composition has not yet been captured in
  the latest Xcode 27 run because visionOS requires a visible user activation
  and the attempted remote pointer mapping did not activate the launch button.
- `[HUMAN]` Marcel supplied clinician-guided Blender landmark placements. They
  remain reviewed generic-model landmarks, not patient registration truth.
- `[BLOCKED]` Marker tracking, index-finger motion, gaze feel, comfort,
  manipulation, occlusion, registration accuracy, and recovery metrics require
  a physical Vision Pro.

## Active next slice

`SIM-ENTRY-001` — **RESEARCH SPIKE**

Question: What is the smallest reliable Xcode 27 simulator workflow that opens
the mixed immersive overlay after the required user activation and leaves the
3D model, reference plane, and status panel visible for review?

Acceptance evidence:

1. Reproducible steps from a clean paired-simulator launch.
2. Visible forearm-and-hand model in mixed reality.
3. Visible reference axial plane at slice 4/5.
4. Visible status panel reporting simulator/manual mode and data source.
5. Companion controls visibly change opacity, colour, and section level.
6. A captured screenshot or recording of the composition.

Non-goals: image-marker accuracy, hand tracking, raw gaze, physical comfort,
patient registration, or new anatomy regions.

Stop condition: if Xcode 27 beta cannot provide reliable activation through the
supported simulator controls, record the platform limitation and specify a
clearly labelled in-window simulator preview fallback rather than weakening the
physical mixed-reality architecture.

## Human gate

After the simulator composition is visible, Marcel reviews legibility,
comprehension, and demonstration value. Physical registration and movement are
accepted only through the PDD physical acceptance script on Apple Vision Pro.
