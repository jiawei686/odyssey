# Markerless anatomy and learning-assistant architecture

## Decision

Keep the current elbow/wrist markers for the prototype. Add markerless recognition only as a separately measured research track. The headset cannot optically identify a bone beneath intact skin; it can estimate surface landmarks or a body region and then register a known anatomical model. Patient-specific bone identity and geometry must come from registered CT/MRI segmentation, not an RGB inference or an LLM.

## Platform constraint

Apple documents that ARKit whole-body tracking is not available on visionOS. Standard visionOS apps can use world, hand, image, plane, scene-reconstruction, and object tracking. Processing forward-camera frames requires the business-only Main Camera Access enterprise entitlement. Therefore a general consumer build cannot assume continuous camera-frame access for a custom body-pose model.

## Layered pipeline

1. **Registration source**
   - Prototype: known ELBOW and WRIST images, each with a metric physical size.
   - Markerless research: enterprise camera frames → Vision/Core ML surface-joint model → temporal filtering → world-coordinate landmarks.
   - Patient-specific research: consented DICOM → de-identification → bone/soft-tissue segmentation → image-to-world registration.
2. **Anatomy state**
   - Structured region, side, landmark confidence, transform, registration error, and semantic entity ID.
   - The renderer accepts only this validated structured state.
3. **Anatomy guide**
   - First release: deterministic USDZ entity names map to reviewed labels and descriptions.
   - Later LLM: retrieval over a versioned, clinician-reviewed anatomy corpus using the structured entity ID.
   - The LLM may explain, quiz, translate, or adapt reading level. It may not select a bone, move the overlay, calculate registration confidence, or provide diagnosis.

## Why ML is useful—and where it is not

- Useful: detecting visible surface landmarks, classifying the viewed body region, segmenting a consented scan, and estimating pose over time.
- Not sufficient: locating an individual patient's hidden bone surface accurately from skin appearance alone.
- Not required for the current forearm POC: two measured markers already provide a transparent, testable rigid registration.

## Imaging modes

- Available now: translucent 3D bone and one illustrative axial reference plane.
- Current gesture cycle: double-pinch switches `3D bone → 3D + axial → 3D bone`; a visible label confirms the result.
- Future gesture cycle, only after valid assets exist: `3D bone → VRT → axial → coronal → sagittal → 3D bone`.
- Requires one coherent volume: axial, coronal, and sagittal multiplanar reconstruction.
- Requires segmentation/transfer functions and GPU performance work: patient-specific volume rendering.
- The interface must not relabel unrelated 2D images as orthogonal reconstructions.

## Verification gates

| Gate | Method | Provisional POC target |
|---|---|---|
| Region recognition | Held-out people, clothing, lighting, side, and pose strata | ≥95% correct region/side; abstain below confidence threshold |
| Landmark localization | Compare inferred joints with measured fiducials | Median ≤15 mm; 95th percentile ≤25 mm |
| Temporal stability | Static 10-second trials | ≤5 mm RMS endpoint jitter |
| Recovery | Occlude for two seconds, then restore | Reacquire within two seconds without a pose jump |
| Semantic bone label | Pinch named USDZ meshes | 100% correct for bundled entities |
| Assistant grounding | Reviewed prompt set | 100% entity/citation match; zero transform or diagnostic claims |
| Patient registration | Independent target landmarks not used during fitting | Threshold defined by approved study protocol before use |

These are engineering acceptance targets for an educational prototype, not clinical performance claims.

## Data and safety requirements

- Process camera frames on device where possible; do not retain them by default.
- Never send patient pixels or identifiers to an LLM.
- Separate identity, imaging, and telemetry stores; encrypt and audit any research data flow.
- Show confidence and abstention states. If the system is uncertain, keep the last validated pose or request marker/manual placement.
- Require clinician review, dataset governance, subgroup analysis, and failure-mode testing before patient-specific use.

## Recommended implementation order

1. Finish and measure marker-based forearm registration.
2. Add semantic bone selection and the deterministic guide.
3. Prototype markerless surface-joint inference only if the enterprise camera entitlement is feasible.
4. Compare markerless results against marker ground truth; keep markers as fallback.
5. Add a coherent normal volume for true multiplanar views.
6. Run a governed patient-specific registration study before any clinical claim.

## Primary Apple references

- ARKit availability and lack of whole-body tracking on visionOS: <https://developer.apple.com/documentation/visionos/bringing-your-arkit-app-to-visionos>
- Main Camera Access enterprise entitlement: <https://developer.apple.com/documentation/visionos/accessing-the-main-camera>
- Image tracking: <https://developer.apple.com/documentation/visionos/tracking-images-in-3d-space>
- Vision human body pose requests: <https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images>
- RealityKit object manipulation: <https://developer.apple.com/videos/play/wwdc2025/274/>
