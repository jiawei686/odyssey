# Product Development Document — tracked sectional anatomy MR prototype

## 1. Decision summary

Build a three-day, non-clinical proof of concept that places a translucent forearm-and-hand model and a selectable axial reference CT plane over a moving human forearm in Apple Vision Pro mixed reality. Use printed elbow and wrist markers as the first registration method. Use a companion iPad/iPhone only for calibration and sectional controls.

The prototype tests whether the interaction is understandable and technically stable enough to justify a patient-specific research phase. It does not test diagnostic accuracy.

## 2. Problem framing

### User problem

Learners and clinical educators must mentally translate between flat sectional images and the anatomy of a person in front of them. Existing viewers separate the CT slice, 3D model, and moving body, making spatial relationships difficult to understand.

### Technical problem

A useful overlay must stay registered as the limb translates and rotates. Bone motion cannot be modelled as rotation around an arbitrary object origin: each segment needs an anatomically meaningful joint centre, local bone transform, and constrained degrees of freedom. Joint surfaces can also produce coupled translation during rotation.

For this prototype, elbow and wrist landmarks define one rigid forearm segment. This is deliberately simpler than articulating individual bones. It proves registration and sectional interaction without claiming natural joint kinematics.

### Safety problem

The current CT slices, AnatomyTOOL mesh, and live participant are different anatomical sources. Their overlay may look convincing while being anatomically inaccurate. The interface must therefore keep the cross-subject, illustrative-orientation, non-patient-specific, and non-clinical limitations visible.

### Opportunity statement

If a mixed-reality overlay can remain stable enough to teach the relationship between external landmarks, a 3D skeletal segment, and an axial section, the same interaction architecture could later accept segmented patient CT/MRI volumes after research-grade registration, governance, and validation are added.

## 3. Prototype users and jobs

### Primary persona: clinical educator

- Wants to demonstrate how an axial section relates to surface landmarks and skeletal anatomy.
- Needs a setup that can be explained and recalibrated quickly.
- Must be able to see when tracking is searching, partial, locked, or lost.

### Secondary persona: learner

- Wants to move around a real limb while seeing a simplified internal reference.
- Needs clear elbow-to-wrist slice navigation and uncluttered controls.
- Must not mistake the composite for the participant's anatomy.

### Operator persona: prototype facilitator

- Runs the companion device, aligns the model, changes opacity, and recovers a lost view.
- Needs a deterministic validation checklist and no patient data in the network payload.

## 4. Scope

### Must have for the three-day prototype

- Apple Vision Pro mixed-reality presentation; no full virtual-reality mode.
- One forearm-and-hand skeletal model with left/right mirroring.
- ELBOW and WRIST printed-image landmarks.
- Rigid translation, rotation, and uniform scale fit from the two landmarks.
- Last valid pose retained with visible fade when tracking is lost.
- Five bundled axial reference CT levels selectable from elbow to wrist.
- Slice visibility and opacity controls on Vision Pro and companion.
- Shared tracking status visible after the anatomy library closes.
- Explicit cross-subject, illustrative-orientation, educational-only disclosure.
- Local-only companion messages containing calibration values, not images or identifiers.

### Should have during physical-device validation

- Measured overlay error at elbow and wrist across neutral, pronated, and flexed test poses.
- Recovery time after temporary marker occlusion.
- Observer rating of slice-control clarity and safety wording.
- Screen recording of the complete demonstration flow.

### Out of scope

- Diagnostic, navigation, procedural, or treatment use.
- Patient-specific CT/MRI import, segmentation, or deformable registration.
- Natural elbow, wrist, finger, or multi-bone articulation.
- A/P or R/L registration of the cropped reference CT textures.
- Multiple Vision Pro viewers sharing a common spatial anchor.
- Authentication, encryption, clinical-system integration, or data persistence.
- Market sizing or commercial validation.

## 5. Functional requirements

| ID | Requirement | Acceptance evidence |
|---|---|---|
| FR-01 | The Vision app offers only mixed immersion. | Static invariant rejects `.full`; Vision target builds. |
| FR-02 | Selecting a ready forearm region opens the anatomy overlay. | Simulator walkthrough. |
| FR-03 | A physical device recognises ELBOW and WRIST markers and fits the rigid model between them. | Physical Vision Pro test. |
| FR-04 | Loss of valid tracking keeps the last pose and reduces opacity. | Source check plus physical occlusion test. |
| FR-05 | Tracking phase remains visible after the library closes. | Status window shows searching/partial/tracking/error states. |
| FR-06 | The user can show one of five CT slices and adjust position and opacity. | Vision and companion interaction tests. |
| FR-07 | The selected slice remains a child of the registered anatomy root. | Source invariant and motion test. |
| FR-08 | Companion sectional controls remain usable when transform calibration is locked. | UI inspection and interaction test. |
| FR-09 | Current snapshots round-trip and older v2 snapshots decode with safe defaults. | Codable test. |
| FR-10 | The interface identifies the CT as cross-subject, orientation-illustrative, and non-clinical. | Static disclosure checks and visual review. |

## 6. Non-functional requirements

- No patient image, name, identifier, or clinical record is bundled or sent.
- Slice assets have a documented source file and processing history.
- Source and built resources preserve the 112:160 image aspect ratio on a 0.105 m × 0.150 m plane.
- Transform changes should appear continuous; tracking updates use smoothing.
- A failed texture load uses a clearly synthetic fallback instead of silently showing a wrong clinical-looking image.
- The development pipeline must build the Vision simulator target, compile the physical Vision target, build the companion simulator target, and confirm resources in the app bundle.

