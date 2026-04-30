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

# Test 4: isDraft is preserved in output
DRAFT=$(echo "$OUT" | jq -r '.[2].isDraft')
[ "$DRAFT" = "true" ] || { echo "FAIL: expected isDraft=true for PR #892, got $DRAFT"; exit 1; }

NOT_DRAFT=$(echo "$OUT" | jq -r '.[0].isDraft')
[ "$NOT_DRAFT" = "false" ] || { echo "FAIL: expected isDraft=false for PR #1234, got $NOT_DRAFT"; exit 1; }

# Test 5: checks field is normalized to comma-joined states
CHECKS_0=$(echo "$OUT" | jq -r '.[0].checks')
[ "$CHECKS_0" = "SUCCESS" ] || { echo "FAIL: expected checks=SUCCESS for PR #1234, got $CHECKS_0"; exit 1; }

CHECKS_2=$(echo "$OUT" | jq -r '.[2].checks')
[ "$CHECKS_2" = "" ] || { echo "FAIL: expected checks='' for PR #892 (no checks), got $CHECKS_2"; exit 1; }

echo "PASS: test-inbox.sh"
