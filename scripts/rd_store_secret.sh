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
USAGE
  exit 1
fi

service="$1"
case "$service" in
  riskdetected_supabase_access_token|riskdetected_supabase_db_password|riskdetected_revenuecat_rest_api_key)
    ;;
  *)
    echo "Unsupported service: $service" >&2
    exit 1
    ;;
esac

# Keep the secret out of shell memory and the process argument list. With -w
# as the final option, macOS Keychain prompts for the value itself.
printf "macOS Keychain will securely prompt for %s.\n" "$service" >&2
security add-generic-password \
  -U \
  -a "$USER" \
  -s "$service" \
  -w >/dev/null

echo "Stored $service in macOS Keychain."
