#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/detect-pr.sh"
FIXTURES="$HERE/fixtures"
PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $label"
    ((PASS += 1))
  else
    echo "FAIL: $label - expected '$expected', got '$actual'"
    ((FAIL += 1))
  fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@" 2>/dev/null; then
    echo "FAIL: $label - expected failure but succeeded"
    ((FAIL += 1))
  else
    echo "PASS: $label"
    ((PASS += 1))
  fi
}

# Test 1: Both args provided (numeric + word, any order)
OUT=$("$SCRIPT" --test-repo-file "$FIXTURES/gh-repo-view.json" \
                 --test-pr-file "$FIXTURES/gh-pr-view.json" \
                 bifrost 1234)
assert_eq "both args: repo" "degree-analytics/bifrost" "$(echo "$OUT" | jq -r .repo)"
assert_eq "both args: pr" "1234" "$(echo "$OUT" | jq -r .pr)"

# Test 2: Reversed order (1234 bifrost)
OUT=$("$SCRIPT" --test-repo-file "$FIXTURES/gh-repo-view.json" \
                 --test-pr-file "$FIXTURES/gh-pr-view.json" \
                 1234 bifrost)
assert_eq "reversed args: repo" "degree-analytics/bifrost" "$(echo "$OUT" | jq -r .repo)"
assert_eq "reversed args: pr" "1234" "$(echo "$OUT" | jq -r .pr)"

# Test 3: Only PR number, repo auto-detected
OUT=$("$SCRIPT" --test-repo-file "$FIXTURES/gh-repo-view.json" \
                 --test-pr-file "$FIXTURES/gh-pr-view.json" \
                 1234)
assert_eq "pr only: repo auto-detected" "degree-analytics/bifrost" "$(echo "$OUT" | jq -r .repo)"
assert_eq "pr only: pr" "1234" "$(echo "$OUT" | jq -r .pr)"

# Test 4: Only repo name, PR auto-detected
OUT=$("$SCRIPT" --test-repo-file "$FIXTURES/gh-repo-view.json" \
                 --test-pr-file "$FIXTURES/gh-pr-view.json" \
                 bifrost)
assert_eq "repo only: repo" "degree-analytics/bifrost" "$(echo "$OUT" | jq -r .repo)"
assert_eq "repo only: pr auto-detected" "1234" "$(echo "$OUT" | jq -r .pr)"

# Test 5: No args, both auto-detected
OUT=$("$SCRIPT" --test-repo-file "$FIXTURES/gh-repo-view.json" \
                 --test-pr-file "$FIXTURES/gh-pr-view.json")
assert_eq "no args: repo" "degree-analytics/bifrost" "$(echo "$OUT" | jq -r .repo)"
assert_eq "no args: pr" "1234" "$(echo "$OUT" | jq -r .pr)"

# Test 6: Repo name with degree-analytics/ prefix is normalized
OUT=$("$SCRIPT" --test-repo-file "$FIXTURES/gh-repo-view.json" \
                 --test-pr-file "$FIXTURES/gh-pr-view.json" \
                 degree-analytics/bifrost 1234)
assert_eq "full repo name: repo" "degree-analytics/bifrost" "$(echo "$OUT" | jq -r .repo)"

# Test 7: Missing repo detection should fail
assert_fail "no repo file fails" \
  "$SCRIPT" --test-pr-file "$FIXTURES/gh-pr-view.json" \
            --test-repo-file /nonexistent 5678

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
