# Odyssey Clinical Education session contract

Status: isolated Phase 2 contract candidate. Do not integrate until the tracked
Right Forearm twin passes the Phase 1 gate.

This contract is for a generic, CT-derived reference Right Forearm used in an
educational demonstration. It is not patient-specific imaging, diagnosis,
surgical navigation, or a validated surgical plan.

## Compatibility boundary

The existing `ClinicianGuidanceProtocol` remains version 1 and is unchanged.
The new wire family is separately identified by:

- protocol identifier: `odyssey-clinical-session`
- protocol version: `1`
- locked case: `Odyssey`
- locked model: `Right Forearm VRT`
- laterality: `right`

`OdysseyClinicalSessionWireCodec.decodeIfOdysseyClinicalSession(_:)` returns
`nil` for existing clinician-guidance and snapshot packets. A transport
multiplexer can therefore pass those packets to their existing codecs. Once a
packet declares the new protocol identifier, malformed or unsupported content
fails closed.

## Authority and synchronization

- The iPhone/iPad companion owns clinician intent in
  `OdysseyClinicalDesiredState`.
- The Apple Vision Pro owns the selected renderer route, tracked frame, pose,
  tracking state, and `OdysseyClinicalAppliedState`.
- The companion may hold only one in-flight desired command. Disconnected,
  stale, unsupported, invalid, and already-pending commands are not queued.
- An acknowledgment records progress but never changes the applied state.
  Only an AVP-applied snapshot can confirm the Reveal Anatomy value.
- On reconnect, the AVP sends its last applied snapshot. The companion displays
  it as AVP-confirmed state, separately from the desired value.
- Sequence numbers must increase, message identifiers cannot replay, and old or
  excessively future-dated messages are rejected.
- The central stale threshold is three seconds.

## Locked state

`OdysseyClinicalSessionDescriptor.odysseyRightForearmReference` fixes the
reference demo to:

| Field | Value |
|---|---|
| Patient | `Odyssey` (`isReferenceDemoPatient = true`) |
| Model | `Right Forearm VRT` (`isReferenceAnatomy = true`) |
| Laterality | `right` |
| Disclosure | Reference anatomy for education; not patient-specific imaging, diagnosis, or a validated surgical plan |

The reveal value is finite and normalized to `0...1`: `0` is Surface and `1`
is Bone. Local controls may clamp. Out-of-range wire values are malformed.

The AVP reports one renderer route:

- `spatialVRT`
- `ctDerivedMeshFallback`

The route is AVP-applied truth; the mobile UI must not infer it from the reveal
slider or advertise VRT when the mesh fallback is active.

## Tracking and presentation

Tracking states are `searching`, `live`, `stale`, and `failed`. `followArm` is
the default presentation. `held` is declared for the explicit last-safe-pose
state and for a future negotiated hold feature; it is not a baseline mobile
control. Rejected states have no presentation mode because no twin pose is
being claimed.

A live applied state requires:

- a matching source message identifier and sequence;
- a fresh tracking-frame identifier and timestamp;
- confidence at or above `0.7`;
- `followArm` presentation;
- an AVP-selected renderer route; and
- no failure reason.

A stale pose is valid only as `heldStale`: the last safe, sufficiently
confident frame remains frozen, with `trackingStale` reported visibly. A
searching, failed, missing, weak, or otherwise unusable frame is rejected; it
cannot be represented as live or assigned arbitrary depth.

## Payloads

Every `OdysseyClinicalSessionMessage` carries the protocol identifier/version,
session ID, message ID, monotonically increasing sequence, send timestamp, and
exactly one payload:

- `handshake`
- `desiredState`
- `appliedState`
- `acknowledgment`
- `heartbeat`
- `error`

The required capability set covers desired and applied reveal, renderer route,
twin tracking state, acknowledgments, heartbeat, and follow-arm presentation.
Unknown capabilities remain decodable. Missing required capabilities disable
commands and surface an error.

## Frontend handoff

Claude's presentation should consume a production object conforming to
`OdysseyClinicalSessionControlling`, not `PeerSession` directly. Child views
receive `OdysseyClinicalSessionClientState` plus an
`OdysseyClinicalSessionActionSet`.

Use these fields:

- `state.descriptor.patient.displayName`
- `state.descriptor.model.displayName`
- `state.connectionState`
- `state.desiredState.reveal.value` for the slider
- `state.confirmedReveal?.value` for AVP-confirmed display
- `state.rendererRoute`
- `state.trackingState`
- `state.presentationState`
- `state.isPending`
- `state.isDesiredStateConfirmed`
- `state.lastAcknowledgedAt`
- `state.lastAppliedAt`
- `state.lastError`
- `state.canSendCommands`

Available actions are:

- `setReveal(Double)`
- `retryConnection()` only when the production adapter exposes retry

The frontend must disable Reveal Anatomy while `canSendCommands` is false. It
must not display desired state as applied, fake a live AVP view, expose a
technical renderer selector, offer offline queuing, or describe the reference
model as the wearer's anatomy.

## Production integration requirements

This isolated checkpoint deliberately does not modify `PeerSession`, Xcode
target registration, project settings, or either presentation. After Phase 1
is green, the integration owner must:

1. register the three contract/codec/adapter sources in both relevant targets;
2. add a distinct PeerSession routing discriminator that tries
   `decodeIfOdysseyClinicalSession(_:)` without consuming legacy packets;
3. build a production synchronization engine around the pure adapter;
4. advertise only the renderer route and capabilities actually available on
   the installed AVP build;
5. send AVP-applied state only after the renderer and a valid tracking frame
   agree;
6. freeze/dim the last safe pose on stale tracking and reject when no safe pose
   exists;
7. keep the feature behind the existing lab-only selection until physical AVP
   evidence is accepted; and
8. rerun the full repository validator and both platform build matrices.

## Deterministic evidence

`Tools/OdysseyClinicalSessionContractCheck.swift` covers:

- locked Odyssey/Right Forearm identity and disclosure;
- Reveal Anatomy bounds;
- every payload round trip;
- required and unknown capability negotiation;
- live confidence and frame freshness;
- explicit stale-pose hold and searching rejection;
- session mismatch, replay, ordering, age, and future-skew gates;
- disconnected/stale/no-queue behavior;
- one in-flight command;
- desired-versus-applied separation; and
- unchanged legacy clinician-guidance routing and round trip.

This is automated contract evidence only. It does not verify device transport,
renderer visibility, arm attachment, stale-pose appearance, performance,
comfort, or physical Apple Vision Pro behavior.
