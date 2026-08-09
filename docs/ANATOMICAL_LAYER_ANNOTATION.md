# Anatomical-layer annotation foundation

Status: experimental, feature flag **OFF by default**, physical AVP status
**DEVICE-PENDING / NOT VERIFIED**.

> Illustrative anatomical model — not patient-specific imaging.

This foundation defines a device-independent contract for asking an eventual AVP
renderer to project a normalized screen annotation onto one explicitly selected
generic anatomical surface. It does not connect that request to the stable
clinician-guidance session, change the judge-demo controls, or claim measured
anatomical accuracy.

## Contract boundary

`AnatomicalAnnotationWireMessage` is a separate version-1 envelope. It carries a
session ID, message ID, monotonic sequence number, send time, and either an
`AnatomicalAnnotationRequest` or `AnatomicalAnnotationProjectionResult`.

Each request carries:

- an annotation UUID;
- a frame identifier and capture timestamp;
- normalized screen coordinates with top-left origin and bounds `[0, 1]`;
- one target layer: `skin`, `subcutaneousFat`, `muscle`, `bone`, or `floating`;
- exactly one point or one circle.

Each result repeats the annotation, frame, source geometry, and layer, then
reports `applied` or `rejected`, projection confidence, a typed failure reason,
and—only when applied—a forearm-local position, unit surface normal, and optional
circle radius in metres.

The published `ClinicianGuidanceProtocol` remains version 1 and its codec,
message gate, synchronization engine, peer wire decoding order, and runtime UI
are unchanged. No annotation packet is sent by production code on this branch.

## Compatibility and fail-closed rules

Requests created before layer selection, and unknown future layer strings,
decode as `floating`. `floating` deliberately has no anatomical surface, so the
projector rejects it with `unsupportedTargetLayer`; it never invents a depth.

Projection is also rejected when the feature is disabled, coordinates are
invalid, the frame ID differs, the frame is older than 250 ms, tracking is not
live, tracking confidence is below 0.8, the ray is invalid, the selected surface
is missed/unavailable, or combined projection confidence is below 0.8.

Circles project a center and one edge ray onto the same selected layer. Both
intersections must pass. There is no fallback to a different layer and no
arbitrary-depth estimate.

## Coordinate and surface model

`AnatomicalScreenRayProviding` converts a normalized screen point plus a frame
reference into a ray and confidence. `AnatomicalLayerSurfaceProjecting` intersects
that ray with one requested layer. `AnatomicalSurfaceProjector` returns the point
and normal in a single forearm-local coordinate root:

- origin: centre of the generic forearm;
- local `+Y`: proximal-to-distal forearm axis;
- local `X/Z`: radial cross-section axes;
- lengths and radii: metres.

The deterministic preview surface is a simplified finite-cylinder model with a
skin shell, subcutaneous-fat shell, muscle volume, and separate radius/ulna
cylinders under `GenericForearmCoordinateRoot`. It is for algorithm checks and
SwiftUI previews only—not segmentation, registration, imaging, or a patient
model.

`GenericAnatomicalForearmPreview` demonstrates exactly one snapped point and one
snapped circle. It is compiled only for `DEBUG` previews. The feature policy used
by normal runtime is `AnatomicalProjectionPolicy.production`, whose flag is
`false`.

## Claude frontend handoff

Claude may consume these shared types after rebasing onto this branch:

- `AnatomicalLayerTarget`
- `AnatomicalNormalizedScreenPoint`
- `AnatomicalAnnotationFrameReference`
- `AnatomicalAnnotationGeometry.point(at:)`
- `AnatomicalAnnotationGeometry.circle(center:normalizedRadius:)`
- `AnatomicalAnnotationRequest`
- `AnatomicalAnnotationProjectionResult`
- `AnatomicalProjectionFailureReason`
- `AnatomicalAnnotationWireMessage`
- `AnatomicalAnnotationWireCodec`

Frontend requirements for a later, separately authorized slice:

1. Keep the feature flag OFF in normal production/demo runtime.
2. Do not call `PeerSession` directly from child views; use a mockable action and
   state adapter owned by the integration layer.
3. Attach commands to the exact displayed frame ID/timestamp and normalized point
   or circle coordinates.
4. Show pending/applied/rejected truthfully; surface the typed rejection reason.
5. Never render a successful snap until AVP returns an `applied` result.
6. Keep the disclosure visible anywhere the generic model is previewed.
7. Do not add freehand, patient images, inferred depth, or simulated physical
   accuracy.

Not included in this foundation: live camera unprojection, AVP compositor frame
binding, anatomical registration, production transport negotiation, state resync,
rendered RealityKit shells, or physical accuracy/attachment evidence. Those are
explicit **DEVICE-PENDING** integration items.
