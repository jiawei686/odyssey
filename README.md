# UpperLimbPOC — Vision Pro + iPad/iPhone prototype

The Vision Pro app is displayed as **Radiographic Anatomy POC**. The Xcode target retains its original name so existing signing and run configurations continue to work.

The scoped problem statement, requirements, success matrix, joint-motion approach, three-day plan, and acceptance script are in `PRODUCT_DEVELOPMENT_DOCUMENT.md`.

## AI development contract

AI contributors must read `AGENTS.md` and `CURRENT_STATUS.md` before changing
the project. Bounded specialist roles and the required assignment contract are
in `.agent-prompts/`. The exact Marcel-approved **Immersive AVP Development
Prompt v2.0** is committed as
`.agent-prompts/immersive-avp-development-v2.md`; `AGENTS.md` adapts it to
this repository. Together these files keep product scope, evidence,
physical-device gates, coordinate contracts, and safety claims consistent
across development sessions.

## Clinician-guidance judge build (in progress)

The current development branch freezes a versioned, semantic companion-to-AVP
contract before the new companion presentation and spatial renderer are
integrated. Judge controls are limited to bone visibility, one bounded
proximal-to-distal fracture-marker position, one preset educational incision
guide, clear guidance, and truthful desired/applied connection feedback.

The contract preserves the raw `OverlaySnapshot` wire format for existing
builds. It adds handshake/capability negotiation, typed desired and applied
states, ACK, heartbeat/stale status, recoverable errors, and sequence/replay
protection without transmitting pixels or ARKit transforms. See
`docs/CLINICIAN_GUIDANCE_CONTRACT.md` and
`docs/CLAUDE_CODEX_WORKFLOW.md`.

The Codex backend maps normalized guidance only on Vision Pro, using the live
wearer forearm axis. A small fracture marker and optional preset collar follow
that axis; stale or disconnected remote state hides the guidance. Existing
local AVP arm tracking remains the fallback when no negotiated remote command
is authoritative.

Physical AVP behavior is DEVICE-PENDING / NOT VERIFIED. This generic educational
POC is not patient-specific and is not procedural guidance.

## Version 4: medical education assistant

- Opening the Vision app requests a separate medical-education chat window that
  remains independent of the mixed-reality renderer.
- Patient and clinician modes share bounded conversational context while using
  different reading levels. Optional cross-launch memory is local and off by
  default.
- The default provider is Apple Intelligence through the Foundation Models
  framework on eligible visionOS 26+ devices. It runs on-device without an API
  key or network request and checks model and locale availability at runtime.
- GPT-5.4 remains an explicit cloud option. The app never silently falls back
  from Apple Intelligence to the cloud; the user must select the cloud provider.
- The assistant receives only the selected region, laterality, and semantic
  anatomy name. It cannot access tracking transforms, images, DICOM, or overlay
  controls and cannot provide diagnosis or patient-specific treatment.
- The OpenAI-compatible cloud client uses `https://api.xcode.best/v1/` with
  `gpt-5.4`. Its API key is entered in-app and stored in Keychain; no key is
  committed or bundled.
- A versioned local corpus retrieves existing anatomy metadata and selected SGH
  AHPedia summaries. Citations are allow-listed and every current entry remains
  visibly marked as pending app clinical review.
- Privacy screening rejects common identifiers, and urgent phrases produce a
  local emergency response without waiting for the external model.

Architecture, setup, provider status, safety limitations, and the future avatar
contract are documented in `MEDICAL_ASSISTANT.md`.

## Version 3: reference sectional imaging

Version 3 adds a five-level axial forearm CT reference plane to the mixed-reality overlay:

- The Vision Pro library and iPad/iPhone companion can show or hide the plane, select its elbow-to-wrist position, and change its opacity.
- The plane is parented to the same tracked anatomy root, so it follows the forearm model during marker tracking and manual fallback placement.
- A separate status panel remains open in mixed reality and reports searching, partial tracking, tracking lock, permission failure, and tracking loss.
- The status panel reports whether bundled NLM textures or a synthetic fallback loaded and provides a return-to-library action.
- The bundled images are cropped reference slices from the **National Library of Medicine Visible Human Male `normalCT` series**. The NLM describes the Visible Human image library as public domain; full provenance and processing notes are in `UpperLimbPOC/ReferenceSlices/README.md`.
- If a bundled texture cannot load, the app substitutes a clearly synthetic procedural section so the demonstration remains usable.

The CT slices, AnatomyTOOL 3D mesh, and live participant come from different anatomical sources. Alignment is therefore an approximate, landmark-based educational composite. Axial orientation and laterality are illustrative only; A/P and R/L are not registered. It is **not patient-specific, diagnostically accurate, or intended for clinical decision-making**.

