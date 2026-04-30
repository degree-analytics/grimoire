#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/triage.sh"
FIXTURES="$HERE/fixtures"

# --- Helper: build a minimal PR JSON blob ---
pr_json() {
  local isDraft="${1:-false}"
  local checks="${2:-SUCCESS}"
  local nwo="${3:-campusiq/admin_app}"
  local number="${4:-1234}"
  local author="${5:-alice}"
  jq -nc \
    --argjson draft "$isDraft" \
    --arg checks "$checks" \
    --arg nwo "$nwo" \
    --argjson number "$number" \
    --arg author "$author" \
    '{number: $number, title: "Test PR", author: $author,
      repo: "admin_app", nameWithOwner: $nwo,
      isDraft: $draft, checks: $checks}'
}

# Test 1: Ready PR → verdict=ready
OUT=$(pr_json false "SUCCESS" | "$SCRIPT" --comments-file "$FIXTURES/gh-pr-comments-none.json" --viewer jparkypark)
V=$(echo "$OUT" | jq -r '.verdict')
[ "$V" = "ready" ] || { echo "FAIL test1: expected ready, got $V"; exit 1; }
echo "PASS: test1 — ready PR"

# Test 2: Draft PR, no prior comment → verdict=not_ready, commented=false
OUT=$(pr_json true "SUCCESS" | "$SCRIPT" --comments-file "$FIXTURES/gh-pr-comments-none.json" --viewer jparkypark)
V=$(echo "$OUT" | jq -r '.verdict')
C=$(echo "$OUT" | jq -r '.commented')
[ "$V" = "not_ready" ] || { echo "FAIL test2: expected not_ready, got $V"; exit 1; }
[ "$C" = "false" ] || { echo "FAIL test2: expected commented=false, got $C"; exit 1; }
echo "PASS: test2 — draft, no prior comment"

# Test 3: CI failing PR, no prior comment → verdict=not_ready
OUT=$(pr_json false "FAILURE" | "$SCRIPT" --comments-file "$FIXTURES/gh-pr-comments-none.json" --viewer jparkypark)
V=$(echo "$OUT" | jq -r '.verdict')
[ "$V" = "not_ready" ] || { echo "FAIL test3: expected not_ready, got $V"; exit 1; }
R=$(echo "$OUT" | jq -r '.reasons[0]')
[[ "$R" == *"CI"* ]] || { echo "FAIL test3: expected CI reason, got $R"; exit 1; }
echo "PASS: test3 — CI failing, no prior comment"

# Test 4: Draft + CI failing → both reasons listed
OUT=$(pr_json true "FAILURE" | "$SCRIPT" --comments-file "$FIXTURES/gh-pr-comments-none.json" --viewer jparkypark)
RCOUNT=$(echo "$OUT" | jq '.reasons | length')
[ "$RCOUNT" = "2" ] || { echo "FAIL test4: expected 2 reasons, got $RCOUNT"; exit 1; }
echo "PASS: test4 — draft + CI failing"

# Test 5: Draft, already commented, no author reply → verdict=already_flagged
OUT=$(pr_json true "SUCCESS" | "$SCRIPT" --comments-file "$FIXTURES/gh-pr-comments-flagged.json" --viewer jparkypark)
V=$(echo "$OUT" | jq -r '.verdict')
[ "$V" = "already_flagged" ] || { echo "FAIL test5: expected already_flagged, got $V"; exit 1; }
echo "PASS: test5 — already flagged, no reply"

# Test 6: Draft, commented, author replied → verdict=not_ready, author_replied=true
OUT=$(pr_json true "SUCCESS" | "$SCRIPT" --comments-file "$FIXTURES/gh-pr-comments-replied.json" --viewer jparkypark)
V=$(echo "$OUT" | jq -r '.verdict')
AR=$(echo "$OUT" | jq -r '.author_replied')
[ "$V" = "not_ready" ] || { echo "FAIL test6: expected not_ready, got $V"; exit 1; }
[ "$AR" = "true" ] || { echo "FAIL test6: expected author_replied=true, got $AR"; exit 1; }
echo "PASS: test6 — flagged but author replied"

# Test 7: CI PENDING → verdict=not_ready with CI reason
OUT=$(pr_json false "PENDING" | "$SCRIPT" --comments-file "$FIXTURES/gh-pr-comments-none.json" --viewer jparkypark)
V=$(echo "$OUT" | jq -r '.verdict')
[ "$V" = "not_ready" ] || { echo "FAIL test7: expected not_ready, got $V"; exit 1; }
echo "PASS: test7 — CI pending"

# Test 8: Checks field with mixed states including SUCCESS → not_ready
OUT=$(pr_json false "FAILURE,SUCCESS" | "$SCRIPT" --comments-file "$FIXTURES/gh-pr-comments-none.json" --viewer jparkypark)
V=$(echo "$OUT" | jq -r '.verdict')
[ "$V" = "not_ready" ] || { echo "FAIL test8: expected not_ready, got $V"; exit 1; }
echo "PASS: test8 — mixed CI states"

echo "PASS: all test-triage.sh tests"
