#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  cat <<'USAGE'
Usage:
  scripts/rd_store_secret.sh <service>

Allowed services:
  riskdetected_supabase_access_token
  riskdetected_supabase_db_password
  riskdetected_revenuecat_rest_api_key
  riskdetected_qa_supabase_db_password
  riskdetected_qa_supabase_url
  riskdetected_qa_supabase_publishable_key
  riskdetected_qa_revenuecat_api_key
  riskdetected_qa_app_store_revenuecat_api_key
  riskdetected_qa_storekit_revenuecat_api_key
  riskdetected_qa_revenuecat_webhook_authorization
USAGE
  exit 1
fi

service="$1"
case "$service" in
  riskdetected_supabase_access_token|riskdetected_supabase_db_password|riskdetected_revenuecat_rest_api_key|riskdetected_qa_supabase_db_password|riskdetected_qa_supabase_url|riskdetected_qa_supabase_publishable_key|riskdetected_qa_revenuecat_api_key|riskdetected_qa_app_store_revenuecat_api_key|riskdetected_qa_storekit_revenuecat_api_key|riskdetected_qa_revenuecat_webhook_authorization)
    ;;
  *)
    echo "Unsupported service: $service" >&2
    exit 1
    ;;
esac

printf "Enter secret for %s: " "$service" >&2
IFS= read -r -s secret
printf "\n" >&2

if [[ -z "$secret" ]]; then
  echo "Secret cannot be empty." >&2
  exit 1
fi

security add-generic-password \
  -U \
  -a "$USER" \
  -s "$service" \
  -w "$secret" >/dev/null

echo "Stored $service in macOS Keychain."