## 7. Motion and joint model

### Prototype model

The elbow and wrist landmarks form a vector. Its midpoint/length supplies translation and uniform scale; a surface-normal estimate supplies roll orientation. A fixed local elbow-to-wrist axis maps the rigid model to this fit. This is appropriate only for the forearm segment represented by the current mesh.

### Required next model for more body parts

Represent anatomy as a kinematic graph:

1. Define a parent segment and anatomically meaningful joint coordinate system for each child segment.
2. Store each bone mesh in joint-local coordinates rather than rotating it around its mesh origin.
3. Estimate pose from at least three non-collinear landmarks per independently moving segment where practical.
4. Constrain motion by joint-specific degrees of freedom and physiological ranges.
5. Add coupled translation or learned pose corrections where rotation alone is insufficient.
6. Validate landmark-to-bone offsets and joint-centre estimates for the intended population.

The next recommended region is upper arm + forearm with shoulder, elbow, and wrist landmarks. Fingers and wrist carpals should remain out of scope until rigid long-bone tracking is validated.

## 8. Sectional-imaging data strategy

### Prototype

- Five public-domain NLM Visible Human Male `normalCT` crops.
- Different source from the AnatomyTOOL model and participant.
- Ordered as illustrative proximal-to-distal levels.
- No orientation labels are inferred; the UI says A/P and R/L are not registered.

### Patient-specific research phase

1. Import a consented DICOM CT/MRI series under an approved governance protocol.
2. De-identify at ingestion and keep identifiers outside the rendering client.
3. Segment the relevant bones/soft tissue and preserve image geometry.
4. Register image space to tracked landmarks or a validated surface scan.
5. Quantify target registration error and failure states before human interpretation.
6. Add access control, encrypted transport, audit logging, retention rules, and clinical safety review.

## 9. Multi-device and multi-user position

The current prototype supports one Vision Pro viewer and one companion controller on the same local network. Multiple devices cannot yet see a single shared spatial object. That requires a shared spatial-anchor/session layer, multi-peer state authority, late-join synchronization, conflict handling, encrypted transport, and per-device alignment validation.

## 10. Success matrix

| Dimension | Prototype success threshold | Current evidence |
|---|---|---|
| Build viability | Vision simulator, Vision device SDK, and iOS simulator builds pass. | Automated pipeline passes. |
| MR constraint | No full-immersion configuration. | Automated invariant passes. |
| Section integration | Five real reference textures ship and remain registered to the anatomy root. | Bundle and source checks pass; physical motion test pending. |
| State synchronization | Slice visibility, level, position, opacity, and count cross the companion snapshot. | Code and compatibility checks pass. |
| Tracking transparency | Phase is visible; loss retains pose and fades the overlay. | UI/source checks pass; physical occlusion test pending. |
| Safety communication | Cross-subject, illustrative orientation, not patient-specific/clinical visible before and during use. | Static/UI review passes. |
| Registration | Elbow and wrist overlay error is recorded in three poses; no pass threshold is claimed until baseline data exists. | Physical Vision Pro required. |
| Recovery | Operator can recover after marker occlusion without restarting the apps. | Physical Vision Pro required. |
| Privacy | No patient pixels or identifiers sent over the POC connection. | Payload/source review passes. |
| Demo completion | A facilitator completes launch → connect → track/manual place → show/move slice → lose/recover tracking in under five minutes. | End-to-end physical rehearsal pending. |

## 11. Three-day delivery plan

### Tonight — demonstrable vertical slice

- Freeze problem statement and exclusions.
- Add five sectional textures, controls, synchronized state, provenance, and visible safety wording.
- Build all targets and run automated invariants.

### Day 2 — physical tracking validation

- Print markers at actual size.
- Run neutral, pronation/supination, and elbow-flexion trials.
- Record landmark error, jitter, recovery, scale, orientation, and status-panel behavior.
- Fix only critical demo blockers; preserve the rigid-segment limitation.

### Day 3 — rehearsal and evidence pack

- Repeat the acceptance script on the final build.
- Capture screen recording, measurements, known limitations, and operator instructions.
- Make a go/no-go decision for a patient-specific research spike.

## 12. Development pipeline

For each change:

1. Frame the requirement and acceptance evidence in this document.
2. Implement the smallest end-to-end slice across model, state, UI, rendering, and resources.
3. Run `git diff --check` and `Tools/validate.sh`.
4. Have an independent reviewer inspect geometry, disclosure, compatibility, and failure behavior.
5. Run the physical acceptance script for tracking-affecting changes.
6. Commit only when the automated pipeline passes; record physical gaps in the handoff.

## 13. Physical acceptance script

1. Launch companion, then Vision app; confirm connection and status window.
2. Open the right forearm overlay with tracking enabled.
3. Present both markers; confirm partial and then locked status.
4. Measure visible elbow and wrist alignment in a neutral pose.
5. Rotate the forearm, flex the elbow, and repeat the measurement.
6. Enable each CT level; confirm the plane follows the anatomy root and does not distort.
7. Lock transform calibration; confirm slice controls still work.
8. Occlude one and then both markers; confirm last pose, fade, and status message.
9. Restore the markers; confirm recovery without app restart.
10. Confirm all safety disclosures are visible and no patient data is used.

## 14. Go/no-go rule

Proceed to a patient-specific research spike only if the physical test produces a stable, recoverable demonstration; users understand the cross-subject limitation; and the team can define an ethically governed DICOM/segmentation/registration workflow. A visually compelling overlay without measured registration error is not sufficient.
