# Odyssey integrated demo candidate

Status: automated integration candidate; physical Apple Vision Pro behavior remains DEVICE-PENDING / NOT VERIFIED.

## Lab entry points

- Vision Pro scheme: `UpperLimbPOC-Odyssey-Integrated-Demo`
- iPhone/iPad scheme: `UpperLimbCompanion-Odyssey-Integrated-Demo`
- Shared DEBUG launch argument: `--odyssey-integrated-demo`

Normal production/demo routes are unchanged when the launch argument is absent.

## What this candidate implements

- A persistent Odyssey Home → Session → End → Home shell on Vision Pro.
- A real Bonjour/Network.framework connection and versioned Odyssey clinical-session handshake between the companion and Vision Pro.
- Companion-authoritative desired Surface-to-Bone reveal and Vision-Pro-authoritative applied acknowledgment.
- One command in flight, replay/freshness checks, and stale-state fail-closed behavior.
- A CT-derived educational forearm mesh fallback for the primary tracked twin.
- Setup & Diagnostics access to the separate named AnatomyTOOL USDZ on-arm lab, including the static Normal Overlay gate and explicit Radius/Ulna alignment action.
- The teammate medical-assistant avatar and its explicit push-to-talk, on-device transcription, existing safety-governed response path, and speech output. The duplicate fallback voice backend was intentionally not retained. Microphone, transcription, model availability, avatar interaction, and speech output remain physical-device pending.

## Truthful capability boundary

This candidate does not provide a live Vision Pro wearer-view stream, camera unprojection, patient-specific CT registration, diagnostic interpretation, or production annotation placement. Those controls remain unavailable. The Surface-to-Bone reveal applies only after the Odyssey session capability is negotiated; it must not be described as changing the separate AnatomyTOOL USDZ diagnostics asset.

The models are generic/reference educational anatomy. The primary CT-derived route is a compact 60 mm public cadaver reference slab stretched to approximate tracked forearm length; source laterality/orientation and named bone identity are not clinically registered. The USDZ diagnostics route is AnatomyTOOL-derived generic anatomy, not CT-derived and not patient-specific imaging.

## Physical gate

Automated builds cannot establish visibility, attachment, flexion/rotation behavior, stale-pose freeze, comfort, microphone behavior, or cross-device connection on the physical devices. Install the exact reported branch commit and record each observation separately before claiming success.

## Simulator evidence and limitation

Both integrated apps launch to their Odyssey Home screen without a simulated connected state. The iPad simulator verifies that Connect enters a real searching state, unavailable guidance remains disabled, and Setup & Diagnostics remains reachable. Bonjour did not establish a cross-simulator session. Headless visionOS gaze activation was not deterministic, so no click-through claim is made from coordinate automation; the same Home → starting → active → ending → Home ordering and disconnected/pending/stale/error gates run in `OdysseyIntegratedDemoCheck.swift`.

## Consolidated physical check

1. Confirm Odyssey Home appears on Vision Pro.
2. Open Setup & Diagnostics, choose Normal overlay, and record whether the static bones appear.
3. Choose Align Radius & Ulna and record the on-arm position and orientation.
4. Return to Odyssey, start and end the session, and confirm Home remains visible.
5. Open the assistant and record its truthful availability/response.
6. If the companion is installed, connect it and record the real connection, desired/applied reveal, pending, and stale behavior.
