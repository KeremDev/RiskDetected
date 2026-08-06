#!/usr/bin/env bash

set -euo pipefail

readonly APP_ID="6769498181"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly EVIDENCE_PATH="${ROOT_DIR}/.asc/evidence/app-privacy-readback-2026-08-01.json"

RD_ASC_APPLE_ID=""

cleanup() {
  if [[ -n "${RD_ASC_APPLE_ID}" ]]; then
    asc web auth logout --apple-id "${RD_ASC_APPLE_ID}" >/dev/null 2>&1 || true
  fi
  unset RD_ASC_APPLE_ID
}
trap cleanup EXIT

read -r -p "App Store Connect Apple Account email: " RD_ASC_APPLE_ID
if [[ -z "${RD_ASC_APPLE_ID}" || "${RD_ASC_APPLE_ID}" != *@* ]]; then
  echo "A valid Apple Account email is required." >&2
  exit 1
fi

echo "Enter the password and two-factor code only in the secure asc prompts."
echo "The password will not be stored."

ASC_WEB_DONT_STORE_PASSWORD=1 \
  asc web auth login --apple-id "${RD_ASC_APPLE_ID}" >/dev/null

asc web privacy pull \
  --app "${APP_ID}" \
  --apple-id "${RD_ASC_APPLE_ID}" \
  --out "${EVIDENCE_PATH}" >/dev/null

jq empty "${EVIDENCE_PATH}"

echo "Read-only App Privacy evidence saved:"
echo "${EVIDENCE_PATH}"
echo "The temporary asc web session will now be cleared."
