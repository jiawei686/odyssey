#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT="$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj"
BUILD_ROOT="$PROJECT_DIR/.build"
mkdir -p "$BUILD_ROOT"

OPENCV_XCFRAMEWORK="$PROJECT_DIR/Vendor/OpenCV/opencv2.xcframework"
test -d "$OPENCV_XCFRAMEWORK" || {
    echo "Missing OpenCV XCFramework; run Tools/bootstrap_body_scanner_dependencies.sh" >&2
    exit 1
}
(
    cd "$PROJECT_DIR"
    shasum -a 256 -c ThirdParty/BodyScanner/models.sha256
)

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

echo "[1/14] Checking mixed-reality, gaze, and sectional-imaging invariants"
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

echo "[2/14] Checking reference CT assets and disclosure"
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
rg -q 'AppleFoundationModelClient.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -Fq '#available(visionOS 26.0, *)' "$PROJECT_DIR/UpperLimbPOC/MedicalAssistant/AppleFoundationModelClient.swift"
rg -q 'SystemLanguageModel.default' "$PROJECT_DIR/UpperLimbPOC/MedicalAssistant/AppleFoundationModelClient.swift"
rg -q 'supportsLocale' "$PROJECT_DIR/UpperLimbPOC/MedicalAssistant/AppleFoundationModelClient.swift"
rg -q '\-\-assistant-on-device-smoke' "$PROJECT_DIR/UpperLimbPOC/MedicalAssistant/MedicalAssistantView.swift"
test -s "$PROJECT_DIR/UpperLimbPOC/MedicalAssistant/Resources/assistant-avatar.usdz"
test "$(shasum -a 256 "$PROJECT_DIR/UpperLimbPOC/MedicalAssistant/Resources/assistant-avatar.usdz" | awk '{print $1}')" = "8a33c0625ded7a555c25475f47b0fae4c67c67320d26d70bb775ae38b8d2bd96"
rg -q 'AssistantAvatarView.swift in Sources' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'AssistantVoiceController.swift in Sources' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'assistant-avatar.usdz in Resources' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
plutil -extract NSMicrophoneUsageDescription raw "$PROJECT_DIR/UpperLimbPOC/InfoVision.plist" >/dev/null
plutil -extract NSSpeechRecognitionUsageDescription raw "$PROJECT_DIR/UpperLimbPOC/InfoVision.plist" >/dev/null
test "$(plutil -extract UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes raw "$PROJECT_DIR/UpperLimbPOC/InfoVision.plist")" = true
rg -q 'HandTrackingProvider' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'func startHandJointProbe' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'HandSkeleton.JointName.allCases' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'JointProbeAccumulator' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'func beginProbeMeasurement' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/JointProbeView.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/JointProbeImmersiveView.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/AVPForearmOverlayPose.swift"
rg -Fq 'WindowGroup(id: "JointProbe")' "$PROJECT_DIR/UpperLimbPOC/UpperLimbPOCApp.swift"
rg -Fq 'ImmersiveSpace(id: "JointProbeSpace")' "$PROJECT_DIR/UpperLimbPOC/UpperLimbPOCApp.swift"
rg -Fq 'Wearer-only educational overlay' "$PROJECT_DIR/UpperLimbPOC/JointProbeView.swift"
rg -Fq 'not a validated anatomical registration' "$PROJECT_DIR/UpperLimbPOC/JointProbeView.swift"
rg -q 'JointProbeView.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'JointProbeImmersiveView.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'JointProbeMetrics.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'JointProbeRoute.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'AVPForearmOverlayPose.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q '\.forearmArm' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift" "$PROJECT_DIR/UpperLimbPOC/JointProbeImmersiveView.swift"
rg -q '\.forearmWrist' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift" "$PROJECT_DIR/UpperLimbPOC/JointProbeImmersiveView.swift"
rg -Fq 'Open & detect arm' "$PROJECT_DIR/UpperLimbPOC/JointProbeView.swift"
rg -Fq 'Show 3D bone overlay' "$PROJECT_DIR/UpperLimbPOC/JointProbeView.swift"
rg -Fq 'guard await openProbeSpace() else { return }' "$PROJECT_DIR/UpperLimbPOC/JointProbeView.swift"
rg -Fq 'Open wearer arm overlay' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'AVPTrackedBoneSegmentTransformResolver' "$PROJECT_DIR/UpperLimbPOC/AVPForearmOverlayPose.swift" "$PROJECT_DIR/UpperLimbPOC/JointProbeImmersiveView.swift"
rg -Fq 'MeshResource.generateCylinder(height: 1, radius: 1)' "$PROJECT_DIR/UpperLimbPOC/JointProbeImmersiveView.swift"
rg -q '\.thumbTip|\.indexFingerTip|\.middleFingerTip|\.ringFingerTip|\.littleFingerTip' "$PROJECT_DIR/UpperLimbPOC/JointProbeImmersiveView.swift"
rg -q 'probeBoneVisible' "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift" "$PROJECT_DIR/UpperLimbPOC/JointProbeView.swift" "$PROJECT_DIR/UpperLimbPOC/JointProbeImmersiveView.swift"
if rg -Fq 'Entity(named: "hand-to-elbow-overlay")' "$PROJECT_DIR/UpperLimbPOC/JointProbeImmersiveView.swift"; then
    echo "AVP wearer tracking must not use the rigid hand-to-elbow asset." >&2
    exit 1