## Version 3.1: appearance and interaction controls

- The companion shows bone opacity as a percentage with slider and 5% minus/plus adjustment, and offers cyan, blue, green, amber, magenta, and white bone colours.
- Colour and opacity are part of the synchronized snapshot; older snapshots safely default to cyan.
- Catalogue cards use skeletal drawings for skull, spine, ribs, pelvis/hips, forearms/hands, and lower limbs.
- On visionOS 26 or later, turn marker following and transform lock off to pinch-drag and uniformly resize the overlay. Released placement is clamped to the companion ranges and sent back to it.
- Single-pinch a bone to identify its semantic anatomy entity. Double-pinch the overlay to switch between the available 3D-bone and 3D-plus-axial modes.
- In axial mode, a vertical WRIST-to-ELBOW level bar appears in the side status panel; dragging it moves the plane continuously, selects the nearest of five slices, and synchronizes the companion.
- The status window continues to provide deterministic anatomy guidance. A separate medical-education window can explain that semantic selection through a bounded LLM interface; it remains non-diagnostic and is not a markerless detector.

The markerless ML and LLM design, data boundaries, and verification gates are in `ML_ASSISTANT_ARCHITECTURE.md`.

The human-review workflow for the model's elbow, distal-radius, and distal-ulna
annotation candidates is in `LANDMARK_ANNOTATION_PROTOCOL.md`. The tracking
status window can show and adjust these coloured markers in 1 mm increments;
review changes do not affect registration until explicitly approved.

## Version 3.3: reviewed index-finger joint prototype

- A clinician-guided Blender batch captured model-local elbow, distal-radius,
  distal-ulna, index MCP, PIP, DIP, and fingertip landmarks. The source JSON,
  repeatable batch tool, and review protocol are bundled with the project.
- On a physical Apple Vision Pro, ARKit hand tracking supplies the selected
  hand's index MCP, PIP, and DIP joint rotations. The app calibrates the first
  live pose without snapping the model.
- The proximal, middle, and distal index phalanges form a nested RealityKit
  pivot chain at the reviewed MCP, PIP, and DIP points. Motion rotates around
  those joint centres while preserving model segment lengths; the bones are
  not translated independently.
- The implementation is an educational kinematic approximation. Apple Vision
  Pro estimates the external hand skeleton; it does not locate the person's
  internal bone surfaces or replace patient-specific registration.
- Hand tracking needs a physical headset and explicit Hands Tracking
  permission. The simulator validates code and resources but cannot validate
  finger-pose accuracy, joint continuity, latency, occlusion, or comfort.

## Version 3.4: hybrid landmark registration contract

- Human-reviewed model points and live observations now use matching semantic
  landmark identifiers and explicit provider types.
- The deterministic registration core reports two-point forearm input as
  axis-only and accepts a full 3D similarity fit only from reviewed,
  non-collinear elbow, distal-radius, and distal-ulna correspondences.
- Image markers and ARKit hand joints are valid named providers for their
  supported points. A scene-reconstruction/LiDAR mesh is surface geometry, not
  a body-joint detector.
- Main-camera body-joint proposals remain a separate enterprise-entitlement
  research provider. They cannot silently replace markers or human review.
- The status window explains the active providers and this sensing limitation.

## Version 3.6: AVP wearer-arm overlay

- The primary interface is reduced to **Open → Detect → Show 3D bones**; legacy
  anatomy and cross-device controls remain collapsed for future work.
- ARKit `HandTrackingProvider` supplies wearer-only wrist, finger, and forearm
  endpoint transforms without iPhone networking or image-marker calibration.
- Small cyan dots confirm detection. An explicit action replaces them with 26
  opaque RealityKit bone segments and joint nodes driven by the selected hand's
  live named joints.
- The rigid `hand-to-elbow-overlay.usdz` remains available to the legacy manual
  prototype, but it is intentionally absent from the live wearer-tracking path
  because a single rigid mesh cannot articulate with wrist and finger motion.
- LIVE/STALE/PARTIAL/FAILED behavior remains explicit. The forearm is an
  endpoint-based educational approximation; `forearmArm` is not claimed as a
  validated anatomical elbow centre.
- The latest articulated build is automated/build verified. Its physical AVP
  retest remains open and blocks merging this checkpoint to `main`.

## Version 3.5: physical joint capability probe (preserved research spike)

- The anatomy library now opens a dedicated **Test AVP joint detection**
  window and mixed-reality joint-sphere view.
- The probe starts ARKit hand tracking without requiring the ELBOW/WRIST image
  markers and visualizes every hand-skeleton joint exposed by the runtime.
- A 30-second measurement reports update count, mean tracked-joint count, and
  continuity for wrist plus the three index-finger pivots.
