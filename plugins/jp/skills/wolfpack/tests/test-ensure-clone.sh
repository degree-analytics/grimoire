#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/ensure-clone.sh"

# Create a temp review dir
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
mkdir -p "$TMP/admin_app" # exists
# bifrost and ghost don't exist

# Input: newline-separated "repo<TAB>nameWithOwner"
INPUT=$'admin_app\tcampusiq/admin_app\nbifrost\tcampusiq/bifrost\nghost\tcampusiq/ghost'

OUT=$(echo "$INPUT" | "$SCRIPT" --review-dir "$TMP" --check-only)

# Expect missing clones: bifrost, ghost (one per line, tab-separated)
EXPECTED="bifrost	campusiq/bifrost
ghost	campusiq/ghost"
[ "$OUT" = "$EXPECTED" ] || { echo "FAIL: missing mismatch"; echo "got: $OUT"; echo "expected: $EXPECTED"; exit 1; }

echo "PASS: test-ensure-clone.sh"