fi
if rg -q 'GenericForearmBody|GenericForearmSection|makeForearmOverlay' "$PROJECT_DIR/UpperLimbPOC/JointProbeImmersiveView.swift"; then
    echo "AVP probe must not reintroduce a generated forearm body or section surface." >&2
    exit 1
fi
rg -q 'jointProbeRoute.present' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'navigationDestination' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift"
rg -q 'IndexFingerRigRoot' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift"
rg -q 'indexFingerKnuckle' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift" "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'indexFingerIntermediateBase' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift" "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'indexFingerIntermediateTip' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift" "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'handTrackingGeneration' "$PROJECT_DIR/UpperLimbPOC/ImmersiveView.swift" "$PROJECT_DIR/UpperLimbPOC/LandmarkTrackingService.swift"
rg -q 'INDEX FINGER STALE' "$PROJECT_DIR/UpperLimbPOC/ContentView.swift" "$PROJECT_DIR/PRODUCT_DEVELOPMENT_DOCUMENT.md"
rg -q 'FR-23' "$PROJECT_DIR/PRODUCT_DEVELOPMENT_DOCUMENT.md"
rg -q 'FR-24' "$PROJECT_DIR/PRODUCT_DEVELOPMENT_DOCUMENT.md"
rg -q 'HybridLandmarkRegistration.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'sceneReconstructionSurface' "$PROJECT_DIR/UpperLimbPOC/HybridLandmarkRegistration.swift"
rg -Fq 'Scene reconstruction (LiDAR-derived surface mesh) does not identify named body joints' "$PROJECT_DIR/UpperLimbPOC/OverlayState.swift"
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
test -f "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceContract.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceWireCodec.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceSyncEngine.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceSession.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/AVPClinicianGuidanceSpatialMapper.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationWireCodec.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/AnatomicalSurfaceProjection.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/GenericAnatomicalForearmPreview.swift"
test -f "$PROJECT_DIR/docs/ANATOMICAL_LAYER_ANNOTATION.md"
test -f "$PROJECT_DIR/docs/CLINICIAN_GUIDANCE_CONTRACT.md"
test -f "$PROJECT_DIR/docs/CLAUDE_CODEX_WORKFLOW.md"
rg -q 'ClinicianGuidanceProtocol.staleAfterSeconds' "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceContract.swift" "$PROJECT_DIR/Tools/ClinicianGuidanceContractCheck.swift"
rg -q 'ClinicianGuidanceContract.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'ClinicianConnectionStatusView.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'ClinicianForearmCanvas.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'ClinicianControlPanel.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'ClinicianGuidancePreviewSupport.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'ClinicianGuidanceSyncEngine.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'ClinicianGuidanceSession.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'AVPClinicianGuidanceSpatialMapper.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'AnatomicalAnnotationContract.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -q 'AnatomicalSurfaceProjection.swift' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -Fq 'static let isEnabledByDefault = false' "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift"
rg -Fq 'Illustrative anatomical model — not patient-specific imaging.' \
    "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/GenericAnatomicalForearmPreview.swift" \
    "$PROJECT_DIR/docs/ANATOMICAL_LAYER_ANNOTATION.md"
rg -q 'case skin' "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift"
rg -q 'case subcutaneousFat' "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift"
rg -q 'case muscle' "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift"
rg -q 'case bone' "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift"
rg -q 'case floating' "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift"
if rg -qi 'freehand' \
    "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/AnatomicalSurfaceProjection.swift" \
    "$PROJECT_DIR/UpperLimbPOC/GenericAnatomicalForearmPreview.swift"; then
    echo "Anatomical-layer foundation must remain point/circle only." >&2
    exit 1
