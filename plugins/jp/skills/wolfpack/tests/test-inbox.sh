#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/inbox.sh"
FIXTURE="$HERE/fixtures/gh-search-prs.json"

# Test 1: --from-file reads fixture and normalizes schema
OUT=$("$SCRIPT" --from-file "$FIXTURE")
COUNT=$(echo "$OUT" | jq 'length')
[ "$COUNT" = "3" ] || { echo "FAIL: expected 3 PRs, got $COUNT"; exit 1; }

REPO=$(echo "$OUT" | jq -r '.[0].repo')
[ "$REPO" = "admin_app" ] || { echo "FAIL: expected repo admin_app, got $REPO"; exit 1; }

OWNER=$(echo "$OUT" | jq -r '.[0].nameWithOwner')
[ "$OWNER" = "campusiq/admin_app" ] || { echo "FAIL: expected campusiq/admin_app, got $OWNER"; exit 1; }

# Test 2: output is valid JSON array
echo "$OUT" | jq -e 'type == "array"' >/dev/null || { echo "FAIL: not a JSON array"; exit 1; }

# Test 3: .author is a plain string, not an object.
# inbox.sh flattens {login: "alice"} → "alice" during normalization.
# Callers should use .author, not .author.login.
AUTHOR=$(echo "$OUT" | jq -r '.[0].author')
[ "$AUTHOR" = "alice" ] || { echo "FAIL: expected author 'alice', got '$AUTHOR'"; exit 1; }
AUTHOR_TYPE=$(echo "$OUT" | jq -r '.[0].author | type')
[ "$AUTHOR_TYPE" = "string" ] || { echo "FAIL: author should be a string, got $AUTHOR_TYPE"; exit 1; }

echo "PASS: test-inbox.sh"
