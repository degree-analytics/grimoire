#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../lib/resolve-clone.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REAL_GIT="$(command -v git)"

# --- Nested layout: $REVIEW_DIR/<owner>/<repo>/.git ---
mkdir -p "$TMP/nested/campusiq/admin_app"
"$REAL_GIT" -C "$TMP/nested/campusiq/admin_app" init -q
"$REAL_GIT" -C "$TMP/nested/campusiq/admin_app" remote add origin git@github.com:campusiq/admin_app.git

OUT=$(resolve_clone_path "$TMP/nested" "campusiq/admin_app")
[ "$OUT" = "$TMP/nested/campusiq/admin_app" ] || {
  echo "FAIL: nested layout — expected '$TMP/nested/campusiq/admin_app', got '$OUT'"
  exit 1
}

# --- Flat layout: $REVIEW_DIR/<repo>/.git with matching origin ---
mkdir -p "$TMP/flat/admin_app"
"$REAL_GIT" -C "$TMP/flat/admin_app" init -q
"$REAL_GIT" -C "$TMP/flat/admin_app" remote add origin git@github.com:campusiq/admin_app.git

OUT2=$(resolve_clone_path "$TMP/flat" "campusiq/admin_app")
[ "$OUT2" = "$TMP/flat/admin_app" ] || {
  echo "FAIL: flat layout — expected '$TMP/flat/admin_app', got '$OUT2'"
  exit 1
}

# --- Flat with non-matching origin should fail ---
if resolve_clone_path "$TMP/flat" "other_org/admin_app" 2>/dev/null; then
  echo "FAIL: flat clone with non-matching origin should fail"
  exit 1
fi

# --- Nested preferred over flat when both exist ---
mkdir -p "$TMP/both/campusiq/admin_app" "$TMP/both/admin_app"
"$REAL_GIT" -C "$TMP/both/campusiq/admin_app" init -q
"$REAL_GIT" -C "$TMP/both/campusiq/admin_app" remote add origin git@github.com:campusiq/admin_app.git
"$REAL_GIT" -C "$TMP/both/admin_app" init -q
"$REAL_GIT" -C "$TMP/both/admin_app" remote add origin git@github.com:campusiq/admin_app.git

OUT3=$(resolve_clone_path "$TMP/both" "campusiq/admin_app")
[ "$OUT3" = "$TMP/both/campusiq/admin_app" ] || {
  echo "FAIL: nested should be preferred over flat — expected '$TMP/both/campusiq/admin_app', got '$OUT3'"
  exit 1
}

# --- No clone at all should fail ---
EMPTY=$(mktemp -d)
trap 'rm -rf "$TMP" "$EMPTY"' EXIT
if resolve_clone_path "$EMPTY" "campusiq/admin_app" 2>/dev/null; then
  echo "FAIL: missing clone should fail"
  exit 1
fi

echo "PASS: test-resolve-clone.sh"