fi
CT_VOLUME_DIR="$PROJECT_DIR/UpperLimbPOC/CTVolume"
CT_VOLUME_ASSET="$CT_VOLUME_DIR/visible-human-male-forearm-1680-1740.r8"
CT_VOLUME_MANIFEST="$CT_VOLUME_DIR/visible-human-male-forearm-1680-1740.json"
test -f "$CT_VOLUME_ASSET"
test -f "$CT_VOLUME_MANIFEST"
test -f "$CT_VOLUME_DIR/PROVENANCE.md"
test -f "$PROJECT_DIR/Tools/build_ct_forearm_volume.swift"
test -x "$PROJECT_DIR/Tools/ct_vrt_simulator_evidence.sh"
test -f "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbCompanion-CT-Lab.xcscheme"
test "$(wc -c < "$CT_VOLUME_ASSET" | tr -d ' ')" = "376320"
test "$(shasum -a 256 "$CT_VOLUME_ASSET" | awk '{print $1}')" = \
    "43244b476c3e409dc1b32d2f55982b4f3946c058063b4d187c617b8243ef3a2d"
rg -Fq 'static let launchArgument = "--ct-forearm-vrt-preview"' "$CT_VOLUME_DIR/CTForearmVRTPreview.swift"
rg -Fq 'NLM Visible Human reference anatomy — not wearer-specific imaging.' "$CT_VOLUME_DIR/CTForearmVRTPreview.swift"
rg -Fq 'CTVisibleSurfaceDepthProviding' "$CT_VOLUME_DIR/CTForearmVolume.swift"
rg -Fq 'invalidSHA256' "$CT_VOLUME_DIR/CTForearmVolume.swift"
rg -Fq 'texture3d<float, access::sample>' "$CT_VOLUME_DIR/CTForearmVolumeShaders.metal"
rg -Fq 'ctVolumeFragment' "$CT_VOLUME_DIR/CTForearmVolumeShaders.metal"
rg -Fq 'Reveal Anatomy' "$CT_VOLUME_DIR/CTForearmVRTPreview.swift"
rg -Fq 'Surface preset' "$CT_VOLUME_DIR/CTForearmVRTPreview.swift"
rg -Fq 'Bone preset' "$CT_VOLUME_DIR/CTForearmVRTPreview.swift"
rg -Fq 'static let isEnabledByDefault = false' "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift"
CLINICAL_TWIN_DIR="$PROJECT_DIR/UpperLimbPOC/ClinicalTwin"
test -f "$CLINICAL_TWIN_DIR/ClinicalTwinPose.swift"
test -f "$CLINICAL_TWIN_DIR/CTForearmTwinGeometry.swift"
test -f "$CLINICAL_TWIN_DIR/ClinicalTwinLabState.swift"
test -f "$CLINICAL_TWIN_DIR/ClinicalTwinRealityKit.swift"
test -f "$CLINICAL_TWIN_DIR/ClinicalTwinImmersiveView.swift"
test -f "$CLINICAL_TWIN_DIR/ClinicalTwinView.swift"
test -f "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbPOC.xcscheme"
test -f "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbPOC-Clinical-Twin-Lab.xcscheme"
rg -Fq 'static let launchArgument = "--odyssey-clinical-twin"' "$CLINICAL_TWIN_DIR/ClinicalTwinLabState.swift"
rg -Fq 'case anatomyToolBlenderUSDZ' "$CLINICAL_TWIN_DIR/ClinicalTwinPose.swift"
rg -Fq 'Odyssey · Right Forearm' "$CLINICAL_TWIN_DIR/ClinicalTwinView.swift"
rg -Fq 'Illustrative anatomical model — not patient-specific imaging.' "$CLINICAL_TWIN_DIR/ClinicalTwinView.swift"
rg -Fq 'rightHandJointTransforms' "$CLINICAL_TWIN_DIR/ClinicalTwinImmersiveView.swift"
rg -Fq 'rightForearmResolution' "$CLINICAL_TWIN_DIR/ClinicalTwinImmersiveView.swift"
rg -Fq 'Tracking dots and procedural cylinders remain Diagnostics only' "$CLINICAL_TWIN_DIR/ClinicalTwinView.swift"
rg -Fq 'OnArmAnatomyRealityKitFactory.loadRoot()' "$CLINICAL_TWIN_DIR/ClinicalTwinRealityKit.swift"
rg -Fq 'showFullAsset: true' "$CLINICAL_TWIN_DIR/ClinicalTwinRealityKit.swift"
rg -Fq 'loaded.root.name = rootName' "$CLINICAL_TWIN_DIR/ClinicalTwinRealityKit.swift"
if rg -q 'assetRootName|let root = Entity\(\)|root\.addChild\(loaded\.root\)' \
    "$CLINICAL_TWIN_DIR/ClinicalTwinRealityKit.swift"; then
    echo "Clinical twin must expose exactly one direct geometry-bearing scene root without a wrapper." >&2
    exit 1
