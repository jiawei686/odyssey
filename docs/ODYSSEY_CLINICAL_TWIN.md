# Odyssey Clinical Education — Right Forearm Twin

Status: Phase 1 lab candidate. Automated gates pass; physical Apple Vision Pro verification is pending.

> Illustrative anatomical model — not patient-specific imaging.

## Scope

The lab route presents a CT-derived reference forearm twin beside Odyssey's tracked right forearm. It does not hide the wearer's arm, replace an X-ray, stream AVP passthrough video, or claim patient-specific registration.

The implementation deliberately uses `ctDerivedMeshFallback`. The existing Metal CT renderer is a two-dimensional companion preview and is not a spatial RealityKit volume. For this physical slice, the AVP converts the bundled, hash-verified R8 CT voxels into one soft-tissue surface and two paired bone-density surfaces under one RealityKit root.

## Experimental launch route

- Xcode project: `RadiographicAnatomyPOC.xcodeproj`
- AVP lab scheme: `UpperLimbPOC-Clinical-Twin-Lab`
- Launch argument: `--odyssey-clinical-twin`
- Stable AVP scheme: `UpperLimbPOC`

The lab route is compiled only in Debug and is off by default. Release builds exclude its Swift sources and CT R8/JSON resources. The normal AVP and companion flows are unchanged.

## Phase 1 behavior

1. `Start Right Forearm Session` opens the CT-derived twin at a fixed mixed-reality position. This proves the model is visible before tracking is requested.
2. `Attach beside right forearm` starts the existing `HandTrackingProvider` path and consumes only the right wrist/forearm observations.
3. The model-local longitudinal axis scales to the tracked wrist-to-forearm length. The wrist transform contributes roll, and a 16 cm side offset keeps the twin beside the real arm.
4. `Reveal Anatomy` continuously fades the soft-tissue surface out and the paired bone-density surfaces in.
5. Partial or missing tracking is labelled. After a valid live pose, stale/failed tracking freezes and dims the last safe transform for up to three seconds, then returns to a labelled static reference. It never extrapolates arbitrary depth or motion.

## Reference-data limits

The source is a public cadaver reference CT from the NLM Visible Human Male `normalCT` series. The committed derivative is a 112 × 160 × 21 R8 texture (376,320 bytes) with SHA-256 `43244b476c3e409dc1b32d2f55982b4f3946c058063b4d187c617b8243ef3a2d`. Raw source images, DICOM, identifiers, and caches are not committed.

The selected source spans only 60 mm longitudinally and part of its field of view is truncated. The lab mesh stretches that slab to an approximate forearm length. Its right-side placement is a demo behavior and does not assert the scan's anatomical laterality or orientation. The two extracted high-density components are consistent with paired forearm bones but are not yet named radius/ulna pending anatomical review.

## Physical acceptance gate

Automated builds and simulator output cannot verify the following. Test them in order on the physical headset:

1. The static CT-derived twin is visible, opaque, and clearly separate from the real right forearm.
2. Surface → Bone reveal exposes both paired bone-density structures.
3. After attachment, the twin follows right-forearm translation and flexion with an acceptable side offset.
4. Forearm rotation produces a corresponding twin roll without left/right switching or side flips.
5. Brief tracking loss freezes and dims the twin instead of drifting.

These remain `DEVICE-PENDING / NOT VERIFIED` until the wearer records a result for every row.
