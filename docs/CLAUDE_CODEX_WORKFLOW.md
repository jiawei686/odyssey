# Claude–Codex clinician-guidance workflow

## Branch and integration rule

- Codex implementation branch: `codex/clinician-annotation`.
- Claude receives the pushed frozen-contract commit as `BASE_SHA` and starts UI
  work from that exact commit.
- Neither agent merges `main`. Codex performs final integration only after the
  command centre supplies Claude's verified commit SHA.
- One file has one owner at a time. Preserve unrelated and generated files.

## Claude-owned files

- `UpperLimbPOC/CompanionContentView.swift`
- `UpperLimbPOC/ClinicianConnectionStatusView.swift`
- `UpperLimbPOC/ClinicianForearmCanvas.swift`
- `UpperLimbPOC/ClinicianControlPanel.swift`
- `UpperLimbPOC/ClinicianGuidancePreviewSupport.swift`

The four new presentation files are registered in `UpperLimbCompanion` as
compile-safe placeholders at the contract checkpoint. Claude replaces their
contents with the accepted frontend design. Claude does not use `PeerSession`
directly in child views.

## Codex-owned files

- clinician guidance contract, wire codec, state machine, and transport adapter;
- `OverlaySnapshot.swift`, `OverlayState.swift`, `PeerSession.swift`, and
  `UpperLimbPeerWireCodec.swift`;
- AVP tracking/spatial mapping/rendering files;
- deterministic checks, `Tools/validate.sh`, project registration, and docs.

## UI integration boundary

The new Forearm Guidance screen becomes the default judge-demo companion route.
Existing calibration, sectional controls, `BodyScannerScreen`, operational
setup, and DEBUG smoke hooks remain intact behind a secondary **Setup &
Diagnostics** destination. Do not delete them.

Child views receive:

- `ClinicianGuidanceClientState` values;
- `ClinicianGuidanceActionSet` closures.

Required actions are `setBoneVisible`, `setFracturePosition`,
`setIncisionGuideVisible`, and `clearGuidance`. Expose retry only when the
backend supplies it. Clear is immediate, not confirmation-gated. Slider network
submission occurs on interaction end. There is no fake camera/POV view,
tap-to-place diagram gesture, freehand drawing, or OpenCV expansion.

## Verification split

Before Claude starts:

1. contract and codec checks pass;
2. legacy `OverlaySnapshot` and joint-frame wire checks remain green;
3. both app targets build for nonphysical destinations;
4. contract branch and commit are pushed.

Before final handoff, Codex integrates Claude's supplied commit, runs all
repository validators/builds/analyzers, and records simulator versus physical
evidence separately.

Current physical status: `[BLOCKED] DEVICE-PENDING / NOT VERIFIED`. When a
Vision Pro becomes available, install the exact reported branch/commit and
check: opaque articulated bone visibility, wrist/forearm following, simple
flexion and forearm rotation attachment, occlusion, remote show/hide bone,
fracture-marker interpolation, preset guide following, clear ACK, stale hiding,
and reconnect resynchronization.