fi
test "$(rg -c 'loaded\.root\.name = rootName' "$CLINICAL_TWIN_DIR/ClinicalTwinRealityKit.swift")" = "1"
rg -Fq 'static let referenceForearmLengthMetres: Float = 0.2625' "$CLINICAL_TWIN_DIR/ClinicalTwinPose.swift"
rg -Fq 'localLongAxis = SIMD3<Float>(0, 0, -1)' "$CLINICAL_TWIN_DIR/ClinicalTwinPose.swift"
rg -Fq 'await labState.startRightForearmTracking(using: tracking)' "$CLINICAL_TWIN_DIR/ClinicalTwinImmersiveView.swift"
rg -Fq 'SceneEvents.Update.self' "$CLINICAL_TWIN_DIR/ClinicalTwinImmersiveView.swift"
rg -Fq 'root.setTransformMatrix(sceneTransform.matrix, relativeTo: nil)' "$CLINICAL_TWIN_DIR/ClinicalTwinImmersiveView.swift"
rg -Fq 'CLINICAL_TWIN_FRAME count=' "$CLINICAL_TWIN_DIR/ClinicalTwinImmersiveView.swift"
if rg -Fq 'loaded.root.transform =' "$CLINICAL_TWIN_DIR/ClinicalTwinRealityKit.swift"; then
    echo "Clinical twin must preserve the centred Blender -Z asset basis without a child pre-rotation." >&2
    exit 1
fi
rg -Fq 'Float(labState.revealAnatomy) * presentation.opacity' "$CLINICAL_TWIN_DIR/ClinicalTwinImmersiveView.swift"
if rg -q 'CTForearmVolumeData.load|CTForearmTwinGeometryBuilder.build|generateCylinder' \
    "$CLINICAL_TWIN_DIR/ClinicalTwinImmersiveView.swift" \
    "$CLINICAL_TWIN_DIR/ClinicalTwinRealityKit.swift"; then
    echo "Clinical twin must load the real Blender USDZ, not CT-derived or procedural fallback geometry." >&2
    exit 1
fi
ON_ARM_ANATOMY_DIR="$PROJECT_DIR/UpperLimbPOC/OnArmAnatomy"
for file in \
    OnArmAnatomyAssetContract.swift \
    OnArmAnatomyPose.swift \
    OnArmAnatomyRealityKit.swift \
    OnArmAnatomyLabState.swift \
    OnArmAnatomyImmersiveView.swift \
    OnArmAnatomyView.swift; do
    test -f "$ON_ARM_ANATOMY_DIR/$file"
done
test -f "$PROJECT_DIR/Tools/OnArmAnatomyAssetCheck.swift"
test -f "$PROJECT_DIR/Tools/OnArmAnatomyPoseCheck.swift"
test -f "$PROJECT_DIR/docs/AVP_ON_ARM_ANATOMY.md"
test -f "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbPOC-On-Arm-Anatomy-Lab.xcscheme"
rg -Fq 'static let launchArgument = "--avp-on-arm-anatomy"' "$ON_ARM_ANATOMY_DIR/OnArmAnatomyLabState.swift"
rg -Fq 'Entity(named: OnArmAnatomyAssetContract.assetName)' "$ON_ARM_ANATOMY_DIR/OnArmAnatomyRealityKit.swift"
rg -Fq 'static let radiusNodeName = "Radius_r"' "$ON_ARM_ANATOMY_DIR/OnArmAnatomyAssetContract.swift"
rg -Fq 'static let ulnaNodeName = "Ulna_r"' "$ON_ARM_ANATOMY_DIR/OnArmAnatomyAssetContract.swift"
rg -Fq 'rightForearmResolution' "$ON_ARM_ANATOMY_DIR/OnArmAnatomyImmersiveView.swift"
rg -Fq 'rightHandJointTransforms' "$ON_ARM_ANATOMY_DIR/OnArmAnatomyImmersiveView.swift"
rg -Fq 'Reference anatomy alignment — not patient-specific imaging.' "$ON_ARM_ANATOMY_DIR/OnArmAnatomyView.swift"
rg -Fq '.upperLimbVisibility(.visible)' "$PROJECT_DIR/UpperLimbPOC/UpperLimbPOCApp.swift"
rg -Fq '.upperLimbVisibility(.hidden)' "$PROJECT_DIR/UpperLimbPOC/UpperLimbPOCApp.swift"
rg -Fq 'OnArmAnatomyView.swift in Sources' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -Fq 'OnArmAnatomyView.swift,' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
if rg -q 'generateCylinder|generateSphere' "$ON_ARM_ANATOMY_DIR"; then
    echo "On-arm anatomy must load named USDZ meshes, not procedural diagnostic geometry." >&2
    exit 1
fi
if find "$PROJECT_DIR" -type f \( -iname '*.dcm' -o -iname '*.dicom' -o -iname '*.ima' \) -print -quit | rg -q .; then
    echo "Raw DICOM-like data must not be committed." >&2
    exit 1
