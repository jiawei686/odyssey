#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <ipad-simulator-udid> <output-directory>" >&2
    exit 2
fi
IPAD_UDID="$1"
OUTPUT_DIR="$2"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
APP="$PROJECT_DIR/.build/companion/Build/Products/Debug-iphonesimulator/UpperLimbCompanion.app"
BUNDLE_ID="com.marcel.UpperLimbPOC.Companion"
test -d "$APP"
mkdir -p "$OUTPUT_DIR"
xcrun simctl bootstatus "$IPAD_UDID" -b
xcrun simctl install "$IPAD_UDID" "$APP"
DATA_DIR="$(xcrun simctl get_app_container "$IPAD_UDID" "$BUNDLE_ID" data)"
PREFERENCES="$DATA_DIR/Library/Preferences/$BUNDLE_ID.plist"
METRICS="$OUTPUT_DIR/ct-vrt-metrics.txt"
: > "$METRICS"

clear_metrics() {
    xcrun simctl terminate "$IPAD_UDID" "$BUNDLE_ID" 2>/dev/null || true
    if [[ -f "$PREFERENCES" ]]; then
        for key in CTVRTLoadMilliseconds CTVRTTextureBytes CTVRTFrameMilliseconds CTVRTFrameCount; do
            plutil -remove "$key" "$PREFERENCES" 2>/dev/null || true
        done
    fi
}

capture_preset() {
    local label="$1"
    local screenshot="$2"
    shift 2
    clear_metrics
    xcrun simctl launch --terminate-running-process \
        "$IPAD_UDID" "$BUNDLE_ID" --ct-forearm-vrt-preview "$@"
    local ready=false
    for _ in {1..30}; do
        local count
        count="$(plutil -extract CTVRTFrameCount raw "$PREFERENCES" 2>/dev/null || true)"
        if [[ "$count" =~ ^[0-9]+$ ]] && (( count >= 60 )); then ready=true; break; fi
        sleep 1
    done
    if [[ "$ready" != true ]]; then
        echo "CT VRT evidence failed for $label: 60 completed frames not recorded." >&2
        exit 1
    fi
    local load bytes frame count
    load="$(plutil -extract CTVRTLoadMilliseconds raw "$PREFERENCES")"
    bytes="$(plutil -extract CTVRTTextureBytes raw "$PREFERENCES")"
    frame="$(plutil -extract CTVRTFrameMilliseconds raw "$PREFERENCES")"
    count="$(plutil -extract CTVRTFrameCount raw "$PREFERENCES")"
    xcrun simctl io "$IPAD_UDID" screenshot "$screenshot"
    {
        echo "preset=$label"
        echo "evidence=MEASURED_SIMULATOR"
        echo "renderer_setup_load_upload_ms=$load"
        echo "smoothed_command_completion_wall_ms=$frame"
        echo "completed_frame_samples=$count"
        echo "logical_texture_payload_bytes_inferred=$bytes"
        echo "peak_cpu_plus_gpu_payload_bytes_inferred=$((bytes * 2))"
        echo
    } >> "$METRICS"
}

capture_preset surface "$OUTPUT_DIR/ct-vrt-surface.png"
capture_preset bone "$OUTPUT_DIR/ct-vrt-bone.png" --ct-vrt-bone-preset
{
    echo "scope=Simulator command-completion wall timing; not physical AVP GPU time"
    echo "steady_state_logical_r8_payload_bytes_inferred=376320"
    echo "memory_note=Logical payload and two-copy peak are inferred; driver/view/process allocations unmeasured"
} >> "$METRICS"

test -s "$OUTPUT_DIR/ct-vrt-surface.png"
test -s "$OUTPUT_DIR/ct-vrt-bone.png"
test -s "$METRICS"
echo "CT VRT simulator evidence captured in $OUTPUT_DIR"
