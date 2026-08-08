# Current development status

Last verified: 2026-08-08

## Feature

The active vertical slice is `UL-SELF-ARM-001`: a wearer-only Apple Vision Pro
overlay driven directly by ARKit `HandTrackingProvider` data. The primary flow
is deliberately small:

1. open the mixed-reality wearer view;
2. detect one wearer arm with small joint dots;
3. explicitly show an opaque, joint-driven 3D skeletal overlay.

The forearm uses `forearmArm`, `forearmWrist`, and `wrist`. The hand overlay
uses the named wrist, thumb, and finger joints. The UI automatically selects a
ready hand, keeps LIVE/STALE/PARTIAL/FAILED behavior explicit, and treats the
near-elbow provider endpoint as an approximation rather than an anatomical
elbow centre.

The earlier iPhone/OpenCV scanner and cross-device plans remain preserved for
future work. They are not part of this AVP-only runtime path.

GitHub feature branch baseline before this checkpoint:
`codex/avp-joint-capability-probe` at `95d24bb`.

## Environment

- Xcode 27.0 beta (`27A5228h`)
- Swift 6.4 compiler; project source mode Swift 5
- visionOS deployment target 2.0 with guarded newer APIs
- iOS deployment target 18.0
- visionOS 27 and iPadOS 27 simulators installed
- Physical Apple Vision Pro was connected for the marker and rigid-model
  trials; CoreDevice was unavailable for the latest articulated-build install

## Evidence

- `[DEVICE][HUMAN]` Marcel confirmed that wearer hand, finger, wrist, and
  forearm markers appeared and followed movement on physical Vision Pro.
- `[DEVICE][HUMAN]` The first generic USDZ overlay appeared, but the supplied
  photo showed two blocking defects: its translucent material did not
  superimpose clearly, and the rigid hand model could not follow individual
  joint movement.
- `[AUTO]` The replacement segment resolver maps both ends of every generated
  bone segment to its two live joint positions and rejects degenerate input.
- `[AUTO]` `Tools/validate.sh` passed all 14 stages after the simplified UI and
  articulated renderer were introduced, including state, compatibility,
  scanner, transform, build, and analyzer gates.
- `[BUILD]` The final small-dot build passed an Xcode 27 physical-device SDK
  build with code signing and warnings treated as errors.
- `[BLOCKED]` The final articulated build has not yet been observed on-device.
  Installation stopped with CoreDevice error 4016 because the headset exposed
  no assertable trusted-connectivity/device-service state.
- `[DEVICE]` The preserved iPhone/OpenCV checkpoint reached an upright landscape
  view and one 6/6 upper-limb joint observation after orientation remediation.
  Participant identity, iPhone-to-AVP transport, and metric calibration remain
  deferred.

## Active next slice

Complete the physical retest of the latest AVP build:

1. reinstall when the Vision Pro is awake, unlocked, trusted, and connected;
2. pinch **Open wearer arm overlay**;
3. pinch **Open & detect arm** and confirm the small dots follow one arm;
4. pinch **Show 3D bone overlay**;
5. flex the wrist and each finger while checking that the opaque segments stay
   attached to their tracked endpoints;
6. record any forearm-axis offset, joint lag, flicker, or loss behavior.

No 30-second continuity run is required for this acceptance slice.

## Human gate

The current commit may be published to the draft PR as an implementation
checkpoint. It must not be merged to `main` until Marcel completes the physical
articulated-overlay retest and no blocking registration or movement defect is
observed.