fi
rg -q 'avpRenderedGuidanceState' "$PROJECT_DIR/UpperLimbPOC/JointProbeImmersiveView.swift"
test -f "$PROJECT_DIR/PRODUCT_DEVELOPMENT_DOCUMENT.md"
test -f "$PROJECT_DIR/ML_ASSISTANT_ARCHITECTURE.md"
test -f "$PROJECT_DIR/JOINT_CAPABILITY_PROBE.md"
rg -qi 'wearer hand' "$PROJECT_DIR/JOINT_CAPABILITY_PROBE.md"
rg -qi 'another person' "$PROJECT_DIR/JOINT_CAPABILITY_PROBE.md"
rg -qi 'enterprise main-camera' "$PROJECT_DIR/JOINT_CAPABILITY_PROBE.md"
rg -qi 'continuity' "$PROJECT_DIR/JOINT_CAPABILITY_PROBE.md"
rg -qi 'accuracy' "$PROJECT_DIR/JOINT_CAPABILITY_PROBE.md"
rg -qi 'kill criterion' "$PROJECT_DIR/JOINT_CAPABILITY_PROBE.md"
test -x "$PROJECT_DIR/Tools/simulator_smoke.sh"
test -f "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionService.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/OdysseyIntegratedDemo.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/OdysseyIntegratedRoots.swift"
test -f "$PROJECT_DIR/UpperLimbPOC/PeerEndpointFailover.swift"
test -f "$PROJECT_DIR/Tools/PeerEndpointFailoverCheck.swift"
test -f "$PROJECT_DIR/docs/ODYSSEY_INTEGRATED_DEMO.md"
test -f "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbPOC-Odyssey-Integrated-Demo.xcscheme"
test -f "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbCompanion-Odyssey-Integrated-Demo.xcscheme"
rg -Fq 'static let launchArgument = "--odyssey-integrated-demo"' "$PROJECT_DIR/UpperLimbPOC/OdysseyIntegratedDemo.swift"
rg -Fq '#if ODYSSEY_INTEGRATED_DEMO' "$PROJECT_DIR/UpperLimbPOC/OdysseyIntegratedDemo.swift"
rg -Fq 'Odyssey Clinician Companion' "$PROJECT_DIR/UpperLimbPOC/PeerSession.swift"
rg -Fq 'isValidClinicianHandshake' "$PROJECT_DIR/UpperLimbPOC/PeerSession.swift"
rg -Fq 'startNextDiscoveredEndpoint' "$PROJECT_DIR/UpperLimbPOC/PeerSession.swift"
rg -Fq 'Verifying clinician companion…' "$PROJECT_DIR/UpperLimbPOC/PeerSession.swift"
rg -Fq 'Connected to clinician companion' "$PROJECT_DIR/UpperLimbPOC/PeerSession.swift"
rg -Fq 'PeerEndpointFailover.swift in Sources' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
rg -Fq 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG ODYSSEY_INTEGRATED_DEMO $(inherited)";' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/project.pbxproj"
test "$(rg -o 'buildConfiguration="Debug-OdysseyIntegratedDemo"' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbPOC-Odyssey-Integrated-Demo.xcscheme" | wc -l | tr -d ' ')" = "3"
test "$(rg -o 'buildConfiguration="Debug-OdysseyIntegratedDemo"' "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbCompanion-Odyssey-Integrated-Demo.xcscheme" | wc -l | tr -d ' ')" = "3"
if rg -q 'Debug-OdysseyIntegratedDemo|ODYSSEY_INTEGRATED_DEMO' \
    "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbPOC.xcscheme" \
    "$PROJECT_DIR/RadiographicAnatomyPOC.xcodeproj/xcshareddata/xcschemes/UpperLimbCompanion.xcscheme"; then
    echo "Stable schemes must not enable the Odyssey integrated-demo compilation condition." >&2
    exit 1
fi
rg -Fq 'case anatomyToolBlenderUSDZ' "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionContract.swift"
rg -Fq '? [.anatomyToolBlenderUSDZ]' "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionService.swift"
rg -Fq 'rendererRoute: .anatomyToolBlenderUSDZ' "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionService.swift"
rg -Fq 'wearerView: .unavailable' "$PROJECT_DIR/UpperLimbPOC/OdysseyIntegratedDemo.swift"

echo "[3/14] Checking snapshot compatibility"
xcrun swiftc \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift" \
    "$PROJECT_DIR/Tools/SnapshotCompatibilityCheck.swift" \
    -o "$BUILD_ROOT/snapshot-compatibility-check"
"$BUILD_ROOT/snapshot-compatibility-check"

echo "[4/14] Checking overlay state behavior"
xcrun swiftc \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OverlayState.swift" \
    "$PROJECT_DIR/Tools/OverlayStateLogicCheck.swift" \
    -o "$BUILD_ROOT/overlay-state-logic-check"
