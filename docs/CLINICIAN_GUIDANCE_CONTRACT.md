# Clinician guidance contract

Status: frozen judge-build contract, protocol version 1.

This contract synchronizes generic educational forearm guidance between one
iPhone/iPad companion and one Apple Vision Pro. It sends semantic state, never
camera pixels, participant images, patient data, DICOM, gaze coordinates, or
raw ARKit transforms. The fracture marker and preset incision guide are
illustrative POC annotations, not patient-specific findings or procedural
advice.

## Authority and coordinate semantics

- The companion is authoritative for clinician **desired** guidance.
- Vision Pro is authoritative for hand tracking, spatial mapping, tracked side,
  and **applied** rendered guidance.
- Desired and applied state remain separate. The companion must show a pending
  mismatch until Vision Pro acknowledges and publishes its applied snapshot.
- `ClinicianForearmPosition.value` is finite and bounded to `[0, 1]`:
  - `0` = proximal, at the tracked `forearmArm` endpoint (near elbow);
  - `1` = distal, at the tracked `forearmWrist` endpoint (wrist);
  - intermediate values are linear interpolation on the live AVP forearm axis.
- The companion clamps local slider values. The wire decoder rejects non-finite
  or out-of-range values rather than silently accepting malformed input.
- `showBone` is independent from fracture/incision guidance. Hiding the bone
  does not erase `fracturePosition` or `showIncisionGuide`.
- A clear command removes fracture/incision guidance while carrying the desired
  bone visibility unchanged. It is immediate and receives a normal ACK.
- `participantSide` is `left`, `right`, or `unknown`; the AVP applied state is
  authoritative. Version 1 has no companion side-selection action.

## Wire envelope

Every `ClinicianGuidanceMessage` contains:

- `protocolVersion`
- `sessionID`
- `messageID`
- monotonically increasing `sequence`
- `sentAt`
- exactly one typed payload

Payload kinds are:

1. `handshake` — endpoint role, supported versions, capability identifiers, and
   optional read-only `peerDisplayName`;
2. `desiredGuidance` — explicit set or clear command plus the resulting desired
   state;
3. `appliedGuidance` — actual AVP state, tracked side, tracking/application
   status, and source command identity when applicable;
4. `acknowledgment` — applied, accepted-pending-tracking, duplicate, or rejected;
5. `heartbeat` — endpoint liveness and latest received/applied sequence;
6. `error` — typed recoverable/non-recoverable error with optional correlation.

Unknown capability strings remain decodable so negotiation can report them.
Unknown protocol versions, malformed payloads, stale timestamps, future-skewed
timestamps, replayed message IDs, and non-increasing sequences fail closed.

## Capabilities

The version-1 judge set is `ClinicianGuidanceCapability.judgeMVP`:

- `desired-guidance`
- `applied-guidance`
- `acknowledgment`
- `heartbeat`
- `normalized-forearm-position`
- `preset-incision-guide`
- `clear-guidance`

No POV streaming, freehand drawing, camera frame, scanner, assistant, patient
record, or external backend capability is part of version 1.

## Connection and command rules

`ClinicianGuidanceClientState` exposes:

- `connectionStatus`: disconnected, connecting, connected, syncing, stale, or
  error;
- `desiredGuidanceState`;
- `appliedGuidanceState`;
- one optional `pendingMessageID`;
- `lastAcknowledgedAt`;
- recoverable `lastError`;
- optional `peerDisplayName`;
- applied/AVP-authoritative `participantSide`.

The central heartbeat interval is 1 second and the stale threshold is 3
seconds. Version 1 permits a single in-flight command and has no offline queue.
`canSendGuidanceCommands` is true only while connected with no pending message.
Disconnected, connecting, syncing, stale, and error states must disable new
guidance controls.

On reconnect within an app session:

1. exchange handshakes and negotiate version/capabilities;
2. companion resends its latest desired state as a new message/sequence;
3. AVP validates and applies what tracking permits;
4. AVP returns ACK plus its applied snapshot.

An app restart creates a new session ID and sequence space. No queued command
from an old session is replayed.

## Frontend API

Claude-owned child views consume values and closures, never `PeerSession`:

- state: `ClinicianGuidanceClientState`
- actions: `ClinicianGuidanceActionSet`
- controller boundary: `ClinicianGuidanceControlling`
- action names:
  - `setBoneVisible`
  - `setFracturePosition`
  - `setIncisionGuideVisible`
  - `clearGuidance`
  - optional `retry`

The diagram is driven by `appliedGuidanceState`; controls are driven by
`desiredGuidanceState`; `pendingMessageID` makes mismatch visible. A fracture
slider sends once on interaction end, not continuously.

## Physical evidence boundary

Contract, codec, ordering, bounds, and builds can be verified without a headset.
Overlay attachment, occlusion, comfort, simple flexion, pronation/supination,
and judge usability remain `[BLOCKED] DEVICE-PENDING / NOT VERIFIED` until a
physical Vision Pro retest.
