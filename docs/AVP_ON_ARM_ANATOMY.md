# AVP on-arm anatomy lab

Status: DEBUG-only isolated lab route. Automated gates can verify the asset and pose logic; all wearer visibility, alignment, motion, occlusion, and comfort findings remain DEVICE-PENDING until a physical Apple Vision Pro test.

> Reference anatomy alignment — not patient-specific imaging.

## Why this route exists

The wearer-arm diagnostic route intentionally draws procedural dots, spheres, and cylinders. Those shapes prove that Apple Vision Pro hand/forearm joints are available, but they are not anatomy. The separate on-arm lab loads the bundled `hand-to-elbow-overlay.usdz` and fails explicitly if `Radius_r`, `Ulna_r`, metre-scale bounds, or the asset itself are unavailable.

The integrated beside-arm clinical-twin route now reuses this validated Blender USDZ and displays the complete hand-to-elbow skeletal asset. The procedural diagnostics route remains separate and is not presented as anatomy.

## Asset and mapping contract

- Source asset: existing generic AnatomyTOOL-derived `hand-to-elbow-overlay.usdz`.
- SHA-256: `72ce34528dc5f56915e43c018948fd5a1898489880c19ff4c64e6e39352a3f94`.
- USD metadata: `metersPerUnit = 1`, Z-up.
- Required named nodes: `Radius_r` and `Ulna_r`.
- Audited mesh lengths: radius approximately 239.9 mm; ulna approximately 262.5 mm.
- Reference scaling uses the 262.5 mm ulna length.
- The model elbow-to-wrist axis is local -Z. The asset is centred on the combined radius/ulna bounds before the root is mapped to the live `forearmArm` to `forearmWrist` axis.
- Wrist X orientation supplies roll when it is valid. Sign continuity prevents calibration axes from flipping between nearby poses.
- Default calibration is zero offset, 1.0 scale, and zero roll correction.

This is a generic educational best fit, not exact CT registration. HandTrackingProvider does not measure a participant's internal radius/ulna position, individual bone shape, or soft-tissue thickness.

## Explicit visibility experiments

Use the `UpperLimbPOC-On-Arm-Anatomy-Lab` scheme. Its `--avp-on-arm-anatomy` argument is enabled in Xcode; the safe app default is unchanged.

The lab offers two separate immersive-space routes:

1. **Normal overlay** requests visible system upper limbs. This preserves the real arm, but the system compositor may occlude virtual bones.
2. **See-Through Anatomy** requests hidden system upper limbs. It substitutes the virtual generic model where the system hides real arms. It does not reveal anatomy beneath a visible real arm.

The static gate shows the full opaque USDZ at a known location in front of the wearer. Only after the wearer confirms that asset does the lab allow right-forearm alignment. The tracked route hides all other hand/finger meshes and shows only `Radius_r` and `Ulna_r`.

The integrated `ClinicalTwinSpace` is intentionally different: it keeps the full rigid hand-to-elbow asset, hides system upper limbs, places the twin 16 cm beside the tracked right forearm, and uses the negotiated reveal value as model opacity.

## Tracking failure behavior

- Initial searching/partial/failed tracking hides the tracked anatomy rather than estimating depth.
- A previously live pose is frozen exactly and dimmed for up to 3 seconds.
- After the 3-second hold expires, the anatomy is hidden rather than drifting or jumping to a fake static alignment.
- Procedural dots/cylinders remain available only in the separate Diagnostics route.

## Deferred work

The USDZ contains separate hand and finger meshes but no armature or actions. Full fingers require a reviewed named-bone/pivot mapping driven by ARKit parent/child joint transforms. Moving the rigid hand root is not accepted as articulation, so this work is deferred until radius/ulna placement passes the physical forearm gate.

## Physical gate, one observation at a time

1. Static full USDZ visible in Normal overlay.
2. `Radius_r` and `Ulna_r` visible after right-forearm alignment.
3. Approximate on-arm centreline/length alignment.
4. Attachment through translation, flexion, and forearm rotation.
5. Tracking interruption freezes/dims, then hides after 3 seconds without drift.
6. Repeat visibility in See-Through Anatomy and record the compositor difference.

Do not mark a row PASS from a simulator or generic device-SDK build.
