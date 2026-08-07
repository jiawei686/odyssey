# UpperLimbPOC — Vision Pro + iPad/iPhone prototype

The Vision Pro app is displayed as **Radiographic Anatomy POC**. The Xcode target retains its original name so existing signing and run configurations continue to work.

## Version 2: elbow–wrist tracking

Version 2 adds a controlled, physical-device registration workflow for the current forearm-and-hand asset:

- ARKit `ImageTrackingProvider` recognises the bundled **ELBOW** and **WRIST** printed markers.
- The app calculates translation, rotation, and uniform scale from the two joint landmarks.
- Tracking updates are smoothed to reduce visible jitter.
- The last valid pose is retained and faded if either marker is lost.
- Left/right region selection is owned by Vision Pro, so the companion can no longer overwrite the chosen side.
- The model is now labelled accurately as **Forearm & Hand**, rather than a complete upper limb.

Printable source markers and instructions are in `UpperLimbPOC/Markers`. Print both SVG files at **80 mm × 80 mm**, using **Actual Size / 100%**.

Image tracking does not run in the Vision Pro simulator. The simulator automatically retains the manual placement workflow; marker recognition must be validated on a physical Apple Vision Pro.

This Xcode project contains two apps:

- `UpperLimbCompanion` runs on iPad or iPhone. It advertises a Bonjour service and sends overlay calibration changes.
- `UpperLimbPOC` runs on Apple Vision Pro. It opens with a scrollable radiographic-region library, then enters a mixed immersive space after the user selects a ready model.

The companion sends newline-framed JSON containing only position, rotation, scale, opacity, and lock state. It does not send the CT source, patient images, names, identifiers, or other clinical data.

## Run on simulators

1. Open `UpperLimbPOC.xcodeproj` in Xcode.
2. Select the `UpperLimbCompanion` scheme and an iPad or iPhone simulator, then press Run.
3. Select the `UpperLimbPOC` scheme and an Apple Vision Pro simulator, then press Run.
4. Wait for both apps to show **Connected**.
5. In the Vision Pro region library, select **Left Forearm & Hand** or **Right Forearm & Hand**, then choose **Open overlay**. The library window closes so only the bone remains in mixed reality.
6. Use the companion sliders to align the centred 0.42 m hand-to-elbow model and adjust its translucency, then press **Lock**. If the model is out of view or too faint, press **Find model** on the companion.

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

The demo deliberately uses a small TCP implementation to keep the August proof-of-concept build understandable. Before any production, research, or clinical deployment, replace it with authenticated encrypted transport, add robust reconnect and multi-peer handling, and establish a validated registration/tracking method. Apple's current sample demonstrates a QUIC/TLS approach.

## Source references

- Apple: <https://developer.apple.com/documentation/visionos/connecting-ipados-and-visionos-apps-over-the-local-network>
- Charles Cai: <https://charlescai.com/academic%20blog/2026/01/20/crossplatformAVPiPad/>

## Status and limitation

Both targets have been built, launched, and connected across the iPad and Vision Pro simulators. Physical-device tracking and overlay accuracy have not yet been validated.

Educational prototype only. Do not use it for diagnosis, navigation, or procedural guidance.
