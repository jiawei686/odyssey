#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT="$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj"
BUILD_ROOT="$PROJECT_DIR/.build"
mkdir -p "$BUILD_ROOT"

run_xcode_stage() {
    local stage_log="$1"
    shift
    if ! xcodebuild "$@" 2>&1 | tee "$stage_log"; then
        echo "Xcode stage failed; see $stage_log" >&2
        exit 1
    fi
    if rg -q '(^|[[:space:]])error:' "$stage_log"; then
        echo "Xcode emitted an error despite a zero exit status; see $stage_log" >&2
        exit 1
    fi
}

echo "[1/12] Checking mixed-reality, gaze, and sectional-imaging invariants"
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

echo "[2/12] Checking reference CT assets and disclosure"
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
rg -q 'NSHandsTrackingUsageDescription' "$PROJECT_DIR/UpperLimbPOC/InfoVision.plist"
rg -q 'HandTrackingProvider' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'IndexFingerRigRoot' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -q 'indexFingerKnuckle' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift" "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'indexFingerIntermediateBase' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift" "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'indexFingerIntermediateTip' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift" "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'handTrackingGeneration' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift" "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'INDEX FINGER STALE' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift" "$PROJECT_DIR/PRODUCT_DEVELOPMENT_DOCUMENT.md"
rg -q 'FR-23' "$PROJECT_DIR/PRODUCT_DEVELOPMENT_DOCUMENT.md"
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

echo "[3/12] Checking snapshot compatibility"
xcrun swiftc \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift" \
    "$PROJECT_DIR/Tools/SnapshotCompatibilityCheck.swift" \
    -o "$BUILD_ROOT/snapshot-compatibility-check"
"$BUILD_ROOT/snapshot-compatibility-check"

echo "[4/12] Checking overlay state behavior"
xcrun swiftc \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OverlayState.swift" \
    "$PROJECT_DIR/Tools/OverlayStateLogicCheck.swift" \
    -o "$BUILD_ROOT/overlay-state-logic-check"
"$BUILD_ROOT/overlay-state-logic-check"

echo "[5/12] Checking index-finger calibration and reacquisition"
xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/IndexFingerKinematics.swift" \
    "$PROJECT_DIR/Tools/IndexFingerKinematicsCheck.swift" \
    -o "$BUILD_ROOT/index-finger-kinematics-check"
"$BUILD_ROOT/index-finger-kinematics-check"

echo "[6/12] Checking the physical-metrics evaluator"
xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/Tools/PhysicalAcceptanceMetrics.swift" \
    -o "$BUILD_ROOT/physical-acceptance-metrics"
"$BUILD_ROOT/physical-acceptance-metrics" --self-test

echo "[7/12] Clean-building Vision Pro simulator target"
run_xcode_stage "$BUILD_ROOT/vision-build.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -sdk xrsimulator \
    -derivedDataPath "$BUILD_ROOT/vision" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

echo "[8/12] Clean-compiling Vision Pro physical-device target"
run_xcode_stage "$BUILD_ROOT/vision-device-build.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -sdk xros \
    -derivedDataPath "$BUILD_ROOT/vision-device" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

echo "[9/12] Clean-building iPad/iPhone companion simulator target"
run_xcode_stage "$BUILD_ROOT/companion-build.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -sdk iphonesimulator \
    -derivedDataPath "$BUILD_ROOT/companion" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

echo "[10/12] Clean-compiling iPad/iPhone physical-device target"
run_xcode_stage "$BUILD_ROOT/companion-device-build.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -sdk iphoneos \
    -derivedDataPath "$BUILD_ROOT/companion-device" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

echo "[11/12] Clean-analyzing Vision Pro target"
run_xcode_stage "$BUILD_ROOT/vision-analyze.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -sdk xrsimulator \
    -derivedDataPath "$BUILD_ROOT/vision" \
    CODE_SIGNING_ALLOWED=NO \
    clean analyze

echo "[12/12] Clean-analyzing iPad/iPhone companion target"
run_xcode_stage "$BUILD_ROOT/companion-analyze.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -sdk iphonesimulator \
    -derivedDataPath "$BUILD_ROOT/companion" \
    CODE_SIGNING_ALLOWED=NO \
    clean analyze

VISION_APP="$BUILD_ROOT/vision/Build/Products/Debug-xrsimulator/UpperLimbPOC.app"
test -f "$VISION_APP/reference-forearm-01.png"
test -f "$VISION_APP/reference-forearm-05.png"

echo "Validation passed: mixed reality, gaze/accessibility invariants, state and index-finger kinematics logic, metric evaluator, five reference slices, clean builds, and static analysis."
