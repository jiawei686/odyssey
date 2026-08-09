# Odyssey Clinician-Guided Forearm Overlay Demo Runbook

## Release candidate

- Branch: `codex/clinician-annotation`
- Code integration SHA: `bd69902d5d2f2c6b130917b52abcd3c1b33e09d2`
- Physical status: **DEVICE-PENDING / NOT VERIFIED**

This POC uses a generic educational teaching model. It is not for diagnosis, patient-specific imaging, surgical navigation, or a validated surgical plan.

## Three-minute judge pitch

### 0:00–0:30 — Problem and problem-solution fit

Flat-screen anatomy explanations are difficult for patients to translate onto their own bodies. Clinicians need a clearer, more intuitive way to explain where an issue or planned discussion sits along the forearm.

### 0:30–0:50 — Solution and novelty

Odyssey creates a shared spatial teaching surface on the Vision Pro wearer's forearm. A clinician uses a familiar iPhone or iPad interface while the wearer sees the same confirmed educational guidance aligned in space.

### 0:50–1:50 — Live flow and interface delight

1. Show the real companion-to-Vision-Pro connection and confirmed status.
2. Turn on the generic bone overlay.
3. Place the illustrative fracture marker along the elbow-to-wrist axis.
4. Show the preset educational incision guide, explicitly noting that it is not a surgical plan.
5. Clear the guidance immediately while preserving the chosen bone visibility.

Call out the simple native controls, the pending-versus-confirmed feedback, and the moment the spatial teaching model follows the wearer's arm.

### 1:50–2:20 — Technical implementation

Vision Pro uses hand and forearm tracking with RealityKit mapping. The companion connects locally through Bonjour and Network.framework. It sends semantic guidance—rather than screen pixels—and distinguishes clinician-desired state from AVP-applied state through acknowledgements. Replay/order protection and a stale-connection fail-safe prevent unsupported controls and hide remote guidance when the link is no longer trustworthy.

### 2:20–2:45 — Value today and future

Today, the POC targets clearer clinician-patient communication using a generic teaching model. Patient-specific anatomy, validated image registration, and clinically validated navigation remain future work requiring dedicated evidence and governance.

### 2:45–3:00 — Truthful close

Odyssey demonstrates a novel, body-aligned shared explanation interface with a tested software architecture. Automated builds and simulator evidence are green; physical end-to-end Vision Pro verification is still pending and will be reported separately.

## Physical acceptance checklist

Run these checks in order. Record **PASS** or **FAIL** and a concise observation for every row.

| # | Check | Result | Observation |
|---:|---|---|---|
| 1 | Install `codex/clinician-annotation` at code integration SHA `bd69902d5d2f2c6b130917b52abcd3c1b33e09d2` on the AVP and companion. |  |  |
| 2 | Verify a real handshake and truthful connection status; no mock or simulated connection. |  |  |
| 3 | Verify bone visibility and whether arm occlusion defeats the intended overlay. |  |  |
| 4 | Verify forearm/wrist following through simple flexion and forearm rotation. |  |  |
| 5 | Verify Show/Hide Bone changes the AVP-rendered bone state. |  |  |
| 6 | Verify the illustrative fracture marker at normalized positions `0` (elbow), `0.5` (mid-shaft), and `1` (wrist). |  |  |
| 7 | Verify the preset educational incision guide follows the tracked forearm and selected marker. |  |  |
| 8 | Verify Clear Guidance immediately removes fracture/incision guidance while preserving bone visibility. |  |  |
| 9 | Disconnect for more than three seconds; verify stale status, disabled companion controls, and hidden AVP remote guidance. |  |  |
| 10 | Reconnect; verify desired and applied state resynchronize truthfully. |  |  |
| 11 | Confirm every row has a PASS/FAIL result and concise observation; capture supporting media/logs. |  |  |

Do not merge `main` until all required physical checks pass.

## Fallback ladder

1. Never present a mock as a real connection.
2. If simulator media is used, visibly label it **Simulated** and disclose it verbally.
3. If the cross-device link fails after the agreed debugging window, demonstrate the AVP-local bone overlay and separate, truthful companion simulator evidence.
4. If fracture/incision attachment fails, remove those actions from the live judge path rather than misrepresenting their behavior.
5. Keep a prepared screenshot/video fallback and avoid adding new features during demo recovery.

## Device and logistics checklist

- [ ] AVP, iPhone/iPad, and Mac charged
- [ ] Chargers and required cables packed
- [ ] Device trust, Developer Mode, signing, and app profiles verified
- [ ] Same local network available; hotspot fallback tested
- [ ] Local-network permission granted
- [ ] Auto-lock/sleep disabled where appropriate for the demo
- [ ] Presenter, AVP wearer, and companion operator assigned

## Judge Q&A

**Is it patient-specific?**

Not yet. The current overlay is a generic educational teaching model, not patient anatomy or imaging.

**Does it diagnose?**

No. It is an explanation interface, not a diagnostic system.

**Why use a companion device?**

It lets the clinician control and explain what the wearer sees while both sides receive explicit connection and applied-state feedback.

**What data is transmitted?**

Semantic guidance state—bone visibility, normalized marker position, preset guide visibility, acknowledgements, and connection health—not patient images or records.

**What is novel?**

A clinician-controlled spatial explanation aligned to the wearer's body, with confirmed shared state rather than an assumed or duplicated display.

**What evidence exists today?**

Automated checks, target builds, static analyzers, and simulator compilation are green. Physical AVP end-to-end verification remains pending.

## Evidence classes

| Evidence class | Status | What it establishes |
|---|---|---|
| AUTO / BUILD / SIM | **PASSED** | Deterministic contract, synchronization, spatial and compatibility checks; iOS/visionOS simulator and unsigned device-SDK builds; static analyzers; companion strict-concurrency build. |
| DEVICE | **DEVICE-PENDING / NOT VERIFIED** | Real cross-device handshake, body attachment, occlusion, motion following, guidance application, stale fail-safe, and reconnect behavior still require the physical AVP checklist. |
| FUTURE / UNIMPLEMENTED | **NOT CLAIMED** | Patient-specific anatomy/imaging, validated registration, diagnosis, surgical navigation/planning, patient records, AVP POV streaming, and freehand annotation. |
