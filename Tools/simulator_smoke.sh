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
xcrun simctl launch --terminate-running-process \
    "$IPAD_UDID" \
    com.marcel.UpperLimbPOC.Companion
xcrun simctl launch --terminate-running-process \
    "$VISION_UDID" \
    com.marcel.UpperLimbPOC \
    --automated-demo

sleep 5

xcrun simctl io "$VISION_UDID" screenshot "$OUTPUT_DIR/vision-automated-demo.png"
xcrun simctl io "$IPAD_UDID" screenshot "$OUTPUT_DIR/companion-automated-demo.png"

echo "Simulator smoke evidence written to $OUTPUT_DIR"
