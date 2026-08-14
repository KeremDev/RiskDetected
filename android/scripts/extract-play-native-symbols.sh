#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: extract-play-native-symbols.sh <release.aab> <native-debug-symbols.zip>" >&2
  exit 64
fi

aab_path="$1"
output_path="$2"

[[ -f "$aab_path" ]] || { echo "AAB not found: $aab_path" >&2; exit 2; }
if command -v readelf >/dev/null; then
  has_symbol_table() { readelf -SW "$1" | grep '[[:space:]]\.symtab[[:space:]]' >/dev/null; }
elif command -v objdump >/dev/null; then
  has_symbol_table() { objdump -h "$1" 2>/dev/null | grep '[[:space:]]\.symtab[[:space:]]' >/dev/null; }
else
  echo "readelf or objdump is required to inspect native symbols." >&2
  exit 3
fi
command -v zip >/dev/null || { echo "zip is required to package native symbols." >&2; exit 3; }

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/riskdetected-native-symbols.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

unzip -q "$aab_path" 'base/lib/*/*.so' -d "$work_dir/aab" 2>/dev/null || true
symbol_count=0
while IFS= read -r library; do
  if has_symbol_table "$library"; then
    # Play expects ABI directories at the archive root (for example,
    # arm64-v8a/libexample.so), not the AAB's intermediate lib/ prefix.
    relative_path="${library#"$work_dir/aab/base/lib/"}"
    destination="$work_dir/archive/$relative_path"
    mkdir -p "$(dirname "$destination")"
    cp "$library" "$destination"
    symbol_count=$((symbol_count + 1))
  fi
done < <(find "$work_dir/aab/base/lib" -type f -name '*.so' -print 2>/dev/null | sort)

if (( symbol_count == 0 )); then
  echo "The AAB contains no native library with an available ELF symbol table." >&2
  exit 4
fi

mkdir -p "$(dirname "$output_path")"
output_path="$(cd "$(dirname "$output_path")" && pwd)/$(basename "$output_path")"
rm -f "$output_path"
(
  cd "$work_dir/archive"
  zip -q -r "$output_path" .
)
unzip -tq "$output_path" >/dev/null
if ! unzip -Z1 "$output_path" | awk -F/ '
  $1 !~ /^(armeabi-v7a|arm64-v8a|x86|x86_64)$/ { invalid = 1 }
  END { exit invalid }
'; then
  echo "Native symbol archive must contain Android ABI directories at its root." >&2
  exit 5
fi
sha256sum "$output_path"
echo "Packaged $symbol_count symbol-bearing native libraries for Play."
