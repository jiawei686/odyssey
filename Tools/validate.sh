#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT="$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj"
BUILD_ROOT="$PROJECT_DIR/.build"
mkdir -p "$BUILD_ROOT"

echo "[1/11] Checking mixed-reality, gaze, and sectional-imaging invariants"
rg -q 'ImmersionStyle = \.mixed' "$PROJECT_DIR/UpperLimbPOC/UpperLimbPOCApp.swift"
if rg -q '\.full' "$PROJECT_DIR/UpperLimbPOC/UpperLimbPOCApp.swift"; then
    echo "Full-immersion configuration detected; mixed reality is required." >&2
    exit 1
fi
rg -q 'sectionVisible' "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift"
rg -q 'normalizedSlicePosition' "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift"
rg -q 'tintID' "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift" "$PROJECT_DIR/Tools/SnapshotCompatibilityCheck.swift"
rg -q 'ReferenceSectionRoot' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -Fq 'referenceForearmLength * Float(overlay.normalizedSlicePosition)' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"

echo "[2/11] Checking reference CT assets and disclosure"
SLICE_COUNT="$(find "$PROJECT_DIR/UpperLimbPOC/ReferenceSlices" -type f -name 'reference-forearm-*.png' | wc -l | tr -d ' ')"
test "$SLICE_COUNT" = "5"
rg -q 'reference-forearm-01.png' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'not patient-specific' "$PROJECT_DIR/README.md" "$PROJECT_DIR/UpperLimbPOC/ReferenceSlices/README.md"
rg -q 'orientation and laterality are illustrative' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'TrackingStatus' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift" "$PROJECT_DIR/UpperLimbPOC/UpperLimbPOCApp.swift"
rg -q 'Return to anatomy library' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'sectionSourceStatus' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift" "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -q 'AnatomyBoneIcon' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'ManipulationComponent' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -q 'configureBoneHitTargets' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -q '!overlay.locked' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -q 'focusBone' "$PROJECT_DIR/UpperLimbPOC/OverlayState.swift" "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -q 'sectionLevelBar' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'Elbow to wrist section level' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'Gaze-targeted interaction' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'AccessibilityComponent' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -q 'AccessibilityEvents.Activate' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -q 'horizontalSizeClass' "$PROJECT_DIR/UpperLimbPOC/CompanionContentView.swift"
rg -q 'Reset placement' "$PROJECT_DIR/UpperLimbPOC/CompanionContentView.swift"
rg -q 'Bone opacity' "$PROJECT_DIR/UpperLimbPOC/CompanionContentView.swift"
rg -q 'Decrease bone opacity' "$PROJECT_DIR/UpperLimbPOC/CompanionContentView.swift"
rg -q 'overlay.resetPlacement()' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -Fq 'onReceive(peer.$lastSnapshot' "$PROJECT_DIR/UpperLimbPOC/CompanionContentView.swift"
if rg -q 'onChange\(of: peer\.isConnected\)' "$PROJECT_DIR/UpperLimbPOC/CompanionContentView.swift"; then
    echo "Companion must not overwrite Vision state on initial connection." >&2
    exit 1
fi
rg -q 'onChange\(of: peer\.isConnected\)' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'onChange\(of: peer\.isConnected\)' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -q 'scheduleReconnect' "$PROJECT_DIR/UpperLimbPOC/PeerSession.swift"
test -f "$PROJECT_DIR/PRODUCT_DEVELOPMENT_DOCUMENT.md"
test -f "$PROJECT_DIR/ML_ASSISTANT_ARCHITECTURE.md"
test -x "$PROJECT_DIR/Tools/simulator_smoke.sh"

echo "[3/11] Checking snapshot compatibility"
xcrun swiftc \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift" \
    "$PROJECT_DIR/Tools/SnapshotCompatibilityCheck.swift" \
    -o "$BUILD_ROOT/snapshot-compatibility-check"
"$BUILD_ROOT/snapshot-compatibility-check"

echo "[4/11] Checking overlay state behavior"
xcrun swiftc \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OverlayState.swift" \
    "$PROJECT_DIR/Tools/OverlayStateLogicCheck.swift" \
    -o "$BUILD_ROOT/overlay-state-logic-check"
"$BUILD_ROOT/overlay-state-logic-check"

echo "[5/11] Checking the physical-metrics evaluator"
xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/Tools/PhysicalAcceptanceMetrics.swift" \
    -o "$BUILD_ROOT/physical-acceptance-metrics"
"$BUILD_ROOT/physical-acceptance-metrics" --self-test

echo "[6/11] Building Vision Pro simulator target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -sdk xrsimulator \
    -derivedDataPath "$BUILD_ROOT/vision" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[7/11] Compiling Vision Pro physical-device target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -sdk xros \
    -derivedDataPath "$BUILD_ROOT/vision-device" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[8/11] Building iPad/iPhone companion simulator target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -sdk iphonesimulator \
    -derivedDataPath "$BUILD_ROOT/companion" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[9/11] Compiling iPad/iPhone physical-device target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -sdk iphoneos \
    -derivedDataPath "$BUILD_ROOT/companion-device" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[10/11] Analyzing Vision Pro target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -sdk xrsimulator \
    -derivedDataPath "$BUILD_ROOT/vision" \
    CODE_SIGNING_ALLOWED=NO \
    analyze

echo "[11/11] Analyzing iPad/iPhone companion target"
xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -sdk iphonesimulator \
    -derivedDataPath "$BUILD_ROOT/companion" \
    CODE_SIGNING_ALLOWED=NO \
    analyze

VISION_APP="$BUILD_ROOT/vision/Build/Products/Debug-xrsimulator/UpperLimbPOC.app"
test -f "$VISION_APP/reference-forearm-01.png"
test -f "$VISION_APP/reference-forearm-05.png"

echo "Validation passed: mixed reality, gaze/accessibility invariants, state logic, metric evaluator, five reference slices, all builds, and static analysis."
