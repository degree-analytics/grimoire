# Wolfpack Hunt Triage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a triage phase to wolfpack hunt that surfaces draft/CI-failing PRs, checks whether we already commented about it, and lets the user decide to skip, comment, or review anyway.

**Architecture:** New `triage.sh` script checks each PR's readiness (draft status + CI) and comment history. SKILL.md gets a new Phase 3.5 ("Triage") between clone verification and PR selection that splits PRs into ready/not-ready buckets and presents actionable options per not-ready PR.

**Tech Stack:** Bash, `gh` CLI, `jq`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `scripts/triage.sh` | Create | Check readiness + comment history for a single PR |
| `tests/test-triage.sh` | Create | Unit tests for triage.sh |
| `tests/fixtures/gh-pr-comments-none.json` | Create | Fixture: no prior comments |
| `tests/fixtures/gh-pr-comments-flagged.json` | Create | Fixture: reviewer already flagged, no author reply |
| `tests/fixtures/gh-pr-comments-replied.json` | Create | Fixture: reviewer flagged, author replied after |
| `SKILL.md` | Modify | Add Phase 3.5 (Triage) between Phase 3 and Phase 4 |
| `scripts/inbox.sh` | No change | Already fetches `isDraft` and `checks` |

---

### Task 1: Create triage.sh script

**Files:**
- Create: `plugins/jp/skills/wolfpack/scripts/triage.sh`
- Create: `plugins/jp/skills/wolfpack/tests/test-triage.sh`
- Create: `plugins/jp/skills/wolfpack/tests/fixtures/gh-pr-comments-none.json`
- Create: `plugins/jp/skills/wolfpack/tests/fixtures/gh-pr-comments-flagged.json`
- Create: `plugins/jp/skills/wolfpack/tests/fixtures/gh-pr-comments-replied.json`

`triage.sh` takes a single PR's JSON (from inbox.sh output) on stdin and outputs a triage verdict. It checks two things:

1. **Readiness:** Is the PR draft or CI-failing?
2. **Comment history:** If not ready, did we already leave a "not ready" comment? Did the author reply after?

- [ ] **Step 1: Create test fixtures**

`tests/fixtures/gh-pr-comments-none.json` — empty comments array:
```json
[]
```

`tests/fixtures/gh-pr-comments-flagged.json` — reviewer flagged, no author reply after:
```json
[
  {
    "author": {"login": "jparkypark"},
    "body": "Holding off on review — CI is failing. Let me know when it's green and I'll take a look.",
    "createdAt": "2026-04-28T10:00:00Z"
  }
]
```

`tests/fixtures/gh-pr-comments-replied.json` — reviewer flagged, author replied:
```json
[
  {
    "author": {"login": "jparkypark"},
    "body": "Holding off on review — this is still in draft. Let me know when it's ready and I'll take a look.",
    "createdAt": "2026-04-28T10:00:00Z"
  },
  {
    "author": {"login": "alice"},
    "body": "Actually can you review now? I want early feedback on the approach.",
    "createdAt": "2026-04-28T14:30:00Z"
  }
]
```

- [ ] **Step 2: Write test-triage.sh**

```bash
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bash plugins/jp/skills/wolfpack/tests/test-triage.sh`
Expected: FAIL — `triage.sh` doesn't exist yet.

- [ ] **Step 4: Write triage.sh**

