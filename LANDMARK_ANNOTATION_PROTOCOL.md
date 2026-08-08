# Landmark annotation review

The prototype exposes seven coloured, model-local annotation candidates:

- **Red — Elbow reference:** midpoint of the proximal radius and ulna surfaces
  in the current forearm-only mesh.
- **Green — Distal radius:** centre of the distal radius surface near the
  wrist.
- **Blue — Distal ulna:** centre of the distal ulna surface near the wrist.
- **Orange — Index MCP:** index-finger metacarpophalangeal joint.
- **Yellow — Index PIP:** index-finger proximal interphalangeal joint.
- **Pink — Index DIP:** index-finger distal interphalangeal joint.
- **Purple — Index tip:** distal endpoint of the index-finger distal phalanx.

The elbow, wrist, and index-finger coordinates were selected in Blender during
a clinician-guided review and exported in `UpperLimbPOC/AnatomyLandmarks.user.json`.
They remain review landmarks, not approved anatomical truth or diagnostic
registration data.

The repeatable Blender helper is `Tools/blender_landmark_batch.py`. It displays
the current landmark name, ray-casts each left-click to the visible mesh,
creates or updates a named marker, and exports the complete JSON set after each
capture. Backspace undoes the previous capture and Escape stops the batch.

## Reviewed coordinates

All values are in imported-model local metres.

For this reviewed scene, Blender scene world is the imported USD stage-root
coordinate system. This was checked against the authored USD transforms (for
example, Blender and USD both place `Radius_r` at
`0.269325, 0.013978, -0.909339` with unit scale). The viewport was adjusted for
clicking, but the imported model objects were not transformed after import.
The batch helper now also provides an optional **Model anchor**: if a future
scene moves the imported anatomy under a parent transform, select that parent
and the helper converts ray-cast world hits through its inverse before export.

| Landmark | X | Y | Z |
|---|---:|---:|---:|
| Elbow reference | 0.039852 | 0.054006 | 0.185587 |
| Distal radius | -0.004117 | -0.004471 | -0.037588 |
| Distal ulna | 0.025707 | -0.003168 | -0.039805 |
| Index MCP | -0.027149 | -0.025324 | -0.139703 |
| Index PIP | -0.039851 | -0.041607 | -0.173793 |
| Index DIP | -0.044962 | -0.057959 | -0.189123 |
| Index tip | -0.049405 | -0.068787 | -0.200471 |

The derived wrist-centre midpoint is `(0.010795, -0.003820, -0.038697)`.

## Review on Apple Vision Pro

1. Open the Forearm & Hand overlay.
2. Open the tracking-status window and expand **Landmark annotation review**.
3. Turn on **Show 3D landmark markers**.
4. Select each landmark and use the X, Y and Z controls to place the sphere at
   the intended bone landmark.
5. Record the displayed model coordinates after each point is accepted.

The selected sphere is enlarged. Coordinate controls use 1 mm increments.
Annotation changes are deliberately local and do not alter live registration
until the coordinates have been reviewed and committed as registration data.

## What needs human confirmation

- Whether the red point represents the most reproducible proximal forearm
  reference when the model has no humerus.
- Whether the green and blue points sit at the intended distal radius and ulna
  reference surfaces.
- Whether the midpoint of the two wrist points is suitable as the wrist centre.
- Which of the two distal points should define the forearm's rotational axis on
  the physical participant.
- Whether the index MCP/PIP/DIP points remain centred when reviewed from an
  orthogonal view; a single surface click does not establish an internal joint
  centre.

## Physical index-finger motion check

1. Wear Apple Vision Pro, open the forearm-and-hand overlay, and allow both
   World Sensing and Hands Tracking access.
2. Align the overlay using the ELBOW and WRIST markers while the selected hand's
   index finger is held comfortably extended.
3. Confirm that the status window reports selected-hand index joints as live.
4. Slowly flex and extend the MCP, PIP, and DIP separately, then together.
5. From two viewing angles, check that each phalanx rotates around its coloured
   reviewed landmark and that no visible gap opens between adjacent phalanges.
6. Briefly hide the hand, then show it again. Confirm that reacquisition does
   not snap the finger to an unrelated pose.

Record video and pass/fail notes for both hands. Simulator builds cannot satisfy
this acceptance check because they do not provide physical ARKit hand joints.

For a future elbow CT case, annotation must be performed in the CT patient
coordinate system. At minimum, record the humeral joint centre, radial-head
centre, and an ulnar reference point. DICOM orientation describes voxel
geometry but does not identify these anatomical landmarks automatically.
