# CT forearm volume-rendering spike

Status: DEBUG-only research spike; feature flag off by default; physical AVP not verified.

> NLM Visible Human reference anatomy — not wearer-specific imaging.

## Route and question

This branch tests true direct volume rendering, not a mesh fallback: can a compact, coherent public donor/cadaver reference CT subvolume render continuously from soft-tissue surface emphasis to bone emphasis in the iPad simulator while preserving an explicit forearm-local pose contract for later RealityKit use?

The standalone preview is entered only with `--ct-forearm-vrt-preview`. In Xcode, select the shared `UpperLimbCompanion-CT-Lab` scheme to supply that argument without using Terminal. Normal companion and Vision Pro flows are unchanged.

## Asset

`UpperLimbPOC/CTVolume/visible-human-male-forearm-1680-1740.r8` is a 112 × 160 × 21 R8 texture (376,320 bytes) derived from the NLM Visible Human Male normalCT PNGs at the 21 available 3 mm locations from 1680 through 1740. Source files and checksums, processing, public-domain status, and limitations are in `UpperLimbPOC/CTVolume/PROVENANCE.md` and the adjacent generated JSON manifest.

The raw PNG/GE inputs are not committed. No DICOM, identifiers, wearer pixels, caches, or generated evidence logs belong in the repository.

## Implementation

- `CTForearmVolumeShaders.metal` performs front-to-back ray marching over a trilinearly sampled `texture3d<r8Unorm>`.
- `Surface preset` sets Reveal Anatomy to 0; `Bone preset` sets it to 1; the slider exposes every continuous value in between.
- Transfer-function interpolation suppresses soft tissue as bone opacity increases; it does not claim formal tissue segmentation.
- `CTVisibleSurfaceDepthProviding` exposes the first accumulated-visible surface along a volume-local ray and maps the hit into `GenericForearmCoordinateRoot` metres.
- `volumeToForearmLocal` is compatible with a future RealityKit entity transform. This branch does not attach the volume to a wearer or claim registration.
- Load failure is visible and the standalone preview offers Reload. No clinical-looking synthetic fallback replaces missing CT data.

## Rebuild

Download only the 21 source PNGs listed in `PROVENANCE.md` to a temporary directory, verify their SHA-256 values, then run:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/odyssey-clang-module-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/odyssey-swift-module-cache \
xcrun swift Tools/build_ct_forearm_volume.swift \
  /path/to/temporary/source-pngs UpperLimbPOC/CTVolume
```

The expected asset SHA-256 is `43244b476c3e409dc1b32d2f55982b4f3946c058063b4d187c617b8243ef3a2d`.

## Verification

Run the repository validator, then capture simulator evidence:

```bash
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer ./Tools/validate.sh
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer \
  ./Tools/ct_vrt_simulator_evidence.sh <ipad-udid> /private/tmp/ct-vrt-evidence
```

The evidence script captures Surface and Bone preset screenshots plus measured simulator renderer-setup/load/upload time, exponentially smoothed command-buffer completion wall time, and frame sample count. The logical R8 payload and peak two-copy payload are inferred from the verified asset size; steady state retains one texture plus unmeasured driver/view allocations. Completion latency is not presented as frame rate, and simulator timing is not physical AVP GPU timing.

### Recorded simulator evidence

On the iPad Pro 11-inch (M5) iPadOS 27 simulator, the Surface and Bone captures
were visibly distinct. The two launches measured renderer setup/load/upload at
433.1 ms and 2.7 ms, and exponentially smoothed command-completion wall time at
2.9 ms and 4.5 ms. The logical texture payload is inferred from the reviewed
asset as 376,320 bytes; the 752,640-byte two-copy peak is also inferred. Metal
driver, view, and whole-process allocations were not measured.

Evidence is kept outside the repository under `/private/tmp/odyssey-ct-vrt-evidence`.
The Surface screenshot SHA-256 is
`d1c34fbc37c525cc1131f8be3db5b47e8aaa9397abca546424ab7a223bb0a0b7`;
the Bone screenshot SHA-256 is
`e2c9cdd6ac8ebcef07ac34a6d31fd1bf2fb35ca90fdb76fdb8f8349591fdd468`.

The CT asset/sampler checker is compiled with complete strict concurrency and
warnings as errors. A separate whole-companion strict-concurrency probe reaches
an existing frontend-owned non-Sendable static action fixture before CT code;
the repository's required warnings-as-errors builds and both analyzers are green.

## Limitations and physical gate

The NLM source field of view truncates part of the lateral forearm. The reference is one cadaver and is cross-subject. A/P and R/L are illustrative. Threshold transfer functions are not tissue segmentation. Simulator evidence cannot verify physical AVP performance, comfort, world pose, annotation attachment, tracking, occlusion, or registration. Those remain DEVICE-PENDING and require Marcel’s physical acceptance; this spike must not be presented as physical AVP verification.
