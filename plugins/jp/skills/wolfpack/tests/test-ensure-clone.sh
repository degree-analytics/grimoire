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

# --clone against a fresh REVIEW_DIR where the owner subdir does not yet exist.
# `gh repo clone` delegates to `git clone`, which does NOT create leading path
# components — so the script must mkdir -p the owner parent before cloning.
FRESH=$(mktemp -d)
trap 'rm -rf "$TMP" "$CROSS" "$FRESH"' EXIT
STUB_BIN="$FRESH/bin"
mkdir -p "$STUB_BIN"

# Stub gh: asserts the target's parent dir exists, then simulates a successful
# clone by creating the target dir (mirroring `git clone`'s behavior).
cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Expect: gh repo clone <nwo> <target>
target="$4"
parent="$(dirname "$target")"
if [ ! -d "$parent" ]; then
  echo "STUB FAIL: parent dir $parent does not exist for target $target" >&2
  exit 1
fi
mkdir -p "$target"
STUB
chmod +x "$STUB_BIN/gh"

REV="$FRESH/review"  # deliberately does not exist yet
INPUT3=$'admin_app\tacme/admin_app\nbifrost\tbeta/bifrost'
PATH="$STUB_BIN:$PATH" echo "$INPUT3" | PATH="$STUB_BIN:$PATH" "$SCRIPT" --review-dir "$REV" --clone
[ -d "$REV/acme/admin_app" ] || { echo "FAIL: clone did not create acme/admin_app"; exit 1; }
[ -d "$REV/beta/bifrost" ]   || { echo "FAIL: clone did not create beta/bifrost"; exit 1; }

# Flat-layout clone: $REVIEW_DIR/<repo>/ exists with origin URL matching <nameWithOwner>.
# --check-only should recognize it as present, not report it as missing.
FLAT=$(mktemp -d)
REAL_GIT="$(command -v git)"
trap 'rm -rf "$TMP" "$CROSS" "$FRESH" "$FLAT"' EXIT
mkdir -p "$FLAT/admin_app"
"$REAL_GIT" -C "$FLAT/admin_app" init -q
"$REAL_GIT" -C "$FLAT/admin_app" remote add origin git@github.com:campusiq/admin_app.git

INPUT_FLAT=$'admin_app\tcampusiq/admin_app'
OUT_FLAT=$(echo "$INPUT_FLAT" | "$SCRIPT" --review-dir "$FLAT" --check-only)
[ -z "$OUT_FLAT" ] || {
  echo "FAIL: flat clone with matching origin should not be reported as missing"
  echo "got: $OUT_FLAT"
  exit 1
}

# Flat clone with DIFFERENT origin should still be reported as missing.
INPUT_DIFF=$'admin_app\tother_org/admin_app'
OUT_DIFF=$(echo "$INPUT_DIFF" | "$SCRIPT" --review-dir "$FLAT" --check-only)
EXPECTED_DIFF="admin_app	other_org/admin_app"
[ "$OUT_DIFF" = "$EXPECTED_DIFF" ] || {
  echo "FAIL: flat clone with non-matching origin should be reported as missing"
  echo "got: $OUT_DIFF"
  echo "expected: $EXPECTED_DIFF"
  exit 1
}

echo "PASS: test-ensure-clone.sh"
