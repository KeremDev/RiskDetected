#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_DIR="${1:-"$ROOT_DIR/output/snapshot-previews"}"
RESULT_BUNDLE="$EXPORT_DIR/RiskDetectedSnapshots.xcresult"
DESTINATION="${SNAPSHOT_DESTINATION:-platform=iOS Simulator,name=RD Preview iPhone 14 Pro Max}"

mkdir -p "$EXPORT_DIR"
rm -rf "$RESULT_BUNDLE"
rm -f "$EXPORT_DIR"/*.png "$EXPORT_DIR"/*.json

echo "Writing SnapshotPreviews output to: $EXPORT_DIR"
echo "Using destination: $DESTINATION"

TEST_RUNNER_SNAPSHOTS_EXPORT_DIR="$EXPORT_DIR" \
xcodebuild test \
  -project "$ROOT_DIR/RiskDetected.xcodeproj" \
  -scheme RiskDetectedSnapshots \
  -configuration Debug \
  -destination "$DESTINATION" \
  -resultBundlePath "$RESULT_BUNDLE"
