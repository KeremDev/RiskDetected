#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${UI_TEST_DESTINATION:-platform=iOS Simulator,name=RD QA iPhone 16 Pro}"
RESULT_BUNDLE="${UI_TEST_RESULT_BUNDLE:-}"
ONLY_TESTS=("$@")

echo "Preparing simulator for UI tests..."
killall -9 xcodebuild 2>/dev/null || true
killall -9 XCTest 2>/dev/null || true

if [[ "$DESTINATION" == *"id="* ]]; then
  SIM_ID="${DESTINATION#*id=}"
  xcrun simctl boot "$SIM_ID" 2>/dev/null || true
  xcrun simctl bootstatus "$SIM_ID" -b >/dev/null
else
  xcrun simctl boot "$DESTINATION" 2>/dev/null || true
fi

open -a Simulator >/dev/null 2>&1 || true

if [[ "${UI_TEST_SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building test bundles..."
  xcodebuild build-for-testing \
    -project "$ROOT_DIR/RiskDetected.xcodeproj" \
    -scheme RiskDetected \
    -configuration Debug \
    -destination "$DESTINATION" \
    -quiet
else
  echo "Skipping build (UI_TEST_SKIP_BUILD=1)."
fi

TEST_ARGS=(
  test-without-building
  -project "$ROOT_DIR/RiskDetected.xcodeproj"
  -scheme RiskDetected
  -configuration Debug
  -destination "$DESTINATION"
  -parallel-testing-enabled NO
)

if [[ -n "$RESULT_BUNDLE" ]]; then
  rm -rf "$RESULT_BUNDLE"
  TEST_ARGS+=(-resultBundlePath "$RESULT_BUNDLE")
fi

if ((${#ONLY_TESTS[@]} > 0)); then
  for test_name in "${ONLY_TESTS[@]}"; do
    TEST_ARGS+=("-only-testing:RiskDetectedUITests/RiskDetectedUITests/$test_name")
  done
fi

echo "Running UI tests with destination: $DESTINATION"
TEST_TIMEOUT_SECONDS="${UI_TEST_TIMEOUT_SECONDS:-180}"
perl -e 'alarm shift; exec @ARGV' "$TEST_TIMEOUT_SECONDS" xcodebuild "${TEST_ARGS[@]}"