- The probe labels the scope honestly: wearer hands only; no standard
  whole-body ARKit provider; no named joints from the LiDAR scene mesh.
- The physical sequence and decision thresholds are in
  `JOINT_CAPABILITY_PROBE.md`.

## Version 3.2: gaze, recovery, and verification hardening

- Apple Vision Pro uses system gaze targeting and pinch confirmation: look at a highlighted bone, then single-pinch to identify it. The app does not receive or record raw gaze coordinates.
- The status window provides explicit `3D bone / 3D + axial` controls and a bone list, so double-pinch and small-entity targeting are optional shortcuts rather than the only path.
- Bone entities expose RealityKit accessibility labels and activation, and the sectional level bar has a larger gaze target.
- Live, stale, and unregistered alignment states are explicit. Tracking-stream failure can be retried and a model-load failure shows Retry and Return-to-library recovery.
- Lock state can be changed in the headset. The companion uses a responsive single-column iPhone layout or two-column iPad layout.
- `Reset placement` preserves appearance and section settings; `Centre & brighten` names its opacity side effect.
- The validation pipeline now executes overlay-state logic tests and a physical-metrics evaluator self-test. Simulator smoke fails unless the companion receives the expected Vision-owned state.

## Version 2: elbow–wrist tracking

Version 2 adds a controlled, physical-device registration workflow for the current forearm-and-hand asset:

- ARKit `ImageTrackingProvider` recognises the bundled **ELBOW** and **WRIST** printed markers.
- The app calculates translation, rotation, and uniform scale from the two joint landmarks.
- Tracking updates are smoothed to reduce visible jitter.
- The last valid pose is retained and faded if either marker is lost.
- Left/right region selection is owned by Vision Pro, so the companion can no longer overwrite the chosen side.
- The model is now labelled accurately as **Forearm & Hand**, rather than a complete upper limb.

Printable source markers and instructions are in `UpperLimbPOC/Markers`. Print both SVG files at **80 mm × 80 mm**, using **Actual Size / 100%**.

Image tracking does not run in the Vision Pro simulator. The simulator uses the manual placement workflow; marker recognition must be validated on a physical Apple Vision Pro.

This Xcode project contains two apps:

- `UpperLimbCompanion` runs on iPad or iPhone. It advertises a Bonjour service and sends overlay calibration changes.
- `UpperLimbPOC` runs on Apple Vision Pro. It opens with a scrollable radiographic-region library, then enters a mixed immersive space after the user selects a ready model.

The companion and Vision app exchange newline-framed JSON containing position, rotation, scale, bone colour, opacity, lock state, and reference-slice controls. Vision owns session initialization; the companion applies that state and transmits only after an operator changes a control. This prevents default or stale companion values from resetting a Vision-side choice. It does not send image pixels, patient images, names, identifiers, or other clinical data; the same public-domain reference images are bundled locally in the Vision Pro app.

## Run on simulators

The iPhone OpenCV arm-scanner route depends on pinned generated artifacts that
are deliberately not committed. Before building `UpperLimbCompanion` from a
clean checkout, select Xcode 27 and run:

```bash
Tools/bootstrap_body_scanner_dependencies.sh
```

The script builds both required iOS XCFramework slices, downloads the four
pinned OpenCV Zoo models, and verifies their checksums. See
`ThirdParty/BodyScanner/README.md` for revisions, licenses, and the narrow
Xcode 27 build patch.

1. Open `RadiographicAnatomyPOC.xcodeproj` in Xcode.
2. Select the `UpperLimbCompanion` scheme and an iPad or iPhone simulator, then press Run.
3. Select the `UpperLimbPOC` scheme and an Apple Vision Pro simulator, then press Run.
4. Wait for both apps to show **Connected**.
5. In the Vision Pro region library, select **Left Forearm & Hand** or **Right Forearm & Hand**, then choose **Open overlay**. The library window closes so only the bone remains in mixed reality.

Apple Intelligence generation is unavailable in the Vision Pro Simulator because
the simulator does not contain the on-device model. For simulator chat testing,
open the assistant settings and explicitly select **GPT-5.4 Cloud**. Test the
Apple Intelligence provider only on a physical Vision Pro with Apple
Intelligence enabled and its model download complete.
   A compact tracking-status window remains visible alongside the overlay.
6. Enable **Reference sectional-imaging plane** before opening the overlay, or control it later from the companion. Move the slice from elbow to wrist and adjust its opacity.
7. Use the companion sliders to align the centred 0.42 m hand-to-elbow model, select a bone colour, and set opacity with the slider or 5% minus/plus controls, then press **Lock placement**. If the model is out of view or too faint, press **Centre & brighten** on the companion.

