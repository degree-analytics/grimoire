#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/ensure-clone.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# campusiq/admin_app already cloned; bifrost and ghost are missing.
mkdir -p "$TMP/campusiq/admin_app"

# Input: newline-separated "repo<TAB>nameWithOwner"
INPUT=$'admin_app\tcampusiq/admin_app\nbifrost\tcampusiq/bifrost\nghost\tcampusiq/ghost'

OUT=$(echo "$INPUT" | "$SCRIPT" --review-dir "$TMP" --check-only)
EXPECTED="bifrost	campusiq/bifrost
ghost	campusiq/ghost"
[ "$OUT" = "$EXPECTED" ] || { echo "FAIL: missing mismatch"; echo "got: $OUT"; echo "expected: $EXPECTED"; exit 1; }

# Cross-owner collision: same short name under two different owners.
# Both must be treated independently — caching on short name alone would
# mis-identify beta/admin_app as already cloned.
CROSS=$(mktemp -d)
trap 'rm -rf "$TMP" "$CROSS"' EXIT
mkdir -p "$CROSS/acme/admin_app"
INPUT2=$'admin_app\tacme/admin_app\nadmin_app\tbeta/admin_app'

OUT2=$(echo "$INPUT2" | "$SCRIPT" --review-dir "$CROSS" --check-only)
EXPECTED2="admin_app	beta/admin_app"
[ "$OUT2" = "$EXPECTED2" ] || {
  echo "FAIL: cross-owner collision — beta/admin_app should be reported missing even though acme/admin_app exists"
  echo "got: $OUT2"
  echo "expected: $EXPECTED2"
  exit 1
}

echo "PASS: test-ensure-clone.sh"
