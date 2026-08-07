#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <vision-simulator-udid> <ipad-simulator-udid> <output-directory>" >&2
    exit 2
fi

VISION_UDID="$1"
IPAD_UDID="$2"
OUTPUT_DIR="$3"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VISION_APP="$PROJECT_DIR/.build/vision/Build/Products/Debug-xrsimulator/UpperLimbPOC.app"
COMPANION_APP="$PROJECT_DIR/.build/companion/Build/Products/Debug-iphonesimulator/UpperLimbCompanion.app"

test -d "$VISION_APP"
test -d "$COMPANION_APP"
mkdir -p "$OUTPUT_DIR"

xcrun simctl bootstatus "$VISION_UDID" -b
xcrun simctl bootstatus "$IPAD_UDID" -b
xcrun simctl install "$IPAD_UDID" "$COMPANION_APP"
xcrun simctl install "$VISION_UDID" "$VISION_APP"
COMPANION_DATA="$(xcrun simctl get_app_container \
    "$IPAD_UDID" \
    com.marcel.UpperLimbPOC.Companion \
    data)"
COMPANION_PREFERENCES="$COMPANION_DATA/Library/Preferences/com.marcel.UpperLimbPOC.Companion.plist"
if [[ -f "$COMPANION_PREFERENCES" ]]; then
    plutil -remove SmokeLastTintID "$COMPANION_PREFERENCES" 2>/dev/null || true
fi
xcrun simctl launch --terminate-running-process \
    "$IPAD_UDID" \
    com.marcel.UpperLimbPOC.Companion
xcrun simctl launch --terminate-running-process \
    "$VISION_UDID" \
    com.marcel.UpperLimbPOC \
    --automated-demo

snapshot_received=false
for _ in {1..20}; do
    tint="$(plutil -extract SmokeLastTintID raw \
        "$COMPANION_PREFERENCES" 2>/dev/null || true)"
    slice_index="$(plutil -extract SmokeLastSliceIndex raw \
        "$COMPANION_PREFERENCES" 2>/dev/null || true)"
    section_visible="$(plutil -extract SmokeLastSectionVisible raw \
        "$COMPANION_PREFERENCES" 2>/dev/null || true)"

    if [[ "$tint" == "amber" && "$slice_index" == "3" && "$section_visible" == "true" ]]; then
        snapshot_received=true
        break
    fi
    sleep 1
done

if [[ "$snapshot_received" != "true" ]]; then
    echo "Smoke failed: companion did not receive the expected Vision-owned snapshot." >&2
    exit 1
fi

xcrun simctl io "$VISION_UDID" screenshot "$OUTPUT_DIR/vision-automated-demo.png"
xcrun simctl io "$IPAD_UDID" screenshot "$OUTPUT_DIR/companion-automated-demo.png"

test -s "$OUTPUT_DIR/vision-automated-demo.png"
test -s "$OUTPUT_DIR/companion-automated-demo.png"

echo "Simulator smoke passed: synchronized amber slice 4/5 state and captured both screens in $OUTPUT_DIR"
