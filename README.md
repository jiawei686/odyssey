# UpperLimbPOC — Vision Pro + iPad/iPhone prototype

The Vision Pro app is displayed as **Radiographic Anatomy POC**. The Xcode target retains its original name so existing signing and run configurations continue to work.

The scoped problem statement, requirements, success matrix, joint-motion approach, three-day plan, and acceptance script are in `PRODUCT_DEVELOPMENT_DOCUMENT.md`.

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
- The status window provides curated anatomy guidance from model metadata. It is not yet a generative LLM or markerless bone detector.

The markerless ML and LLM design, data boundaries, and verification gates are in `ML_ASSISTANT_ARCHITECTURE.md`.

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

1. Open `UpperLimbPOC.xcodeproj` in Xcode.
2. Select the `UpperLimbCompanion` scheme and an iPad or iPhone simulator, then press Run.
3. Select the `UpperLimbPOC` scheme and an Apple Vision Pro simulator, then press Run.
4. Wait for both apps to show **Connected**.
5. In the Vision Pro region library, select **Left Forearm & Hand** or **Right Forearm & Hand**, then choose **Open overlay**. The library window closes so only the bone remains in mixed reality.
   A compact tracking-status window remains visible alongside the overlay.
6. Enable **Reference sectional-imaging plane** before opening the overlay, or control it later from the companion. Move the slice from elbow to wrist and adjust its opacity.
7. Use the companion sliders to align the centred 0.42 m hand-to-elbow model, select a bone colour, and set opacity with the slider or 5% minus/plus controls, then press **Lock**. If the model is out of view or too faint, press **Find model** on the companion.

For a repeatable debug smoke test, first run `Tools/validate.sh`, then run:

```bash
Tools/simulator_smoke.sh <vision-simulator-udid> <ipad-simulator-udid> <output-directory>
```

The smoke route exists only in Debug builds. It prepares the right forearm in amber at 65% bone opacity with reference slice 4/5 at 0.55 opacity, launches both apps, and captures both simulator screens so startup and Vision-to-companion state synchronization can be reviewed. visionOS still requires a user activation to enter an immersive space: select the large **Open Right Forearm overlay** button in the Vision simulator, then capture the mixed-reality scene and status panel for visual review.

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
- Charles Cai: <https://charlescai.com/academic%20blog/2026/01/20/crossplatformAVPiPad/>
- AnatomyTOOL Open3DModel upper-limb mesh (CC BY-SA): <https://anatomytool.org/open3dmodel>
- NLM Visible Human Project: <https://www.nlm.nih.gov/research/visible/visible_human.html>
- NLM Visible Human `normalCT` images: <https://data.lhncbc.nlm.nih.gov/public/Visible-Human/Male-Images/PNG_format/radiological/normalCT/>

## Status and limitation

The automated pipeline builds the Vision Pro simulator target, compiles the physical Vision Pro target, builds the iPad/iPhone simulator target, and confirms the five CT textures in the Vision app bundle. The v2 baseline was previously launched and connected across simulators; the v3 sectional interaction, physical tracking, and overlay accuracy still require device-level validation.

Educational prototype only. Do not use it for diagnosis, navigation, or procedural guidance.
