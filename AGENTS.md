# Radiographic Anatomy POC agent contract

This repository uses the **Immersive AVP Development Prompt v2.0** approved by
Marcel on 2026-08-08 (`IDP-20260808-0906-001`). The complete approved prompt
is committed at `.agent-prompts/immersive-avp-development-v2.md`. This file is
the repository-facing contract. The other role prompts in `.agent-prompts/`
provide bounded specialist instructions.

## Product boundary

- Educational and research proof of concept only.
- Not diagnostic, patient-specific, or intended for navigation, treatment, or
  procedural guidance.
- The AnatomyTOOL mesh, NLM reference CT slices, and physical participant are
  separate anatomical sources.
- Never imply that cross-subject content is registered to a participant.
- Patient pixels, identifiers, clinical records, and ungoverned DICOM data must
  not enter the app, repository, network payload, logs, or a general LLM.
- Any patient-specific or clinical claim stops implementation pending explicit
  human governance and regulatory review.

Human safety, truth, privacy, and intended use outrank speed or visual polish.
Marcel retains anatomical, clinical, physical-comfort, and go/no-go authority.

## Recover context before acting

At the beginning of work:

1. Read this file and `CURRENT_STATUS.md`.
2. Read the relevant sections of:
   - `PRODUCT_DEVELOPMENT_DOCUMENT.md`
   - `README.md`
   - `ML_ASSISTANT_ARCHITECTURE.md`
   - `LANDMARK_ANNOTATION_PROTOCOL.md`
   - `Tools/validate.sh` and `Tools/simulator_smoke.sh`
3. Inspect `git status -sb`, the current branch, recent commits, and remotes.
4. Confirm the selected Xcode/Swift versions, deployment targets, simulator
   inventory, and physical Vision Pro availability.
5. State the active feature, evidence, blocker, and next smallest step.

Never reconstruct the architecture from memory when repository evidence exists.
Preserve unfamiliar or concurrent changes until their ownership is understood.

## Locked development environment

- Preferred toolchain: `/Applications/Xcode-27-beta.app`
- Current recorded toolchain: Xcode 27.0 beta, Swift 6.4 compiler, project
  source mode `SWIFT_VERSION = 5.0`.
- Project deployment targets remain visionOS 2.0 and iOS 18.0 unless a reviewed
  requirement explicitly changes them. Newer APIs require availability guards.
- Do not silently change the toolchain, deployment target, signing, entitlement,
  dependency, or bundle-identifier strategy.

Run Xcode commands with:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer
```

## Execution lanes

- **FAST PATCH**: localized, low-risk issue with known acceptance criteria.
  Inspect, apply the smallest fix, run targeted and regression checks, report.
- **FEATURE**: new tracking, imaging, interaction, networking, asset, or
  architecture behavior. Frame, specify, plan, build one vertical slice,
  verify, pass the human gate, then converge.
- **RESEARCH SPIKE**: feasibility or platform behavior is uncertain. Define one
  question, time-box it, run the smallest discriminating experiment, and record
  adopt/revise/reject evidence without building premature architecture.

After two failed fixes based on the same assumption, stop editing and reframe
the diagnosis.

Keep one active feature. Put tangential ideas in the PDD backlog. Every task
must map to a requirement and every requirement to acceptance evidence.

## Spatial, tracking, and imaging guardrails

- Mixed reality is the required immersion style; use the minimum immersion
  necessary.
- System gaze may target and highlight. Only pinch, tap, or another explicit
  action activates. Never request, infer, store, or claim raw gaze coordinates.
- Every custom gesture needs an explicit UI/accessibility alternative.
- Keep LIVE, STALE, PARTIAL, UNREGISTERED, and FAILED states truthful and
  visible. Never leave a stale overlay looking registered.
- Keep Blender/model, USD/RealityKit, DICOM patient, ARKit world, and physical
  landmark coordinate spaces explicit. No unnamed transforms or unexplained
  constants.
- Blender is authoritative for proposed generic-model landmarks. Anatomical
  acceptance remains a named human review.
- A governed DICOM tool such as 3D Slicer is authoritative for future DICOM
  annotations. Preserve orientation, spacing, frame of reference, laterality,
  transforms, reviewer, version, and confidence.
- Do not hide missing clinical-looking data behind a convincing fallback.
  Synthetic fallback content must be visibly identified.

## Implementation rules

- Prefer existing SwiftUI, RealityKit, ARKit, and Network.framework patterns.
- Build the smallest complete behavior across state, UI, renderer, resources,
  synchronization, recovery, documentation, and tests.
- Preserve snapshot and saved-format compatibility.
- Keep UI and RealityKit mutations concurrency-safe.
- Load expensive assets asynchronously and make failures recoverable.
- Avoid unrelated refactors and dependencies.
- Compilation is not behavioral verification.

## Evidence vocabulary

- `[AUTO]` automated unit, state, compatibility, resource, or analyzer check
- `[BUILD]` target compiled successfully
- `[SIM]` behavior observed in Simulator
- `[DEVICE]` behavior measured on physical hardware
- `[HUMAN]` accepted by Marcel or a named reviewer
- `[SOURCE]` supported by an identified authoritative source
- `[INFERRED]` reasonable but untested conclusion
- `[BLOCKED]` required evidence cannot currently be obtained

Never promote one evidence level into another.

## Validation gates

For every change:

```bash
git diff --check
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer ./Tools/validate.sh
```

When simulator behavior is in scope, also run:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer \
  ./Tools/simulator_smoke.sh <vision-udid> <ipad-udid> <output-directory>
```

The smoke route proves synchronized launch state, not automatic immersive-space
entry. A visible user activation is still required by visionOS.

Tracking, gaze, comfort, real-world registration, hand motion, occlusion, and
physical manipulation require the PDD physical acceptance script. Simulator
evidence cannot close those gates.

## Specialist work

Use specialists only for independent bounded questions where domain separation
or adversarial review adds value. Use at most three concurrently. Specialists
default to read-only; QA never edits the implementation it reviews. Every
assignment must use `.agent-prompts/task-contract.md` and one applicable role
prompt. One file has at most one writer at a time.

## Completion and handoff

A slice is complete only when implementation, relevant automation, simulator
inspection, safety wording, accessibility, recovery, documentation, and
repository durability agree. Physical gates may remain open only when clearly
labelled `[BLOCKED]` or pending.

End each slice with:

- `FEATURE`
- `TEAM USED`
- `DECISIONS`
- `CHANGES`
- `EVIDENCE`
- `REVIEW FINDINGS`
- `HUMAN INPUT`
- `RISKS`
- `NEXT STEP`
