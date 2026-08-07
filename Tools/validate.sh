#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT="$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj"
BUILD_ROOT="$PROJECT_DIR/.build"
mkdir -p "$BUILD_ROOT"

echo "[1/9] Checking mixed-reality and sectional-imaging invariants"
rg -q 'ImmersionStyle = \.mixed' "$PROJECT_DIR/UpperLimbPOC/UpperLimbPOCApp.swift"
if rg -q '\.full' "$PROJECT_DIR/UpperLimbPOC/UpperLimbPOCApp.swift"; then
    echo "Full-immersion configuration detected; mixed reality is required." >&2
    exit 1
fi
rg -q 'sectionVisible' "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift"
rg -q 'normalizedSlicePosition' "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift"
rg -q 'ReferenceSectionRoot' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"

echo "[2/9] Checking reference CT assets and disclosure"
SLICE_COUNT="$(find "$PROJECT_DIR/UpperLimbPOC/ReferenceSlices" -type f -name 'reference-forearm-*.png' | wc -l | tr -d ' ')"
test "$SLICE_COUNT" = "5"
rg -q 'reference-forearm-01.png' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'not patient-specific' "$PROJECT_DIR/README.md" "$PROJECT_DIR/UpperLimbPOC/ReferenceSlices/README.md"
rg -q 'orientation and laterality are illustrative' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'TrackingStatus' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift" "$PROJECT_DIR/UpperLimbPOC/UpperLimbPOCApp.swift"
test -f "$PROJECT_DIR/PRODUCT_DEVELOPMENT_DOCUMENT.md"

echo "[3/9] Checking snapshot compatibility"
xcrun swiftc \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift" \
    "$PROJECT_DIR/Tools/SnapshotCompatibilityCheck.swift" \
    -o "$BUILD_ROOT/snapshot-compatibility-check"
"$BUILD_ROOT/snapshot-compatibility-check"

echo "[4/9] Building Vision Pro simulator target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -destination 'generic/platform=visionOS Simulator' \
    -derivedDataPath "$BUILD_ROOT/vision" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[5/9] Compiling Vision Pro physical-device target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -destination 'generic/platform=visionOS' \
    -derivedDataPath "$BUILD_ROOT/vision-device" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[6/9] Building iPad/iPhone companion simulator target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$BUILD_ROOT/companion" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[7/9] Compiling iPad/iPhone physical-device target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD_ROOT/companion-device" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[8/9] Analyzing Vision Pro target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -destination 'generic/platform=visionOS Simulator' \
    -derivedDataPath "$BUILD_ROOT/vision" \
    CODE_SIGNING_ALLOWED=NO \
    analyze

echo "[9/9] Analyzing iPad/iPhone companion target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$BUILD_ROOT/companion" \
    CODE_SIGNING_ALLOWED=NO \
    analyze

VISION_APP="$BUILD_ROOT/vision/Build/Products/Debug-xrsimulator/UpperLimbPOC.app"
test -f "$VISION_APP/reference-forearm-01.png"
test -f "$VISION_APP/reference-forearm-05.png"

echo "Validation passed: mixed reality, snapshot compatibility, five reference slices, all builds, and static analysis."