```bash
#!/usr/bin/env bash
# triage.sh — determine if a PR is ready for review.
# Reads a single PR JSON object from stdin (inbox.sh schema).
# Usage:
#   triage.sh --viewer <gh-login>
#     → live: fetches comments via gh pr view
#   triage.sh --viewer <gh-login> --comments-file <path>
#     → test: reads comments from file
#
# Output: JSON object with verdict and metadata.
#
# Verdicts:
#   ready          — PR is not draft, CI is green (or empty). Review it.
#   not_ready      — PR is draft and/or CI failing. No prior comment, or author replied.
#   already_flagged — We already commented about readiness and author hasn't replied.
#
# Schema:
#   { "verdict", "reasons": [], "commented": bool, "author_replied": bool }
set -euo pipefail

VIEWER=""
COMMENTS_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --viewer)        VIEWER="$2"; shift 2 ;;
    --comments-file) COMMENTS_FILE="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$VIEWER" ] || { echo "missing --viewer" >&2; exit 2; }

PR=$(cat)
IS_DRAFT=$(echo "$PR" | jq -r '.isDraft')
CHECKS=$(echo "$PR" | jq -r '.checks')
NUMBER=$(echo "$PR" | jq -r '.number')
NWO=$(echo "$PR" | jq -r '.nameWithOwner')
PR_AUTHOR=$(echo "$PR" | jq -r '.author')

# --- Step 1: Check readiness ---
REASONS='[]'
if [ "$IS_DRAFT" = "true" ]; then
  REASONS=$(echo "$REASONS" | jq '. + ["PR is still in draft"]')
fi

# checks is a comma-joined string of unique states from statusCheckRollup.
# "SUCCESS" or "" (no checks) = green. Anything else = not green.
if [ -n "$CHECKS" ] && [ "$CHECKS" != "SUCCESS" ]; then
  REASONS=$(echo "$REASONS" | jq '. + ["CI is not green ('"$CHECKS"')"]')
fi

REASON_COUNT=$(echo "$REASONS" | jq 'length')
if [ "$REASON_COUNT" = "0" ]; then
  jq -nc '{verdict: "ready", reasons: [], commented: false, author_replied: false}'
  exit 0
fi

# --- Step 2: Check comment history ---
if [ -n "$COMMENTS_FILE" ]; then
  COMMENTS=$(cat "$COMMENTS_FILE")
else
  COMMENTS=$(gh pr view "$NUMBER" --repo "$NWO" --json comments --jq '.comments' 2>/dev/null || echo '[]')
fi

# Find the most recent comment from us (the reviewer/viewer)
LAST_VIEWER_IDX=$(echo "$COMMENTS" | jq --arg v "$VIEWER" '
  [to_entries[] | select(.value.author.login == $v)] | last | .key // -1
')

if [ "$LAST_VIEWER_IDX" = "-1" ] || [ "$LAST_VIEWER_IDX" = "null" ]; then
  # Never commented
  echo "$REASONS" | jq -c '{verdict: "not_ready", reasons: ., commented: false, author_replied: false}'
  exit 0
fi

# Check if the PR author replied after our last comment
AUTHOR_REPLIED=$(echo "$COMMENTS" | jq --arg v "$VIEWER" --arg a "$PR_AUTHOR" --argjson idx "$LAST_VIEWER_IDX" '
  [to_entries[] | select(.key > $idx and .value.author.login == $a)] | length > 0
')

if [ "$AUTHOR_REPLIED" = "true" ]; then
  echo "$REASONS" | jq -c '{verdict: "not_ready", reasons: ., commented: true, author_replied: true}'
else
  echo "$REASONS" | jq -c '{verdict: "already_flagged", reasons: ., commented: true, author_replied: false}'
fi
```

- [ ] **Step 5: Make triage.sh executable and run tests**

Run: `chmod +x plugins/jp/skills/wolfpack/scripts/triage.sh && bash plugins/jp/skills/wolfpack/tests/test-triage.sh`
Expected: `PASS: all test-triage.sh tests`

- [ ] **Step 6: Commit**

```bash
git add plugins/jp/skills/wolfpack/scripts/triage.sh \
       plugins/jp/skills/wolfpack/tests/test-triage.sh \
       plugins/jp/skills/wolfpack/tests/fixtures/gh-pr-comments-none.json \
       plugins/jp/skills/wolfpack/tests/fixtures/gh-pr-comments-flagged.json \
       plugins/jp/skills/wolfpack/tests/fixtures/gh-pr-comments-replied.json
git commit -m "feat: add triage.sh for PR readiness and comment history checks"
```

---

### Task 2: Update SKILL.md with Phase 3.5 (Triage)

**Files:**
- Modify: `plugins/jp/skills/wolfpack/SKILL.md:66-89` (between Phase 3 and Phase 4)

- [ ] **Step 1: Insert Phase 3.5 after Phase 3 in SKILL.md**

Add the following section between the existing Phase 3 (Verify clones) and Phase 4 (PR selection). Renumber Phase 4 → Phase 5, Phase 5 → Phase 6, Phase 6 → Phase 7.

New Phase 4 content:

````markdown
### Phase 4: Triage

Determine which PRs are actually ready for review. For each PR in `$INBOX`, run triage:

```bash
VIEWER=$(gh api user --jq .login)
TRIAGE_RESULTS=""
while read -r pr_json; do
  result=$(echo "$pr_json" | ${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/scripts/triage.sh --viewer "$VIEWER")
  TRIAGE_RESULTS="${TRIAGE_RESULTS}${result}"$'\n'
done < <(echo "$INBOX" | jq -c '.[]')
```

Split PRs into three buckets based on `verdict`:

