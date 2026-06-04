#!/usr/bin/env bash
set -euo pipefail

project_ref="${RISKDETECTED_QA_SUPABASE_REF:-iidhnqvuszjcoyncqzkg}"

read_secret() {
  local service="$1"
  security find-generic-password -a "$USER" -s "$service" -w 2>/dev/null || true
}

access_token="$(read_secret riskdetected_supabase_access_token)"
revenuecat_key="$(read_secret riskdetected_qa_revenuecat_api_key)"
webhook_authorization="$(read_secret riskdetected_qa_revenuecat_webhook_authorization)"

if [[ -z "$access_token" ]]; then
  echo "Missing riskdetected_supabase_access_token in Keychain." >&2
  exit 1
fi

if [[ "$revenuecat_key" != test_* ]]; then
  cat >&2 <<'ERROR'
Missing RevenueCat Test Store API key in Keychain.

Run:
  scripts/rd_store_secret.sh riskdetected_qa_revenuecat_api_key
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

echo "Configured QA Supabase subscription secrets for project $project_ref."
