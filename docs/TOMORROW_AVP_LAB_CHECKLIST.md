# Tomorrow: Apple Vision Pro lab checklist

Status: **DEVICE-PENDING / NOT VERIFIED**. Do not treat simulator or build
evidence as physical Apple Vision Pro acceptance.

## Release candidate to open

- Prepared worktree: `/private/tmp/odyssey-avp-lab-rc`
- Branch: `codex/avp-lab-rc`
- Exact app-code commit: `f35c7a4ce8a3181094936c93af4ce5acb33f847b`
- CT spike source branch: `codex/ct-forearm-vrt-spike` at
  `82cc880ab7494fe92b3a8de8963b4644f11d2e48`
- Claude presentation source: `claude/anatomical-layer-ui` at
  `d8b87927dc6b00bb9729fc398cd545e0d53b2925`

The published branch tip adds this checklist and records the exact CT/Claude
lineages with tree-identical merge commits; it is reported in the overnight
handoff. Fetch/open the branch tip. The exact app tree installed by Xcode is
the app-code commit above.

## What this candidate genuinely contains

| Area | Current truth |
|---|---|
| AVP wearer app | Existing wearer hand/forearm tracking and generic articulated bone overlay path. This combined commit has not been installed on a physical AVP. |
| Real companion link | Existing local Bonjour/Network.framework session, clinician guidance handshake, desired/applied ACK state, replay/order protection, and stale fail-safe. |
| Anatomical lab UI | Minimal Connect → See → Reveal → Mark/Undo presentation. Connection status comes from the real `PeerSession`; no simulated connection is used. |
| Live AVP-aligned view | **Unavailable.** The lab UI states this explicitly and has no displayed frame. |
| Mark transport/projection | **Unavailable in the physical lab route.** Mark remains disabled without a frame identifier; no arbitrary depth is estimated. |
| CT reference | True Metal ray-marched NLM Visible Human reference CT on the companion, with Surface/Bone presets and continuous Reveal Anatomy. It is not wearer-specific imaging. |
| CT on the wearer | **Not implemented.** The CT volume is not yet attached to the AVP forearm pose; AVP continues to use the existing generic bone overlay. |
| Passthrough streaming/camera unprojection | **Not implemented.** No fake AVP video is shown. |

## Xcode and device preparation

- Xcode 27.0 beta, build `27A5228h`.
- Open `RadiographicAnatomyPOC.xcodeproj`.
- In Xcode Settings → Components, confirm Metal Toolchain build `27A5228f`
  is installed.
- The prepared worktree already contains ignored OpenCV/model build products;
  CT assets are committed and bundled, with no runtime download. Do not delete
  `Vendor/OpenCV/opencv2.xcframework` or `UpperLimbPOC/BodyScannerModels` before
  the lab run.
- Charge the AVP, companion iPhone/iPad, and Mac; bring chargers and cables.
- Enable Developer Mode and trust the Mac on both devices.
- Put AVP and companion on the same Wi-Fi; keep a hotspot fallback ready.
- Enable Bluetooth and allow Local Network permission when prompted.
- Disable auto-lock/sleep where appropriate.
- Assign an AVP wearer and a companion operator.
- In Signing & Capabilities, select Marcel's available development team for
  both targets if team `QLYUY93X5V` is unavailable on the lab Mac.

The Info plists already declare `_upperlimb-poc._tcp`, local-network use, hand
tracking, and world sensing. No custom entitlement file is required by the
current project.

## Schemes and launch order

1. Select scheme **UpperLimbPOC**, destination **Marcel's Apple Vision Pro**,
   then Run. This is the wearer app.
2. Select scheme **UpperLimbCompanion-Anatomical-Lab**, destination the
   iPhone/iPad, then Run. The scheme embeds the lab launch argument; no Terminal
   command is needed.
3. Use the **Anatomy** tab for real connection status and fail-closed marking.
4. Use the **CT Reference** tab for the true CT Surface → Bone renderer. This
   tab is a standalone reference view and does not imply an AVP connection.
5. For the stable real clinician-guidance controls, use scheme
   **UpperLimbCompanion** instead. For the standalone CT-only route, scheme
   **UpperLimbCompanion-CT-Lab** remains available.

## Five-minute physical smoke test

Record PASS/FAIL plus one short observation for every row.

| Step | Action | Expected truthful result |
|---|---|---|
| 1 | Launch **UpperLimbPOC** on AVP and enter the forearm view. | App opens; tracking requests permission; no claim of attachment until markers/overlay are visible. |
| 2 | Launch **UpperLimbCompanion-Anatomical-Lab** on the companion. | Status changes from Connecting/Waiting to Connected only after a real Bonjour connection. Never accept a simulated label as physical evidence. |
| 3 | Open **CT Reference** and move Reveal Anatomy from Surface to Bone. | One bundled CT volume changes continuously from soft-tissue emphasis to two bone structures; reference-anatomy disclosure remains visible. |
| 4 | Return to **Anatomy** and try Mark/Undo. | With current capabilities, live AVP view is unavailable and Mark stays disabled. This fail-closed result is expected. If a real frame capability unexpectedly becomes available, place and undo one mark and record the frame/rejection status. Do not enable the synthetic diagnostics source for physical evidence. |
| 5 | On AVP, show the existing generic bone overlay; flex and rotate the forearm. | Joint markers and generic articulated overlay should follow wrist/forearm motion. Record drift, occlusion, detachment, or wrong laterality; this is DEVICE-PENDING until observed. |
| 6 | Disconnect the companion or leave Wi-Fi for more than 3 seconds. | Companion status becomes disconnected/stale, new real guidance controls are unavailable, and stale remote guidance is hidden by the existing fail-safe. |
| 7 | Rejoin Wi-Fi and relaunch/reconnect. | Real connection returns and existing desired/applied clinician-guidance state resynchronizes. The anatomical lab still does not invent a live view or mark capability. |

Stop rather than weaken a gate if connection, tracking, CT loading, or stale
handling differs from these expectations.

## Evidence to capture

- Screenshot the Anatomy tab while Waiting and after a real Connected state.
- Screenshot CT Reference at Surface and Bone.
- Record AVP video/photo in neutral, flexed, pronated, and supinated poses.
- Capture the companion/AVP state after more than 3 seconds disconnected and
  again after reconnect.
- In Xcode, retain console lines around Network.framework connection changes,
  tracking state, capability/ACK state, CT load status, and any projection
  rejection. Also capture the exact onscreen transport/rejection text.
- Note device models, OS versions, branch, commit, time, and operator/wearer.

## Stable fallback

- Branch: `codex/clinician-annotation`
- Exact SHA: `2ee5b322333ed4382a397023e2656bcdd0b075b6`
- Run **UpperLimbPOC** on AVP and **UpperLimbCompanion** on iPhone/iPad.
- Demonstrate only the existing real connection, generic wearer bone overlay,
  show/hide bone, illustrative fracture position, preset educational incision
  guide, clear, ACK/pending state, and stale disconnect behavior.
- If cross-device connection fails within the agreed debugging window, show the
  AVP-local generic overlay and separately labelled simulator evidence.
- If fracture/incision attachment fails, remove those actions from the live
  path rather than misrepresenting them.

PR #4 was already merged before this lab-candidate wrap-up; this task did not
modify it or `main`. The fallback branch remains available at the SHA above.
