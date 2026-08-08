#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$PROJECT_DIR/.dependencies/opencv-4.13.0"
BUILD_DIR="$PROJECT_DIR/.dependencies/opencv-4.13.0-build"
FRAMEWORK_DIR="$PROJECT_DIR/Vendor/OpenCV"
MODEL_DIR="$PROJECT_DIR/UpperLimbPOC/BodyScannerModels"
PATCH_FILE="$PROJECT_DIR/ThirdParty/BodyScanner/opencv-xcode27-arm64-fp16.patch"
OPENCV_COMMIT="fe38fc608f6acb8b68953438a62305d8318f4fcd"
ZOO_COMMIT="47534e27c9851bb1128ccc0102f1145e27f23f98"

mkdir -p "$PROJECT_DIR/.dependencies" "$FRAMEWORK_DIR" "$MODEL_DIR"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    git clone --depth 1 --branch 4.13.0 https://github.com/opencv/opencv.git "$SOURCE_DIR"
fi

actual_commit="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
if [[ "$actual_commit" != "$OPENCV_COMMIT" ]]; then
    echo "OpenCV source mismatch: $actual_commit" >&2
    exit 1
fi

if git -C "$SOURCE_DIR" apply --check "$PATCH_FILE" 2>/dev/null; then
    git -C "$SOURCE_DIR" apply "$PATCH_FILE"
elif ! git -C "$SOURCE_DIR" apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
    echo "OpenCV Xcode 27 patch does not apply cleanly" >&2
    exit 1
fi

export IPHONEOS_DEPLOYMENT_TARGET=18.0
python3 "$SOURCE_DIR/platforms/apple/build_xcframework.py" \
    --out "$BUILD_DIR" \
    --iphoneos_archs arm64 \
    --iphonesimulator_archs arm64,x86_64 \
    --build_only_specified_archs \
    --without objc

rm -rf "$FRAMEWORK_DIR/opencv2.xcframework"
cp -R "$BUILD_DIR/opencv2.xcframework" "$FRAMEWORK_DIR/opencv2.xcframework"

download_verified() {
    local url="$1"
    local destination="$2"
    local expected="$3"
    local temporary="${destination}.partial"
    curl -L --fail --silent --show-error "$url" -o "$temporary"
    local actual
    actual="$(shasum -a 256 "$temporary" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        rm -f "$temporary"
        echo "Checksum mismatch for $destination" >&2
        return 1
    fi
    mv "$temporary" "$destination"
}

zoo_root="https://github.com/opencv/opencv_zoo/raw/$ZOO_COMMIT/models"
download_verified "$zoo_root/person_detection_mediapipe/person_detection_mediapipe_2023mar.onnx" "$MODEL_DIR/person_detection_mediapipe_2023mar.onnx" "47fd5599d6fa17608f03e0eb0ae230baa6e597d7e8a2c8199fe00abea55a701f"
download_verified "$zoo_root/pose_estimation_mediapipe/pose_estimation_mediapipe_2023mar.onnx" "$MODEL_DIR/pose_estimation_mediapipe_2023mar.onnx" "9d89c599319a18fb7d2e28451a883476164543182bafca5f09eb2cf767ed2f3f"
download_verified "$zoo_root/palm_detection_mediapipe/palm_detection_mediapipe_2023feb.onnx" "$MODEL_DIR/palm_detection_mediapipe_2023feb.onnx" "78ff51c38496b7fc8b8ebdb6cc8c1abb02fa6c38427c6848254cdaba57fcce7c"
download_verified "$zoo_root/handpose_estimation_mediapipe/handpose_estimation_mediapipe_2023feb.onnx" "$MODEL_DIR/handpose_estimation_mediapipe_2023feb.onnx" "db0898ae717b76b075d9bf563af315b29562e11f8df5027a1ef07b02bef6d81c"

(
    cd "$PROJECT_DIR"
    shasum -a 256 -c ThirdParty/BodyScanner/models.sha256
)

plutil -p "$FRAMEWORK_DIR/opencv2.xcframework/Info.plist"
