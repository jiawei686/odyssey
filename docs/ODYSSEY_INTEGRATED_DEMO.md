# Odyssey integrated demo candidate

Status: automated integration candidate; physical Apple Vision Pro behavior remains DEVICE-PENDING / NOT VERIFIED.

## Lab entry points

- Vision Pro scheme: `UpperLimbPOC-Odyssey-Integrated-Demo`
- iPhone/iPad scheme: `UpperLimbCompanion-Odyssey-Integrated-Demo`
- Scheme-only build configuration: `Debug-OdysseyIntegratedDemo`
- Persistent compilation condition: `ODYSSEY_INTEGRATED_DEMO`
- Optional simulator override: `--odyssey-integrated-demo`

Apps compiled by either integrated scheme reopen into the Odyssey shell even when launched manually from the device app library. The optional launch argument remains useful for simulator automation. Stable schemes and their routes do not define the compilation condition and remain unchanged.

## What this candidate implements

- A persistent Odyssey Home → Session → End → Home shell on Vision Pro.
- A real Bonjour/Network.framework connection and versioned Odyssey clinical-session handshake between the companion and Vision Pro.
- Companion-authoritative desired skeletal-model opacity and Vision-Pro-authoritative applied acknowledgment.
- One command in flight, replay/freshness checks, and stale-state fail-closed behavior.
- The validated AnatomyTOOL/Blender hand-to-elbow USDZ as the primary tracked twin.
- Setup & Diagnostics access to the separate named AnatomyTOOL USDZ on-arm lab, including the static Normal Overlay gate and explicit Radius/Ulna alignment action.
- The teammate medical-assistant avatar and its explicit push-to-talk, on-device transcription, existing safety-governed response path, and speech output. The duplicate fallback voice backend was intentionally not retained. Microphone, transcription, model availability, avatar interaction, and speech output remain physical-device pending.

## Truthful capability boundary

This candidate does not provide a live Vision Pro wearer-view stream, camera unprojection, patient-specific CT registration, diagnostic interpretation, or production annotation placement. Those controls remain unavailable. The negotiated reveal value fades the Blender USDZ model opacity; it does not switch to CT tissue layers.

The model is generic/reference educational AnatomyTOOL anatomy exported from Blender. It is not CT-derived, patient-specific imaging, or registered internal anatomy. The rigid twin is scaled to the tracked forearm length and displayed beside the arm.

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