"$BUILD_ROOT/overlay-state-logic-check"

echo "[5/14] Checking hybrid landmark registration"
xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/HybridLandmarkRegistration.swift" \
    "$PROJECT_DIR/Tools/HybridLandmarkRegistrationCheck.swift" \
    -o "$BUILD_ROOT/hybrid-landmark-registration-check"
"$BUILD_ROOT/hybrid-landmark-registration-check"

echo "[5a/14] Checking upper-limb integration and scanner contracts"
xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbJointFrame.swift" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbPeerEnvelope.swift" \
    "$PROJECT_DIR/Tools/UpperLimbJointFrameCheck.swift" \
    -o "$BUILD_ROOT/upper-limb-joint-frame-check"
"$BUILD_ROOT/upper-limb-joint-frame-check"

xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceWireCodec.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionWireCodec.swift" \
    "$PROJECT_DIR/Tools/ClinicianGuidanceContractCheck.swift" \
    -o "$BUILD_ROOT/clinician-guidance-contract-check"
"$BUILD_ROOT/clinician-guidance-contract-check"

xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceSyncEngine.swift" \
    "$PROJECT_DIR/Tools/ClinicianGuidanceSyncCheck.swift" \
    -o "$BUILD_ROOT/clinician-guidance-sync-check"
"$BUILD_ROOT/clinician-guidance-sync-check"

xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/AVPForearmOverlayPose.swift" \
    "$PROJECT_DIR/UpperLimbPOC/AVPClinicianGuidanceSpatialMapper.swift" \
    "$PROJECT_DIR/Tools/ClinicianGuidanceSpatialCheck.swift" \
    -o "$BUILD_ROOT/clinician-guidance-spatial-check"
"$BUILD_ROOT/clinician-guidance-spatial-check"

xcrun swiftc \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceWireCodec.swift" \
    "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationWireCodec.swift" \
    "$PROJECT_DIR/Tools/AnatomicalAnnotationContractCheck.swift" \
    -o "$BUILD_ROOT/anatomical-annotation-contract-check"
"$BUILD_ROOT/anatomical-annotation-contract-check"

xcrun swiftc \
    -D DEBUG \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/AnatomicalSurfaceProjection.swift" \
    "$PROJECT_DIR/Tools/AnatomicalSurfaceProjectionCheck.swift" \
    -o "$BUILD_ROOT/anatomical-surface-projection-check"
"$BUILD_ROOT/anatomical-surface-projection-check"

xcrun swiftc \
    -D DEBUG \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/AnatomicalAnnotationContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/CTVolume/CTForearmVolume.swift" \
    "$PROJECT_DIR/Tools/CTForearmVolumeCheck.swift" \
    -o "$BUILD_ROOT/ct-forearm-volume-check"
"$BUILD_ROOT/ct-forearm-volume-check" "$PROJECT_DIR"

xcrun swiftc \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/OverlaySnapshot.swift" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbJointFrame.swift" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbPeerEnvelope.swift" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceWireCodec.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionWireCodec.swift" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbPeerWireCodec.swift" \
    "$PROJECT_DIR/Tools/UpperLimbPeerWireCheck.swift" \
    -o "$BUILD_ROOT/upper-limb-peer-wire-check"
"$BUILD_ROOT/upper-limb-peer-wire-check"

xcrun swiftc \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicianGuidanceWireCodec.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionWireCodec.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OdysseyClinicalSessionAdapter.swift" \
    "$PROJECT_DIR/Tools/OdysseyClinicalSessionContractCheck.swift" \
    -o "$BUILD_ROOT/odyssey-clinical-session-contract-check"
"$BUILD_ROOT/odyssey-clinical-session-contract-check"

xcrun swiftc \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/PeerEndpointFailover.swift" \
    "$PROJECT_DIR/Tools/PeerEndpointFailoverCheck.swift" \
    -o "$BUILD_ROOT/peer-endpoint-failover-check"
"$BUILD_ROOT/peer-endpoint-failover-check"

xcrun swiftc \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/OdysseyExperienceViewState.swift" \
    "$PROJECT_DIR/Tools/OdysseyIntegratedDemoCheck.swift" \
    -o "$BUILD_ROOT/odyssey-integrated-demo-check"
"$BUILD_ROOT/odyssey-integrated-demo-check"

xcrun swiftc \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbJointFrame.swift" \
    "$PROJECT_DIR/UpperLimbPOC/HybridLandmarkRegistration.swift" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbIntegration/SpatialJointBridge.swift" \
    "$PROJECT_DIR/Tools/UpperLimbSpatialBridgeCheck.swift" \
    -o "$BUILD_ROOT/upper-limb-spatial-bridge-check"
