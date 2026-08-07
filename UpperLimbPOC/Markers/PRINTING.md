# Elbow and wrist landmark markers

Print `elbow-marker.svg` and `wrist-marker.svg` at **80 mm × 80 mm**, with page scaling set to **100% / Actual Size**.

For the controlled forearm demonstration:

1. Place the **ELBOW** marker over the approximate elbow joint landmark.
2. Place the **WRIST** marker over the approximate wrist joint landmark.
3. Keep both markers flat, unobstructed, and visible to Apple Vision Pro.
4. In the Vision app, select the correct left or right **Forearm & Hand** card.
5. Leave **Follow ELBOW + WRIST markers** enabled and open the overlay.

The app accepts marker separation from 0.12 m to 0.45 m. It scales the model using the measured elbow-to-wrist distance, aligns the model’s long axis to the two landmarks, smooths updates, and fades the overlay when either marker is lost.

This is an educational registration approximation. Surface landmarks do not reveal the exact position of an individual patient’s internal bones.
