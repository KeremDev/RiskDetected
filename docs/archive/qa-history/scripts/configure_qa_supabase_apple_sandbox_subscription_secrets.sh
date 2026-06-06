#!/usr/bin/env bash
set -euo pipefail

project_ref="${RISKDETECTED_QA_SUPABASE_REF:-iidhnqvuszjcoyncqzkg}"
revenuecat_key="${RISKDETECTED_REVENUECAT_API_KEY:-appl_mckFFxUrvtNqzjShezjMIrFmItA}"

read_secret() {
  local service="$1"
  security find-generic-password -a "$USER" -s "$service" -w 2>/dev/null || true
}

mask_key() {
  local key="$1"
  if (( ${#key} <= 10 )); then
    printf '%s' "$key"
    return
  fi
  printf '%s...%s' "${key:0:8}" "${key: -4}"
}

access_token="$(read_secret riskdetected_supabase_access_token)"
webhook_authorization="$(read_secret riskdetected_qa_revenuecat_webhook_authorization)"

if [[ -z "$access_token" ]]; then
  echo "Missing riskdetected_supabase_access_token in Keychain." >&2
  exit 1
fi

if [[ "$revenuecat_key" != appl_* ]]; then
  cat >&2 <<'ERROR'
Missing RevenueCat App Store API key.

Apple Sandbox/TestFlight QA must use the RevenueCat App Store key that belongs
to bundle id com.riskdetected.app. Do not use a Test Store key on this lane.
ERROR
  exit 1
fi

if [[ -z "$webhook_authorization" ]]; then
  webhook_authorization="Bearer qa_$(openssl rand -hex 24)"
  security add-generic-password \
    -U \
    -a "$USER" \
    -s riskdetected_qa_revenuecat_webhook_authorization \
    -w "$webhook_authorization" >/dev/null
fi

SUPABASE_ACCESS_TOKEN="$access_token" supabase secrets set \
  REVENUECAT_REST_API_KEY="$revenuecat_key" \
  REVENUECAT_WEBHOOK_AUTHORIZATION="$webhook_authorization" \
  --project-ref "$project_ref"

echo "Configured QA Supabase Apple Sandbox subscription secrets for project $project_ref."
echo "RevenueCat key: $(mask_key "$revenuecat_key")"