"$BUILD_ROOT/upper-limb-spatial-bridge-check"

xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbJointFrame.swift" \
    "$PROJECT_DIR/UpperLimbPOC/HybridLandmarkRegistration.swift" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbIntegration/SpatialJointBridge.swift" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbIntegration/UpperLimbIntegrationState.swift" \
    "$PROJECT_DIR/Tools/UpperLimbIntegrationStateCheck.swift" \
    -o "$BUILD_ROOT/upper-limb-integration-state-check"
"$BUILD_ROOT/upper-limb-integration-state-check"

xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/BodyScanner/UI/BodyScannerPresentation.swift" \
    "$PROJECT_DIR/Tools/BodyScannerUICheck.swift" \
    -o "$BUILD_ROOT/body-scanner-ui-check"
"$BUILD_ROOT/body-scanner-ui-check"

xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/BodyScanner/UI/BodyScannerPresentation.swift" \
    "$PROJECT_DIR/Tools/BodyScannerOrientationCheck.swift" \
    -o "$BUILD_ROOT/body-scanner-orientation-check"
"$BUILD_ROOT/body-scanner-orientation-check" "$PROJECT_DIR"

xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/UpperLimbJointFrame.swift" \
    "$PROJECT_DIR/UpperLimbPOC/BodyScanner/Inference/BodyScannerModelManifest.swift" \
    "$PROJECT_DIR/UpperLimbPOC/BodyScanner/Inference/BodyScannerResourceInspector.swift" \
    "$PROJECT_DIR/UpperLimbPOC/BodyScanner/Inference/BodyScannerUpperLimbPoseMapper.swift" \
    "$PROJECT_DIR/Tools/BodyScannerInferenceContractCheck.swift" \
    -o "$BUILD_ROOT/body-scanner-inference-contract-check"
"$BUILD_ROOT/body-scanner-inference-contract-check"

xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/Tools/OpenCVWrapperContractCheck.swift" \
    -o "$BUILD_ROOT/opencv-wrapper-contract-check"
"$BUILD_ROOT/opencv-wrapper-contract-check" "$PROJECT_DIR"

echo "[6/14] Checking AVP joint capability probe metrics"
xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/JointProbeMetrics.swift" \
    "$PROJECT_DIR/Tools/JointProbeMetricsCheck.swift" \
    -o "$BUILD_ROOT/joint-probe-metrics-check"
"$BUILD_ROOT/joint-probe-metrics-check"

xcrun swiftc \
    -warnings-as-errors \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/AVPForearmOverlayPose.swift" \
    "$PROJECT_DIR/Tools/AVPForearmOverlayPoseCheck.swift" \
    -o "$BUILD_ROOT/avp-forearm-overlay-pose-check"
"$BUILD_ROOT/avp-forearm-overlay-pose-check"

xcrun swiftc \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/AVPForearmOverlayPose.swift" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicalTwin/ClinicalTwinPose.swift" \
    "$PROJECT_DIR/Tools/ClinicalTwinPoseCheck.swift" \
    -o "$BUILD_ROOT/clinical-twin-pose-check"
"$BUILD_ROOT/clinical-twin-pose-check"

xcrun swiftc \
    -D DEBUG \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/AVPForearmOverlayPose.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OnArmAnatomy/OnArmAnatomyAssetContract.swift" \
    "$PROJECT_DIR/UpperLimbPOC/OnArmAnatomy/OnArmAnatomyPose.swift" \
    "$PROJECT_DIR/Tools/OnArmAnatomyPoseCheck.swift" \
    -o "$BUILD_ROOT/on-arm-anatomy-pose-check"
"$BUILD_ROOT/on-arm-anatomy-pose-check"

/usr/bin/usdchecker "$PROJECT_DIR/UpperLimbPOC/hand-to-elbow-overlay.usdz"
/usr/bin/usdcat \
    "$PROJECT_DIR/UpperLimbPOC/hand-to-elbow-overlay.usdz" \
    -o "$BUILD_ROOT/on-arm-anatomy.usda"
xcrun swiftc \
    -D DEBUG \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/OnArmAnatomy/OnArmAnatomyAssetContract.swift" \
    "$PROJECT_DIR/Tools/OnArmAnatomyAssetCheck.swift" \
    -o "$BUILD_ROOT/on-arm-anatomy-asset-check"
"$BUILD_ROOT/on-arm-anatomy-asset-check" \
    "$PROJECT_DIR/UpperLimbPOC/hand-to-elbow-overlay.usdz" \
    "$BUILD_ROOT/on-arm-anatomy.usda"

