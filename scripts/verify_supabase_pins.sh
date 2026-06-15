#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/App/Services/RDConfig.swift"
HOST="$(grep -E 'static let supabaseURL' "$CONFIG_FILE" | sed -E 's#.*https://([^"/]+).*#\1#')"

if [[ -z "$HOST" ]]; then
  echo "Could not read Supabase host from RDConfig.swift" >&2
  exit 2
fi

EXPECTED_HASHES=()
while IFS= read -r hash; do
  EXPECTED_HASHES+=("$hash")
done < <(
  awk '/pinnedCertificateSHA256Hashes/,/]/' "$CONFIG_FILE" \
    | grep -Eo '"[A-Za-z0-9+/=]{32,}"' \
    | tr -d '"'
)

if [[ ${#EXPECTED_HASHES[@]} -eq 0 ]]; then
  echo "No pinned certificate hashes found in RDConfig.swift" >&2
  exit 2
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo | openssl s_client -servername "$HOST" -connect "$HOST:443" -showcerts 2>/dev/null \
  | /usr/bin/perl -ne 'if (/BEGIN CERTIFICATE/) {$i++; open F, ">", sprintf("'"$WORKDIR"'/cert%02d.pem", $i)} print F if $i; if (/END CERTIFICATE/) {close F}'

LIVE_HASHES=()
for cert in "$WORKDIR"/cert*.pem; do
  hash="$(
    openssl x509 -in "$cert" -outform der \
      | openssl dgst -sha256 -binary \
      | openssl base64
  )"
  LIVE_HASHES+=("$hash")
done

echo "Supabase host: $HOST"
echo "Live chain SHA-256 certificate hashes:"
printf '  %s\n' "${LIVE_HASHES[@]}"

for expected in "${EXPECTED_HASHES[@]}"; do
  for live in "${LIVE_HASHES[@]}"; do
    if [[ "$expected" == "$live" ]]; then
      echo "Pin match: $expected"
      exit 0
    fi
  done
done

echo "No configured pin matched the live certificate chain." >&2
echo "Expected pins:" >&2
printf '  %s\n' "${EXPECTED_HASHES[@]}" >&2
exit 1
