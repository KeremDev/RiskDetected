#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_DIR="${1:-"$ROOT_DIR/output/snapshot-previews"}"
DEFAULT_DESTINATIONS="platform=iOS Simulator,name=RD QA iPhone 13;platform=iOS Simulator,name=RD Preview iPhone 14 Pro Max"
DESTINATION_LIST="${SNAPSHOT_DESTINATIONS:-${SNAPSHOT_DESTINATION:-$DEFAULT_DESTINATIONS}}"

mkdir -p "$EXPORT_DIR"
echo "Writing SnapshotPreviews output to: $EXPORT_DIR"

IFS=';' read -r -a DESTINATIONS <<< "$DESTINATION_LIST"
for DESTINATION in "${DESTINATIONS[@]}"; do
  DEVICE_NAME="${DESTINATION##*name=}"
  DEVICE_NAME="${DEVICE_NAME%%,*}"
  DEVICE_SLUG="$(printf '%s' "$DEVICE_NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]_-')"
  DEVICE_EXPORT_DIR="$EXPORT_DIR/$DEVICE_SLUG"
  RESULT_BUNDLE="$EXPORT_DIR/RiskDetectedSnapshots-$DEVICE_SLUG.xcresult"

  mkdir -p "$DEVICE_EXPORT_DIR"
  rm -rf "$RESULT_BUNDLE"
  rm -f "$DEVICE_EXPORT_DIR"/*.png "$DEVICE_EXPORT_DIR"/*.json

  echo "Using destination: $DESTINATION"
  TEST_RUNNER_SNAPSHOTS_EXPORT_DIR="$DEVICE_EXPORT_DIR" \
  xcodebuild test \
    -project "$ROOT_DIR/RiskDetected.xcodeproj" \
    -scheme RiskDetectedSnapshots \
    -configuration Debug \
    -destination "$DESTINATION" \
    -resultBundlePath "$RESULT_BUNDLE"
done