For a repeatable debug smoke test, first run `Tools/validate.sh`, then run:

```bash
Tools/simulator_smoke.sh <vision-simulator-udid> <ipad-simulator-udid> <output-directory>
```

The smoke route exists only in Debug builds. It prepares the right forearm in amber at 65% bone opacity with reference slice 4/5 at 0.55 opacity, launches both apps, asserts that the companion received that Vision-owned state, and captures both simulator screens. visionOS still requires a user activation to enter an immersive space: select the large **Open Right Forearm overlay** button in the Vision simulator, then capture the mixed-reality scene and status panel for visual review.

For physical measurements, copy `Tools/physical_acceptance_template.csv`, enter at least three `neutral`, `pronated`, `supinated`, and `flexed` trials, then run:

```bash
.build/physical-acceptance-metrics <completed-results.csv>
```

## Run on physical devices

1. Connect the Mac, iPad/iPhone, and Apple Vision Pro to the same local network.
2. Under **Signing & Capabilities**, select your Apple development team for both targets. Change the bundle identifiers if Xcode requests it.
3. Run `UpperLimbCompanion` on the iPad/iPhone first and allow Local Network access.
4. Run `UpperLimbPOC` on Apple Vision Pro and allow Local Network access.
5. Wait for **Connected**, open the overlay, and calibrate it from the companion.

If discovery fails, confirm that Local Network access is enabled for both apps, both devices are on the same non-isolated Wi-Fi network, and neither device is using a VPN that blocks peer discovery.

## Architecture

- Discovery: Bonjour service `_upperlimb-poc._tcp`
- Transport: local TCP with `Network.framework`
- Shared state: `OverlaySnapshot`, encoded with `Codable`
- Anatomy catalogue: 12 radiographic regions, with availability shown explicitly
- 3D asset: `hand-to-elbow-overlay.usdz`, bundled in both targets
- Companion preview: SceneKit
- Vision rendering: RealityKit `RealityView`
- Physical landmark tracking: ARKit `ImageTrackingProvider`
- Index-finger motion: ARKit `HandTrackingProvider` driving a reviewed nested
  MCP/PIP/DIP pivot chain
- Current wearer overlay: ARKit `HandTrackingProvider` driving 26 generated,
  opaque RealityKit segments between named wrist, hand, and finger joints
- Fit anchors: local elbow Z `+0.205 m`, local wrist Z approximately `-0.058 m`
- Reference elbow–wrist model length: `0.2625 m`
- Sectional reference: five bundled NLM Visible Human CT crops, loaded as local RealityKit textures
- Section registration: approximate normalized elbow-to-wrist position on the same anatomy root
- Recovery: client reconnect retry, status-panel return to library, and explicit texture-fallback status
- Manual interaction: RealityKit `ManipulationComponent` on visionOS 26+, limited to translation and uniform scaling
- Anatomy guidance: curated descriptions keyed to semantic USDZ entity names such as `Radius_r` and `Ulna_r`

The demo deliberately uses a small TCP implementation to keep the August proof-of-concept build understandable. Before any production, research, or clinical deployment, replace it with authenticated encrypted transport, add robust reconnect and multi-peer handling, and establish a validated registration/tracking method. Apple's current sample demonstrates a QUIC/TLS approach.

## Source references

- Apple: <https://developer.apple.com/documentation/visionos/connecting-ipados-and-visionos-apps-over-the-local-network>
- Apple gaze privacy: <https://developer.apple.com/documentation/visionos/adopting-best-practices-for-privacy>
- Apple hover effects: <https://developer.apple.com/documentation/realitykit/hovereffectcomponent/>
- Apple spatial accessibility: <https://developer.apple.com/documentation/visionos/improving-accessibility-support-in-your-app/>
- Charles Cai: <https://charlescai.com/academic%20blog/2026/01/20/crossplatformAVPiPad/>
- AnatomyTOOL Open3DModel upper-limb mesh (CC BY-SA): <https://anatomytool.org/open3dmodel>
- NLM Visible Human Project: <https://www.nlm.nih.gov/research/visible/visible_human.html>
- NLM Visible Human `normalCT` images: <https://data.lhncbc.nlm.nih.gov/public/Visible-Human/Male-Images/PNG_format/radiological/normalCT/>

## Status and limitation

The automated pipeline builds the Vision Pro simulator target, compiles the physical Vision Pro target, builds the iPad/iPhone simulator target, and confirms the five CT textures in the Vision app bundle. The v2 baseline was previously launched and connected across simulators; the v3 sectional interaction, physical tracking, and overlay accuracy still require device-level validation.

Educational prototype only. Do not use it for diagnosis, navigation, or procedural guidance.