- **ready** — eligible for review, pass through to selection.
- **not_ready** — draft or CI failing, and we haven't commented yet (or author replied to our comment asking for review anyway).
- **already_flagged** — we already left a comment and author hasn't replied. Auto-skip these.

If there are **already_flagged** PRs, print a summary line:

```
Skipping N PRs (already flagged as not ready, no author response):
  - #1234 campusiq/admin_app — "WIP: new auth flow" (draft)
  - #567  campusiq/bifrost   — "Add metrics" (CI: FAILURE)
```

If there are **not_ready** PRs, present each one via **AskUserQuestion** (one question per PR, or batched if ≤3):

```
PR #892 campusiq/bifrost — "WIP: new auth flow"
Status: draft
```

Options:
- **"Leave a comment and skip"** — post a comment via `gh pr comment <n> --repo <nwo> --body "..."` using a polite template (see below) and remove from the selection pool.
- **"Review anyway"** — keep it in the selection pool despite not being ready.
- **"Skip silently"** — remove from selection pool without commenting.

For PRs where `author_replied` is true, amend the question to note:

```
PR #892 campusiq/bifrost — "WIP: new auth flow"
Status: draft
Note: Author replied after your last comment — they may want early feedback.
```

**Comment templates** (choose based on reasons):

Draft only:
> Holding off on review — this is still in draft. Let me know when it's ready and I'll take a look.

CI failing only:
> Holding off on review — CI is failing. Let me know when it's green and I'll take a look.

Both:
> Holding off on review — this is still in draft and CI is failing. Let me know when both are resolved and I'll take a look.

After triage, replace `$INBOX` with only the PRs that passed through (ready + "review anyway" selections). If no PRs remain, print:

```
no review-ready PRs after triage — nothing to hunt
```

...and stop.
````

- [ ] **Step 2: Renumber existing phases**

In the existing SKILL.md:
- Phase 4 (PR selection) → Phase 5
- Phase 5 (Dispatch subagents) → Phase 6
- Phase 6 (Collect and render) → Phase 7

Update all references. The consolidated table in Phase 7 remains unchanged.

- [ ] **Step 3: Verify SKILL.md is coherent**

Read through the full SKILL.md to confirm:
- Phase numbering is sequential (1–7)
- No dangling references to old phase numbers
- The `$INBOX` variable flows correctly through Triage into Selection

- [ ] **Step 4: Commit**

```bash
git add plugins/jp/skills/wolfpack/SKILL.md
git commit -m "feat: add triage phase to wolfpack hunt for draft/CI/comment awareness"
```

---

### Task 3: Update test fixture and inbox tests for triage integration

**Files:**
- Modify: `plugins/jp/skills/wolfpack/tests/fixtures/gh-search-prs.json`
- Modify: `plugins/jp/skills/wolfpack/tests/test-inbox.sh`

The existing fixture has a draft PR (`#892`) and a PENDING PR (`#1237`). Verify that inbox.sh outputs the `isDraft` and `checks` fields correctly so triage.sh can consume them.

- [ ] **Step 1: Add assertions to test-inbox.sh for isDraft and checks fields**

Append to `tests/test-inbox.sh` before the final `echo "PASS"`:

```bash
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
```

- [ ] **Step 2: Run the updated test**

Run: `bash plugins/jp/skills/wolfpack/tests/test-inbox.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add plugins/jp/skills/wolfpack/tests/test-inbox.sh
git commit -m "test: add isDraft and checks assertions to inbox tests"
```

---

### Task 4: End-to-end manual verification

No files changed — this is a verification task.

- [ ] **Step 1: Run all wolfpack tests**

Run: `for t in plugins/jp/skills/wolfpack/tests/test-*.sh; do echo "--- $t ---"; bash "$t" || exit 1; done`
Expected: All tests PASS.

- [ ] **Step 2: Dry-run the triage script against live data**

Run a quick manual check that `triage.sh` works against a real PR (pick one from your inbox):

```bash
VIEWER=$(gh api user --jq .login)
gh search prs --review-requested=@me --state=open --json number,title,author,repository --limit 1 \
  | jq -c '.[0] | {number, title, author: .author.login, repo: .repository.name, nameWithOwner: .repository.nameWithOwner, isDraft: false, checks: "SUCCESS"}' \
  | plugins/jp/skills/wolfpack/scripts/triage.sh --viewer "$VIEWER"
```

Verify output is valid JSON with a `verdict` field.

- [ ] **Step 3: Commit (no changes — verification only)**

No commit needed. Verification complete.
