#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scheme="${RISKDETECTED_QA_SCHEME:-RiskDetected QA}"
destination="${RISKDETECTED_QA_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro}"

read_secret() {
  local service="$1"
  security find-generic-password -a "$USER" -s "$service" -w 2>/dev/null || true
}

supabase_url="$(read_secret riskdetected_qa_supabase_url)"
supabase_key="$(read_secret riskdetected_qa_supabase_publishable_key)"
revenuecat_key="${RISKDETECTED_REVENUECAT_API_KEY:-appl_mckFFxUrvtNqzjShezjMIrFmItA}"
offering_identifier="${RISKDETECTED_REVENUECAT_OFFERING_IDENTIFIER:-default}"

if [[ -z "$supabase_url" || -z "$supabase_key" ]]; then
  cat >&2 <<'ERROR'
Missing QA Supabase client config in Keychain.

Run:
  scripts/rd_store_secret.sh riskdetected_qa_supabase_url
  scripts/rd_store_secret.sh riskdetected_qa_supabase_publishable_key
ERROR
  exit 1
fi

if [[ "$revenuecat_key" != appl_* ]]; then
  cat >&2 <<'ERROR'
Missing RevenueCat App Store SDK key.

Apple Sandbox/TestFlight QA uses the RevenueCat App Store public SDK key that
belongs to bundle id com.riskdetected.app. Override with
RISKDETECTED_REVENUECAT_API_KEY only when intentionally testing another app.
ERROR
  exit 1
fi

cd "$project_root"

xcodebuild \
  -project RiskDetected.xcodeproj \
  -scheme "$scheme" \
  -configuration QA \
  -destination "$destination" \
  RISKDETECTED_SUPABASE_URL="$supabase_url" \
  RISKDETECTED_SUPABASE_PUBLISHABLE_KEY="$supabase_key" \
  RISKDETECTED_REVENUECAT_API_KEY="$revenuecat_key" \
  RISKDETECTED_REVENUECAT_OFFERING_IDENTIFIER="$offering_identifier" \
  build
