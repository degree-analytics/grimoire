#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../lib/derive-owner.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REAL_GIT="$(command -v git)"

# Set up a repo with an SSH origin
mkdir -p "$TMP/ssh_repo"
"$REAL_GIT" -C "$TMP/ssh_repo" init -q
"$REAL_GIT" -C "$TMP/ssh_repo" remote add origin git@github.com:campusiq/admin_app.git

OUT=$(derive_owner "$TMP/ssh_repo")
[ "$OUT" = $'campusiq\tadmin_app' ] || { echo "FAIL: SSH URL -> got '$OUT'"; exit 1; }

# Set up a repo with an HTTPS origin
mkdir -p "$TMP/https_repo"
"$REAL_GIT" -C "$TMP/https_repo" init -q
"$REAL_GIT" -C "$TMP/https_repo" remote add origin https://github.com/acme/bifrost.git

OUT2=$(derive_owner "$TMP/https_repo")
[ "$OUT2" = $'acme\tbifrost' ] || { echo "FAIL: HTTPS URL -> got '$OUT2'"; exit 1; }

# HTTPS without .git suffix
mkdir -p "$TMP/no_suffix"
"$REAL_GIT" -C "$TMP/no_suffix" init -q
"$REAL_GIT" -C "$TMP/no_suffix" remote add origin https://github.com/org/repo

OUT3=$(derive_owner "$TMP/no_suffix")
[ "$OUT3" = $'org\trepo' ] || { echo "FAIL: HTTPS no .git -> got '$OUT3'"; exit 1; }

# No origin remote -> exit 1
mkdir -p "$TMP/no_remote"
"$REAL_GIT" -C "$TMP/no_remote" init -q
if derive_owner "$TMP/no_remote" 2>/dev/null; then
  echo "FAIL: expected failure for repo with no origin"
  exit 1
fi

# Not a git repo -> exit 1
mkdir -p "$TMP/not_git"
if derive_owner "$TMP/not_git" 2>/dev/null; then
  echo "FAIL: expected failure for non-git directory"
  exit 1
fi

echo "PASS: test-derive-owner.sh"
