# Body Scanner Dependencies

The iPhone scanner pins OpenCV tag `4.13.0` at commit
`fe38fc608f6acb8b68953438a62305d8318f4fcd` and OpenCV Zoo commit
`47534e27c9851bb1128ccc0102f1145e27f23f98`.

Run `Tools/bootstrap_body_scanner_dependencies.sh` with Xcode 27 selected.
It builds an uncommitted `Vendor/OpenCV/opencv2.xcframework`, downloads the
four uncommitted ONNX models, and verifies `models.sha256`.

`opencv-xcode27-arm64-fp16.patch` is intentionally narrow. It keeps arm64 NEON
as the baseline and sends FP16 kernels through OpenCV's `NEON_FP16` dispatch,
fixing Xcode 27's `vfmaq_f16 requires target feature fullfp16` failure without
changing the x86_64 simulator baseline. The build excludes OpenCV's generated
Objective-C wrapper because this project owns a narrower Objective-C++ bridge.

OpenCV and the four pinned OpenCV Zoo model directories are Apache-2.0 licensed.
The verbatim notices are retained as `LICENSE-OpenCV.txt` and
`LICENSE-OpenCV-Zoo.txt`. No generated framework or model binary is committed.
