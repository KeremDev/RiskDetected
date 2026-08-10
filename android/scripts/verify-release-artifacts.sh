#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: verify-release-artifacts.sh <release.aab> <bundletool.jar> [google-services.json]" >&2
  exit 64
fi

aab_path="$1"
bundletool_path="$2"

[[ -f "$aab_path" ]] || { echo "AAB not found: $aab_path" >&2; exit 2; }
[[ -f "$bundletool_path" ]] || { echo "bundletool not found: $bundletool_path" >&2; exit 2; }

verify_dir=$(mktemp -d "${TMPDIR:-/tmp}/riskdetected-aab-verify.XXXXXX")
trap 'rm -rf "$verify_dir"' EXIT

java -jar "$bundletool_path" validate --bundle="$aab_path" >"$verify_dir/bundletool-validate.txt"
echo "bundletool validate passed."
LC_ALL=C jarsigner -verify -verbose -certs "$aab_path" >"$verify_dir/jarsigner.txt"
grep -q '^jar verified\.$' "$verify_dir/jarsigner.txt" || {
  echo "AAB signature verification did not report a signed, verified JAR." >&2
  exit 9
}
echo "AAB JAR signature verified."

bundle_config=$(java -jar "$bundletool_path" dump config --bundle="$aab_path")
grep -q "PAGE_ALIGNMENT_16K" <<<"$bundle_config" || {
  echo "AAB does not request PAGE_ALIGNMENT_16K." >&2
  exit 3
}

for forbidden in "Assets.xcassets" "AppIcon.appiconset" "Contents.json"; do
  if unzip -Z1 "$aab_path" | grep -F "$forbidden" >/dev/null; then
    echo "Forbidden iOS asset leaked into AAB: $forbidden" >&2
    exit 4
  fi
done

payload_strings_path="$verify_dir/payload-strings.txt"
unzip -p "$aab_path" | strings >"$payload_strings_path"
if grep -Eqi \
  'sb_secret_[0-9A-Za-z_-]{16,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
  "$payload_strings_path"; then
  echo "Server-secret marker found in release bundle." >&2
  exit 5
fi
command -v python3 >/dev/null || { echo "python3 is required for JWT role scanning." >&2; exit 5; }
firebase_config_path="${3:-$script_dir/../app/google-services.json}"
[[ -f "$firebase_config_path" ]] || { echo "Production google-services.json not found." >&2; exit 5; }
python3 - "$payload_strings_path" "$firebase_config_path" <<'PY'
import base64
import json
import pathlib
import re
import sys

raw_strings = pathlib.Path(sys.argv[1]).read_text(errors="ignore").splitlines()
firebase_document = json.loads(pathlib.Path(sys.argv[2]).read_text())
allowed_google_keys = {
    entry.get("current_key")
    for client in firebase_document.get("client", [])
    for entry in client.get("api_key", [])
    if isinstance(entry.get("current_key"), str)
}
if not allowed_google_keys:
    print("Production Firebase client key allowlist is empty.", file=sys.stderr)
    raise SystemExit(5)

for raw in raw_strings:
    for candidate in re.findall(r"AIza[0-9A-Za-z_-]{30,}", raw):
        if candidate not in allowed_google_keys:
            print("Unapproved Google API key found in release bundle.", file=sys.stderr)
            raise SystemExit(5)

for raw in raw_strings:
    for candidate in re.findall(r"re_[A-Za-z0-9]{24,}", raw):
        if any(character.isdigit() for character in candidate[3:]):
            print("Resend-shaped secret found in release bundle.", file=sys.stderr)
            raise SystemExit(5)

for raw in raw_strings:
    token = raw.strip()
    if not token.startswith("eyJ") or token.count(".") != 2:
        continue
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        decoded = json.loads(base64.urlsafe_b64decode(payload))
    except Exception:
        continue
    if decoded.get("role") == "service_role":
        print("Supabase service-role JWT found in release bundle.", file=sys.stderr)
        raise SystemExit(5)
PY

apks_path="$verify_dir/release.apks"
java -jar "$bundletool_path" build-apks \
  --bundle="$aab_path" \
  --output="$apks_path" \
  --mode=universal \
  --overwrite
unzip -q "$apks_path" universal.apk -d "$verify_dir"

sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk_root" && -f "$script_dir/../local.properties" ]]; then
  sdk_root=$(sed -n 's/^sdk\.dir=//p' "$script_dir/../local.properties" | head -n 1)
fi
[[ -n "$sdk_root" ]] || { echo "ANDROID_HOME/ANDROID_SDK_ROOT or local.properties sdk.dir is required." >&2; exit 6; }
build_tools_dir="$sdk_root/build-tools/37.0.0"
zipalign_path="$build_tools_dir/zipalign"
[[ -x "$zipalign_path" ]] || { echo "zipalign 37.0.0 not found." >&2; exit 6; }
"$zipalign_path" -c -P 16 -v 4 "$verify_dir/universal.apk" >/dev/null

native_dir="$verify_dir/native"
mkdir -p "$native_dir"
unzip -q "$verify_dir/universal.apk" 'lib/*/*.so' -d "$native_dir" 2>/dev/null || true
if [[ -n "$(find "$native_dir" -type f -name '*.so' -print -quit)" ]]; then
  if command -v readelf >/dev/null; then
    while IFS= read -r library; do
      while IFS= read -r alignment; do
        if (( alignment < 0x4000 )); then
          echo "ELF LOAD segment is not 16 KB aligned: $library ($alignment)" >&2
          exit 8
        fi
      done < <(readelf -lW "$library" | awk '$1 == "LOAD" { print $NF }')
    done < <(find "$native_dir" -type f -name '*.so' -print)
  elif command -v objdump >/dev/null; then
    while IFS= read -r library; do
      while IFS= read -r exponent; do
        if (( exponent < 14 )); then
          echo "ELF LOAD segment is not 16 KB aligned: $library (2**$exponent)" >&2
          exit 8
        fi
      done < <(objdump -p "$library" | awk '$1 == "LOAD" { sub(/^2\*\*/, "", $NF); print $NF }')
    done < <(find "$native_dir" -type f -name '*.so' -print)
  else
    echo "readelf or objdump is required for ELF alignment checks." >&2
    exit 7
  fi
fi

keytool -printcert -jarfile "$aab_path"
sha256sum "$aab_path"
echo "Release artifact verification passed."
