#!/bin/zsh

set -euo pipefail

readonly keychain_service="riskdetected_gemini_api_key_canary"
readonly keychain_account="${USER:?USER is required}"

gemini_canary_key="$(
  security find-generic-password \
    -a "$keychain_account" \
    -s "$keychain_service" \
    -w 2>/dev/null
)" || {
  print -u2 -- "CANARY_KEYCHAIN_PROVIDER_KEY_MISSING"
  exit 2
}

if (( ${#gemini_canary_key} < 20 )); then
  unset gemini_canary_key
  print -u2 -- "CANARY_KEYCHAIN_PROVIDER_KEY_INVALID"
  exit 2
fi

export GEMINI_API_KEY="$gemini_canary_key"
unset gemini_canary_key

exec "$(dirname "$0")/run_ai_localization_canary.mjs" "$@"
