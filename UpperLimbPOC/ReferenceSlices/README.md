# Reference forearm CT slices

These five 8-bit PNG textures are cropped educational reference images from the
National Library of Medicine (NLM) Visible Human Male `normalCT` series:

- `reference-forearm-01.png` <- `cvm1680f.png`
- `reference-forearm-02.png` <- `cvm1695f.png`
- `reference-forearm-03.png` <- `cvm1710f.png`
- `reference-forearm-04.png` <- `cvm1725f.png`
- `reference-forearm-05.png` <- `cvm1740f.png`

Source directory:
https://data.lhncbc.nlm.nih.gov/public/Visible-Human/Male-Images/PNG_format/radiological/normalCT/

Dataset information:
https://www.nlm.nih.gov/research/visible/visible_human.html

The NLM describes the Visible Human Project image library as public domain and
states that a licence is no longer required. Credit remains included here for
traceability and respectful reuse.

Processing for this prototype:

1. Normalize the 16-bit source PNG display range to an 8-bit grayscale image.
2. Crop the forearm visible on the left side of the radiological image to
   `112 x 160` pixels (`x=0`, `y=130`).
3. Preserve the source slice order from proximal to distal reference levels.

The crops do not retain clinically usable A/P or R/L orientation annotations.
Orientation and laterality are explicitly presented as illustrative in the app.

These images, the AnatomyTOOL 3D mesh, and the live participant are different
anatomical sources. Their mixed-reality alignment is approximate and based on
external landmarks. This prototype is educational, not patient-specific,
diagnostically accurate, or intended for clinical decision-making.
