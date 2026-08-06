#!/bin/sh

set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
  exit 0
fi

if command -v node >/dev/null 2>&1; then
  rd_node_bin="$(command -v node)"
elif [ -x /opt/homebrew/bin/node ]; then
  rd_node_bin=/opt/homebrew/bin/node
elif [ -x /usr/local/bin/node ]; then
  rd_node_bin=/usr/local/bin/node
else
  echo "error: Localization release gate requires Node.js." >&2
  exit 1
fi

cd "${SRCROOT:?SRCROOT is required}"
"$rd_node_bin" scripts/localization_catalog_tests.mjs

case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " in
  *" RD_GLOBAL_LOCALIZATION_WAVE1 "*)
    "$rd_node_bin" scripts/verify_phase5_external_gates.mjs --mode=release --live
    ;;
  *)
    echo "notice: RD_GLOBAL_LOCALIZATION_WAVE1 is disabled; building the Turkish legacy path."
    ;;
esac