xcrun swiftc \
    -D DEBUG \
    -warnings-as-errors \
    -strict-concurrency=complete \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/CTVolume/CTForearmVolume.swift" \
    "$PROJECT_DIR/UpperLimbPOC/AVPForearmOverlayPose.swift" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicalTwin/ClinicalTwinPose.swift" \
    "$PROJECT_DIR/UpperLimbPOC/ClinicalTwin/CTForearmTwinGeometry.swift" \
    "$PROJECT_DIR/Tools/CTForearmTwinGeometryCheck.swift" \
    -o "$BUILD_ROOT/ct-forearm-twin-geometry-check"
"$BUILD_ROOT/ct-forearm-twin-geometry-check" "$PROJECT_DIR"

xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/JointProbeRoute.swift" \
    "$PROJECT_DIR/Tools/JointProbeRouteCheck.swift" \
    -o "$BUILD_ROOT/joint-probe-route-check"
"$BUILD_ROOT/joint-probe-route-check"

echo "[7/14] Checking index-finger calibration and reacquisition"
xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/IndexFingerKinematics.swift" \
    "$PROJECT_DIR/Tools/IndexFingerKinematicsCheck.swift" \
    -o "$BUILD_ROOT/index-finger-kinematics-check"
"$BUILD_ROOT/index-finger-kinematics-check"

echo "[8/14] Checking the physical-metrics evaluator"
xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/Tools/PhysicalAcceptanceMetrics.swift" \
    -o "$BUILD_ROOT/physical-acceptance-metrics"
"$BUILD_ROOT/physical-acceptance-metrics" --self-test

echo "[8a/14] Checking medical-assistant safety and retrieval contracts"
xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$BUILD_ROOT/swift-module-cache" \
    "$PROJECT_DIR/UpperLimbPOC/MedicalAssistant/MedicalAssistantModels.swift" \
    "$PROJECT_DIR/UpperLimbPOC/MedicalAssistant/MedicalKnowledgeRepository.swift" \
    "$PROJECT_DIR/UpperLimbPOC/MedicalAssistant/MedicalSafetyPolicy.swift" \
    "$PROJECT_DIR/Tools/MedicalAssistantContractCheck.swift" \
    -o "$BUILD_ROOT/medical-assistant-contract-check"
"$BUILD_ROOT/medical-assistant-contract-check" "$PROJECT_DIR"

echo "[9/14] Clean-building Vision Pro simulator target"
run_xcode_stage "$BUILD_ROOT/vision-build.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -sdk xrsimulator \
    -derivedDataPath "$BUILD_ROOT/vision" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

echo "[10/14] Clean-compiling Vision Pro physical-device target"
run_xcode_stage "$BUILD_ROOT/vision-device-build.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -sdk xros \
    -derivedDataPath "$BUILD_ROOT/vision-device" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

echo "[11/14] Clean-building iPad/iPhone companion simulator target"
run_xcode_stage "$BUILD_ROOT/companion-build.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -sdk iphonesimulator \
    -derivedDataPath "$BUILD_ROOT/companion" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

echo "[12/14] Clean-compiling iPad/iPhone physical-device target"
run_xcode_stage "$BUILD_ROOT/companion-device-build.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbCompanion \
    -configuration Debug \
    -sdk iphoneos \
    -derivedDataPath "$BUILD_ROOT/companion-device" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

echo "[13/14] Clean-analyzing Vision Pro target"
run_xcode_stage "$BUILD_ROOT/vision-analyze.log" \
    -quiet \
    -project "$PROJECT" \
    -scheme UpperLimbPOC \
    -configuration Debug \
    -sdk xrsimulator \
    -derivedDataPath "$BUILD_ROOT/vision" \
    CODE_SIGNING_ALLOWED=NO \
    clean analyze

echo "[14/14] Clean-analyzing iPad/iPhone companion target"
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
test -f "$VISION_APP/visible-human-male-forearm-1680-1740.r8"
test -f "$VISION_APP/visible-human-male-forearm-1680-1740.json"
test -f "$VISION_APP/assistant-avatar.usdz"
COMPANION_APP="$BUILD_ROOT/companion/Build/Products/Debug-iphonesimulator/UpperLimbCompanion.app"
test -f "$COMPANION_APP/visible-human-male-forearm-1680-1740.r8"
test -f "$COMPANION_APP/visible-human-male-forearm-1680-1740.json"
test ! -e "$COMPANION_APP/assistant-avatar.usdz"

echo "Validation passed: mixed reality, gaze/accessibility invariants, AVP self-forearm axis/stale state, named USDZ on-arm asset/pose checks, AnatomyTOOL Blender USDZ clinical-twin asset/pose checks, isolated CT-derived geometry checks, hybrid landmark registration and index-finger kinematics logic, CT VRT resource/surface-depth checks, medical-assistant avatar/push-to-talk/streaming contracts, metric evaluator, five reference slices, clean builds, and static analysis."
