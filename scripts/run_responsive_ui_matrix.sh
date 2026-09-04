#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${RESPONSIVE_UI_RUNTIME:-$(xcrun simctl list runtimes available | awk '/^iOS / { runtime=$NF } END { print runtime }')}"

if [[ -z "$RUNTIME" ]]; then
  echo "No available iOS simulator runtime was found." >&2
  exit 1
fi

ensure_device() {
  local name="$1"
  local device_type="$2"

  if ! xcrun simctl list devices available | grep -Fq "    $name ("; then
    echo "Creating $name on $RUNTIME"
    xcrun simctl create "$name" "$device_type" "$RUNTIME" >/dev/null
  fi
}

DEVICE_MATRIX=(
  "RD Responsive iPhone SE 3|com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"
  "RD Responsive iPhone 13 mini|com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini"
  "RD QA iPhone 13|com.apple.CoreSimulator.SimDeviceType.iPhone-13"
  "RD Responsive iPhone 11|com.apple.CoreSimulator.SimDeviceType.iPhone-11"
  "RD QA iPhone 14 Pro|com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro"
  "RD Preview iPhone 14 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro-Max"
  "RD Responsive iPhone 17 Pro|com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
  "RD Responsive iPhone 17 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
)

TESTS=(
  testEnglishMainAccessibilityLayoutAtLargestDynamicType
  testResponsivePaywallAtLargestDynamicTypeKeepsPlansCTAAndLegalReachable
  testResponsiveResultHubAtLargestDynamicTypeKeepsTabsAndReportActionReachable
)

if (($# > 0)); then
  TESTS=("$@")
fi

FIRST_RUN=1
for ENTRY in "${DEVICE_MATRIX[@]}"; do
  NAME="${ENTRY%%|*}"
  DEVICE_TYPE="${ENTRY##*|}"
  ensure_device "$NAME" "$DEVICE_TYPE"

  echo "Running responsive UI checks on $NAME"
  if ((FIRST_RUN == 1)); then
    UI_TEST_DESTINATION="platform=iOS Simulator,name=$NAME" \
      "$ROOT_DIR/scripts/run_ui_tests.sh" "${TESTS[@]}"
    FIRST_RUN=0
  else
    UI_TEST_SKIP_BUILD=1 \
    UI_TEST_DESTINATION="platform=iOS Simulator,name=$NAME" \
      "$ROOT_DIR/scripts/run_ui_tests.sh" "${TESTS[@]}"
  fi
done
