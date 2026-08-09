# CT forearm VRT asset provenance

> Reference anatomy from the NLM Visible Human Male cadaver — not wearer-specific imaging.

## Source and reuse status

- Dataset: National Library of Medicine (NLM) Visible Human Project, male `normalCT` series.
- Dataset overview and reuse status: https://www.nlm.nih.gov/research/visible/visible_human.html
- NLM states that the image library is public-domain and that a licence has not been required since 2019.
- Download documentation: https://www.nlm.nih.gov/research/visible/getting_data.html
- Normal CT technical README: https://data.lhncbc.nlm.nih.gov/public/Visible-Human/Male-Images/radiological/normalCT/README
- PNG source directory: https://data.lhncbc.nlm.nih.gov/public/Visible-Human/Male-Images/PNG_format/radiological/normalCT/

The NLM describes a 512 × 512, 12-bit axial CT dataset. The distributed PNGs used here are 16-bit grayscale containers. The original GE headers report 0.8984375 mm in-plane spacing. For this selected region, the official file index provides locations every 3 mm; the source headers for `c_vm1680.fre` and `c_vm1740.fre` report -288.000 mm and -348.000 mm respectively, confirming the 60 mm span.

Header evidence is available from the same NLM `normalCT` directory as `c_vm1680.fre.Z` (compressed SHA-256 `cb3a26ceb36e952bea53df0834a58f341f0a5cbb5d010a0e6676d3ef741bfa0b`) and `c_vm1740.fre.Z` (compressed SHA-256 `d31f2e335744b436d19c5ec414818c68342f7a0c0b1e9092934969de3dc63610`). The decompressed header SHA-256 values used for inspection were `d70747d306302cedd81cc1b000c1a4cd4cc5cd76a0b00b03e2c4274390bc467c` and `1879b1c720588b3b9659d4795cd1594a3b8d653dd93e19d16278414ee4587fd0` respectively.

## Selected source images

The compact volume uses 21 consecutive available locations: `cvm1680f.png` through `cvm1740f.png`, inclusive, step 3. Each file URL is the PNG source directory above plus the filename. SHA-256:

- `cvm1680f.png` — `280e0ebd115c76be8740ea5d443ddf548bde042bc3ddef8a9d3d5e91bf34f422`
- `cvm1683f.png` — `de2d6553628f4d0ab6ccdf7c9cbc3c469c4cd4cb97cbfeef1f666f036e741cf2`
- `cvm1686f.png` — `d85c832b5ec075de2c8e3b8d98fe3ef65875ed7a1d91d172b3aecbf2546082a5`
- `cvm1689f.png` — `79dedf3922bb6151d8f3661b00515dbee9c4dcea83744fbad342dbbeacd7d351`
- `cvm1692f.png` — `7b48867536bbb2d62899b07d1647e5e20758aefcc1864bad40d1d7f3a7916a4f`
- `cvm1695f.png` — `1e0934baa1ed976f12fe8bf51495c6371312f7298f845b368320588a62ebefb5`
- `cvm1698f.png` — `11bee9fee07d38becbcbc72dd90c2ae93e62e7a159bee6041d736760d9ec46aa`
- `cvm1701f.png` — `7b7dc2454f5f3fb562ba348313a6c7a5a8fba2f14498c5a8ba0389d2f839ee62`
- `cvm1704f.png` — `1fc65804ab1a69cb74548a9315cd5a542dddbae174127f31b6f1f0233be07c19`
- `cvm1707f.png` — `422591da94a130d6c159554402f823dc59242b14c9cb2a3bffec1ac48336bc39`
- `cvm1710f.png` — `e5e5895f09dd9d012a346c3b9f21e03c12810a582a7fab08f3f568e3870462ed`
- `cvm1713f.png` — `3e6b6fc330a5b76e3e438d560eb174c24d313b754139ea2c3ec70bcd9e598718`
- `cvm1716f.png` — `8ed19b3a01d950df58b17e335de56a0e6d7c50caa01b03806d2f25b569c1206d`
- `cvm1719f.png` — `1558222dc67c9002521427bb5b7d8c4deda1413fdb163dde32630e4006a9b48a`
- `cvm1722f.png` — `e1bee731832068f7f54520c6c85a6765b61b3c961c7da57ce81d42a51dc92b3f`
- `cvm1725f.png` — `dc6475c356969ee69ae14e134c9a587da6ea20e4ecf56c8a25b017f9b9f07b9a`
- `cvm1728f.png` — `e6adcda29b49f03e5805bb71963e25dbc4c21236e67844efa19c7b2b3530354a`
- `cvm1731f.png` — `c930d51812218924ed0d980b5c7ab49a0d6f997e260681e2bb63ef7d705389d1`
- `cvm1734f.png` — `b6a9cc02c0be16bcd02de778d5bd70f3ab62ad9b094d1ffca214e0eb429ba877`
- `cvm1737f.png` — `8563f212f31053c0cb81c4dd7933407784781fec183d648023733c93f521ec07`
- `cvm1740f.png` — `917de5a5cd2880ec8d4b23073cb2afb0922364ccbc11ac4d9036e5298a513717`

## Deterministic processing

Run `Tools/build_ct_forearm_volume.swift` against a directory containing only the downloaded source PNGs. It crops each slice at `x=0, y=130, width=112, height=160`, preserves ascending location order, and quantizes each 12-bit source value with `UInt8(clamp(round(value / 8), 0...255))`.

Generated asset: `visible-human-male-forearm-1680-1740.r8`, 112 × 160 × 21 R8 voxels, 376,320 bytes, SHA-256 `43244b476c3e409dc1b32d2f55982b4f3946c058063b4d187c617b8243ef3a2d`. The adjacent generated JSON manifest records dimensions, spacing, crop, coordinate mapping, per-source checksums, and limitations.

The DEBUG loader verifies both byte count and this SHA-256 before creating the Metal texture. A missing, truncated, or same-size substituted asset fails visibly instead of rendering under the NLM label. Release companion builds exclude the renderer sources and derived volume resources.

Raw PNG/GE files, DICOM, identifiers, download trees, caches, and logs are not committed.

## Coordinate and safety limits

The texture maps into `GenericForearmCoordinateRoot`: texture +X → forearm +X; texture +Y → forearm -Z; increasing slice index → illustrative proximal-to-distal forearm +Y. This is an explicit compatibility transform, not participant registration.

The source CT field of view truncates part of the lateral forearm surface. A/P and R/L are not asserted. The renderer is an educational reference VRT, not diagnostic, not wearer-specific, and not physical AVP verification.
