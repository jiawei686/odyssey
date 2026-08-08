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
  three-point forearm similarity solver and explicit LiDAR/body-joint limits;
- a physical-device joint capability probe that visualizes all runtime hand
  joints and records a 30-second critical-joint continuity result.

GitHub baseline: `main` at `4de2f2d`.

## Environment

- Xcode 27.0 beta (`27A5228h`)
- Swift 6.4 compiler; project source mode Swift 5
- visionOS deployment target 2.0 with guarded newer APIs
- iOS deployment target 18.0
- visionOS 27 and iPadOS 27 simulators installed
- No physical Apple Vision Pro currently connected

## Evidence

- `[AUTO]` `Tools/validate.sh` passed all 14 stages on Xcode 27 beta, including
  the new deterministic joint-probe continuity evaluator and all existing
  simulator/device build gates.
- `[BUILD]` The probe branch also passed strict-concurrency, warnings-as-errors
  builds for both the visionOS simulator and physical visionOS 27 SDK.
- `[AUTO]` Existing baseline coverage includes invariants,
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

`JOINT-PROBE-001` — **RESEARCH SPIKE**

Determine which named joints a standard visionOS app can observe on physical
Apple Vision Pro and whether the registration-critical wearer-hand subset has
adequate continuity for the next hybrid overlay experiment.

Acceptance evidence:

1. Physical AVP displays cyan left-hand and orange right-hand joint spheres.
2. The 30-second report includes sample count, mean joint count, and critical
   continuity for each hand.
3. At least one controlled run reaches 90% critical-joint continuity, or the
   route is reshaped after two controlled failures.
4. Another-person whole-body and LiDAR-joint claims remain explicitly absent.

Physical execution remains pending because no Apple Vision Pro is connected.
The run card is `JOINT_CAPABILITY_PROBE.md`.

## Human gate

After the simulator composition is visible, Marcel reviews legibility,
comprehension, and demonstration value. Physical registration and movement are
accepted only through the PDD physical acceptance script on Apple Vision Pro.
