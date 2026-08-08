# Apple Vision Pro joint capability probe

## Question

Can a standard visionOS app obtain named joint positions that are useful for
the educational forearm-overlay registration experiment?

This probe separates three claims that must not be blended:

1. **Wearer hand:** ARKit can expose a tracked hand skeleton for the person
   wearing Apple Vision Pro.
2. **Another person:** standard visionOS does not expose a whole-body ARKit
   provider for a person standing in front of the wearer.
3. **Environment surface:** LiDAR-derived scene reconstruction provides an
   unlabelled surface mesh, not elbow, shoulder, hip, or knee identities.

Camera-based pose detection of another person is a separate research track. It
requires approved enterprise main-camera access and a licensed app build, then
a validated Vision/Core ML provider that transforms camera-relative output
into the app's world coordinate space.

## What this prototype measures

The app renders one sphere at every tracked hand-skeleton transform reported by
the current visionOS runtime:

- cyan for the left hand;
- orange for the right hand;
- hidden whenever that joint is not tracked.

The 30-second test records only anonymous counts and timing. It does not retain
camera images, hand transforms, video, body geometry, or personal data.

Four points form the registration-critical continuity set: wrist, index
knuckle, index intermediate base, and index intermediate tip. A continuity
pass requires at least 30 hand updates and all four points present in at least
90% of frames for one hand during a run of at least 25 seconds.

Continuity is not accuracy. This test does not measure millimetre error against
a physical reference and cannot prove internal-bone position.

## Physical AVP run card

1. Connect and trust Apple Vision Pro, then enable Developer Mode on the
   headset.
2. Open `RadiographicAnatomyPOC.xcodeproj` in Xcode 27 beta.
3. Select the Apple Development team for the `UpperLimbPOC` target under
   Signing & Capabilities.
4. Select the physical Apple Vision Pro destination and press Run.
5. In the anatomy library, open **Test AVP joint detection** and allow Hands
   Tracking.
6. Press **Start tracking**. Confirm cyan and/or orange joint spheres follow
   the wearer's hands.
7. Press **Run 30-second continuity test**. During the run:
   - hold both hands neutrally for five seconds;
   - flex and extend the fingers;
   - rotate each wrist;
   - briefly hide one hand for about two seconds;
   - bring it back and confirm reacquisition.
8. Record the on-screen verdict and a headset screen recording. Do not record
   another person or patient without the appropriate consent.
9. Repeat once under the same lighting and hand positions.

## Decision rule

**Adopt the hand provider for the next hybrid-registration experiment** when at
least one controlled run reaches `CONTINUITY PASS`, the spheres visibly follow
the correct hand, and lost joints do not remain falsely visible.

**Reshape or stop this route** when either condition is met:

- two controlled runs fail to reach 90% critical-joint continuity; or
- tracking loss cannot be presented truthfully as lost/stale.

This is the kill criterion for using native hand joints as a live registration
provider. It does not kill the marker/manual provider.

## What a pass means for the overlay

A pass supports wrist and finger observations for the wearer. It does not
support automatic elbow, shoulder, hip, knee, ankle, or another-person body
joint detection. The current forearm overlay still needs a visible elbow
marker or a human-confirmed elbow point. Full-frame alignment still needs three
non-collinear correspondences.

## Follow-on research choices

1. Measure hand-joint accuracy against visible physical fiducials.
2. Apply for development-only enterprise main-camera access and test Vision
   2D/3D body pose on a consenting participant.
3. Use an external iPhone/iPad pose provider and stream named landmarks to AVP.
4. Keep image markers/manual points as the transparent baseline.
