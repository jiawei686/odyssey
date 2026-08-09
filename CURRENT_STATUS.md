# Current development status

Last verified: 2026-08-09

## Active feature

`CLINICIAN-GUIDANCE-001` is the current Level-1 judge-build slice. It adds a
versioned semantic contract for one companion controller and one Vision Pro:
show/hide the generic bone, set a bounded proximal-to-distal fracture-marker
position, show/hide a preset educational incision guide, clear guidance, and
distinguish desired from AVP-applied state. The wire carries no camera pixels,
patient data, DICOM, gaze coordinates, or raw hand transforms.

The contract and Claude/Codex ownership workflow live in
`docs/CLINICIAN_GUIDANCE_CONTRACT.md` and
`docs/CLAUDE_CODEX_WORKFLOW.md`. Claude-owned presentation files are registered
as compile-safe placeholders; their UI implementation is deliberately absent
from the Codex contract checkpoint.

- `[BUILD]` Clean baseline visionOS simulator and generic device-SDK builds
  passed with Xcode 27 and warnings treated as errors.
- `[AUTO]` The frozen contract check covers codec round trips, bounds,
  clear/bone independence, capability negotiation, malformed values,
  versioning, sequence/replay rejection, stale messages, and safe disconnected
  UI state.
- `[BLOCKED]` The physical Vision Pro is unavailable. The articulated wearer
  overlay and future remote guidance rendering are DEVICE-PENDING / NOT
  VERIFIED, never passed by simulator evidence.

## Preserved medical-assistant slice

`MED-ASSIST-001` remains an independent, text-first
medical-education assistant for the Vision Pro app. It supports patient and
clinician language modes, bounded session context, optional protected local
memory, deterministic anatomy context, locally retrieved public reference
excerpts, citation allow-listing, and local privacy/emergency handling.

The assistant is educational only. It cannot diagnose, prescribe, provide
patient-specific treatment, inspect the wearer, receive images/DICOM/tracking
coordinates, or mutate anatomy and tracking state. The direct provider
connection is limited to this development POC; distribution requires a
team-owned backend proxy.

Apple Intelligence through Foundation Models is now the default provider for a
new installation. It is explicit, device-local, and guarded to visionOS 26+;
the user may explicitly select GPT-5.4 Cloud instead. A provider failure never
silently changes the selected route.

The previous `UL-SELF-ARM-001` wearer-only overlay remains implemented and its
physical articulated-overlay retest remains open. The assistant work does not
change that renderer or its tracking contracts.

## Previous tracking slice

`UL-SELF-ARM-001` is a wearer-only Apple Vision Pro
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

- Xcode 26.6 (`17F113`) currently used for assistant verification; the earlier
  tracking checkpoint used Xcode 27.0 beta (`27A5228h`)
- Swift 6.3.3 compiler in the current Xcode; project source mode Swift 5
- visionOS deployment target 2.0 with guarded newer APIs
- iOS deployment target 18.0
- visionOS 27 and iPadOS 27 simulators installed
- Physical Apple Vision Pro was connected for the marker and rigid-model
  trials; CoreDevice was unavailable for the latest articulated-build install

## Evidence

- `[AUTO]` The medical-assistant contract checks pass for multilingual local
  retrieval, identifier rejection, urgent local response, scope boundaries,
  citation allow-listing, safe Markdown rendering, secret absence, and spatial
  transform absence.
- `[BUILD]` The medical assistant compiles for the Vision simulator with the
  existing overlay app. Foundation Models weak-links correctly while the
  project deployment target remains visionOS 2.0; the iOS companion remains
  isolated from assistant code.
- `[SIM]` The signed Vision simulator app automatically opened one assistant
  window, stored its development credential in Keychain, and returned a
  grounded Radius answer with `[S1]` using `gpt-5.4`.
- `[SOURCE]` `gpt-5.4` returned a successful authenticated provider probe on
  2026-08-09. `gpt-5.6-luna` was unavailable and is not the configured default.
- `[SIM]` The visionOS 26.5 simulator does not contain Apple Intelligence
  generation assets. The app now identifies the simulator before calling
  Foundation Models, reports that a physical Vision Pro is required, and offers
  an explicit provider-selection path without cloud fallback.
- `[BLOCKED]` Physical Vision Pro comfort, window placement, dictation/text
  entry, cancellation, persistence/relaunch, and error-recovery review remain
  pending.
- `[BLOCKED]` Current AHPedia excerpts and the adversarial prompt set still need
  approval by a named clinical reviewer.
- `[BLOCKED]` A physical Vision Pro running visionOS 26 or later must have Apple
  Intelligence enabled and its local model downloaded before the on-device
  generation, Chinese/English locale behavior, latency, cancellation, and
  offline use can be accepted.

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

Complete `MED-ASSIST-001` acceptance on a physical Vision Pro:

1. open the app and confirm exactly one assistant window appears nearby;
2. compare the same anatomy question in Patient and Clinician modes;
3. ask a follow-up without repeating the anatomy name and confirm context;
4. verify clear, optional persistence/relaunch, cancellation, and retry;
5. force offline and provider-error states and verify recovery wording;
6. review window placement, text entry, accessibility, comfort, and citations;
7. enable Apple Intelligence on the headset, verify an on-device English and
   Chinese anatomy response, then switch explicitly to GPT-5.4 Cloud and verify
   the route does not change automatically;
8. have a named clinical reviewer approve or revise the reference excerpts and
   adversarial prompt set.

Then complete the preserved articulated-overlay physical retest:

1. reinstall when the Vision Pro is awake, unlocked, trusted, and connected;
2. pinch **Open wearer arm overlay**;
3. pinch **Open & detect arm** and confirm the small dots follow one arm;
4. pinch **Show 3D bone overlay**;
5. flex the wrist and each finger while checking that the opaque segments stay
   attached to their tracked endpoints;
6. record any forearm-axis offset, joint lag, flicker, or loss behavior.

No 30-second continuity run is required for this acceptance slice.

## Human gate

The assistant is an implementation checkpoint, not a medically reviewed
feature. Do not present it externally as clinical advice or ship the direct
provider credential architecture. Merge remains gated on Marcel's physical UI
review, the preserved articulated-overlay retest, and named clinical approval
of the assistant corpus and safety evaluation.
