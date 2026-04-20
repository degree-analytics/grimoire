# Wolfpack Layout Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all wolfpack scripts reliably handle both nested (`<owner>/<repo>/`) and flat (`<repo>/`) clone layouts, emit diagnostics when neither layout matches, and document the dual-layout contract.

**Architecture:** Extract the URL-to-owner parse logic into a shared `lib/derive-owner.sh` helper sourced by both `groom.sh` and `ensure-clone.sh`. Add a fail-loud diagnostic to `groom.sh` for empty CLONES with non-empty review dirs. Update SKILL.md assumptions.

**Tech Stack:** Bash, jq, git, gh CLI

**Source root:** `/Users/jp/ws/x/grimoire/plugins/jp/skills/wolfpack`

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/derive-owner.sh` | Shared helper: given a git clone path, derive `owner\trepo` from origin URL |
| Modify | `scripts/groom.sh` | Source shared helper, add fail-loud diagnostic after CLONES[] build |
| Modify | `scripts/ensure-clone.sh` | Source shared helper, recognize flat clones in --check-only mode |
| Modify | `SKILL.md` | Document "nested preferred, flat accepted" in Assumptions |
| Create | `tests/test-derive-owner.sh` | Unit tests for the shared helper |
| Modify | `tests/test-groom.sh` | Add test case for empty CLONES with unrecognized subdirs |
| Modify | `tests/test-ensure-clone.sh` | Add test case for flat clone recognized by origin URL |

---

### Task 1: Create shared `lib/derive-owner.sh` helper

**Files:**
- Create: `lib/derive-owner.sh`
- Create: `tests/test-derive-owner.sh`

This extracts the URL-parse logic currently inline in `groom.sh:44-50` into a reusable function.

- [ ] **Step 1: Write the test for derive-owner.sh**

```bash
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
[ "$OUT" = $'campusiq\tadmin_app' ] || { echo "FAIL: SSH URL → got '$OUT'"; exit 1; }

# Set up a repo with an HTTPS origin
mkdir -p "$TMP/https_repo"
"$REAL_GIT" -C "$TMP/https_repo" init -q
"$REAL_GIT" -C "$TMP/https_repo" remote add origin https://github.com/acme/bifrost.git

OUT2=$(derive_owner "$TMP/https_repo")
[ "$OUT2" = $'acme\tbifrost' ] || { echo "FAIL: HTTPS URL → got '$OUT2'"; exit 1; }

# HTTPS without .git suffix
mkdir -p "$TMP/no_suffix"
"$REAL_GIT" -C "$TMP/no_suffix" init -q
"$REAL_GIT" -C "$TMP/no_suffix" remote add origin https://github.com/org/repo

OUT3=$(derive_owner "$TMP/no_suffix")
[ "$OUT3" = $'org\trepo' ] || { echo "FAIL: HTTPS no .git → got '$OUT3'"; exit 1; }

# No origin remote → exit 1
mkdir -p "$TMP/no_remote"
"$REAL_GIT" -C "$TMP/no_remote" init -q
if derive_owner "$TMP/no_remote" 2>/dev/null; then
  echo "FAIL: expected failure for repo with no origin"
  exit 1
fi

# Not a git repo → exit 1
mkdir -p "$TMP/not_git"
if derive_owner "$TMP/not_git" 2>/dev/null; then
  echo "FAIL: expected failure for non-git directory"
  exit 1
fi

echo "PASS: test-derive-owner.sh"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-derive-owner.sh`
Expected: FAIL — `lib/derive-owner.sh` does not exist yet.

- [ ] **Step 3: Implement derive-owner.sh**

```bash
#!/usr/bin/env bash
# derive-owner.sh — given a git clone path, derive owner and repo from origin URL.
# Source this file, then call: derive_owner <clone-path>
# Output on stdout: "owner<TAB>repo"
# Exit 1 if origin URL cannot be parsed.

derive_owner() {
  local clone="$1"
  local url
  url=$(git -C "$clone" remote get-url origin 2>/dev/null) || return 1
  # Strip trailing .git and optional slash, extract owner/repo from:
  #   git@host:owner/repo(.git)  or  https://host/owner/repo(.git)
  local path
  path=$(printf '%s' "$url" | sed -E 's#\.git/?$##; s#.*[:/]([^/:]+)/([^/]+)$#\1/\2#')
  case "$path" in
    */*)
      local owner="${path%/*}"
      local repo="${path##*/}"
      [ -n "$owner" ] && [ -n "$repo" ] || return 1
      printf '%s\t%s\n' "$owner" "$repo"
      ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-derive-owner.sh`
Expected: `PASS: test-derive-owner.sh`

- [ ] **Step 5: Commit**

```bash
git add lib/derive-owner.sh tests/test-derive-owner.sh
git commit -m "feat(wolfpack): extract derive-owner helper from groom URL-parse logic"
```

---

### Task 2: Add fail-loud diagnostic to groom.sh (Item A)

**Files:**
- Modify: `scripts/groom.sh:54` (after CLONES[] build, before sync pass)
- Modify: `tests/test-groom.sh` (add unrecognized-subdir test case)

- [ ] **Step 1: Write the failing test**

Append this test case to the end of `tests/test-groom.sh` (before the final PASS line):

```bash
# Fail-loud diagnostic: review dir has subdirs but none are git clones.
# Groom should warn about unrecognized entries instead of silently reporting 0/0/0.
UNRECOG="$TMP/unrecog_review"
mkdir -p "$UNRECOG/not_a_repo/subdir" "$UNRECOG/also_not_a_repo" "$UNRECOG/.reports/archive"
OUT=$(PATH="$STUB_BIN:$PATH" "$SCRIPT" --review-dir "$UNRECOG" --no-sync 2>&1)
echo "$OUT" | grep -q "but none look like git clones" \
  || { echo "FAIL: no diagnostic for unrecognized subdirs"; echo "got: $OUT"; exit 1; }
# Should still exit 0 — informational, not a failure
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-groom.sh`
Expected: FAIL — groom.sh does not yet emit the diagnostic.

- [ ] **Step 3: Implement the diagnostic in groom.sh**

After line 54 (`shopt -u nullglob`), insert:

```bash
# Fail-loud diagnostic: if REVIEW_DIR has subdirs but none matched as clones,
# warn so layout mismatches don't silently produce 0/0/0 output.
if [ ${#CLONES[@]} -eq 0 ]; then
  shopt -s nullglob
  _subdirs=("$REVIEW_DIR"/*/)
  shopt -u nullglob
  if [ ${#_subdirs[@]} -gt 0 ]; then
    _samples=()
    for _d in "${_subdirs[@]:0:3}"; do
      _samples+=("$(basename "${_d%/}")")
    done
    echo "warn: found ${#_subdirs[@]} directories under $REVIEW_DIR but none look like git clones; expected <owner>/<repo>/.git or <repo>/.git (first: ${_samples[*]})" >&2
  fi
fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-groom.sh`
Expected: `PASS: test-groom.sh`

- [ ] **Step 5: Commit**

```bash
git add scripts/groom.sh tests/test-groom.sh
git commit -m "feat(wolfpack): emit diagnostic when groom finds no clones in non-empty review dir"
```

---

### Task 3: Refactor groom.sh to use shared derive-owner helper

**Files:**
- Modify: `scripts/groom.sh:42-53` (flat-layout discovery loop)

Replace the inline URL-parse logic in the flat-layout discovery loop with a call to `derive_owner`.

- [ ] **Step 1: Run existing tests to confirm green baseline**

Run: `bash tests/test-groom.sh`
Expected: `PASS: test-groom.sh`

- [ ] **Step 2: Refactor groom.sh flat-layout loop**

At the top of `groom.sh`, after `set -euo pipefail` (line 11), add:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/derive-owner.sh"
```

Then replace lines 42-53 (the flat-layout discovery loop) with:

```bash
for clone in "$REVIEW_DIR"/*/; do
  [ -d "${clone}.git" ] || continue
  IFS=$'\t' read -r _owner _repo < <(derive_owner "${clone%/}") || continue
  [ -n "$_owner" ] && [ -n "$_repo" ] || continue
  CLONES+=("${clone%/}|$_owner|$_repo")
done
```

- [ ] **Step 3: Run tests to verify refactor is behavior-preserving**

Run: `bash tests/test-groom.sh`
Expected: `PASS: test-groom.sh`

- [ ] **Step 4: Commit**

```bash
git add scripts/groom.sh
git commit -m "refactor(wolfpack): use shared derive-owner helper in groom flat-layout discovery"
```

---

### Task 4: Fix ensure-clone.sh to recognize flat clones (Item B)

**Files:**
- Modify: `scripts/ensure-clone.sh:25-42`
- Modify: `tests/test-ensure-clone.sh`

- [ ] **Step 1: Write the failing test**

Append this test case to the end of `tests/test-ensure-clone.sh` (before the final PASS line):

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-ensure-clone.sh`
Expected: FAIL — ensure-clone.sh does not check flat clones yet.

- [ ] **Step 3: Implement flat-clone recognition in ensure-clone.sh**

At the top of `ensure-clone.sh`, after `set -euo pipefail` (line 9), add:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/derive-owner.sh"
```

Replace the inner logic of the `while` loop (lines 30-41) with:

```bash
  # Check nested layout first (preferred)
  if [ -d "$REVIEW_DIR/$nwo" ]; then
    continue
  fi
  # Check flat layout: $REVIEW_DIR/<repo>/ with origin URL matching nwo
  if [ -d "$REVIEW_DIR/$repo/.git" ]; then
    flat_nwo=""
    if IFS=$'\t' read -r _fo _fr < <(derive_owner "$REVIEW_DIR/$repo"); then
      flat_nwo="$_fo/$_fr"
    fi
    if [ "$flat_nwo" = "$nwo" ]; then
      continue
    fi
  fi
  if [ "$MODE" = "check" ]; then
    printf '%s\t%s\n' "$repo" "$nwo"
  else
    mkdir -p "$(dirname "$REVIEW_DIR/$nwo")"
    gh repo clone "$nwo" "$REVIEW_DIR/$nwo" >&2
  fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-ensure-clone.sh`
Expected: `PASS: test-ensure-clone.sh`

- [ ] **Step 5: Run all tests to verify no regressions**

Run: `for t in tests/test-*.sh; do echo "--- $t ---"; bash "$t"; done`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/ensure-clone.sh tests/test-ensure-clone.sh
git commit -m "feat(wolfpack): recognize flat-layout clones in ensure-clone --check-only"
```

---

### Task 5: Update SKILL.md to document dual-layout support (Item C)

**Files:**
- Modify: `SKILL.md:33-34`

- [ ] **Step 1: Update the Assumptions section**

Replace line 34:
```
- Clone layout: `~/ws/review/<owner>/<repo>/` (nested so same-name repos across orgs don't collide)
```

With:
```
- Clone layout: nested `~/ws/review/<owner>/<repo>/` (preferred; prevents same-name collisions across orgs). Flat `~/ws/review/<repo>/` is also accepted — owner is derived from the clone's `origin` URL. Hunt creates new clones in nested layout only.
```

- [ ] **Step 2: Verify the doc reads correctly**

Read the updated SKILL.md and confirm the Assumptions section flows naturally.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "docs(wolfpack): document nested-preferred, flat-accepted clone layout"
```

---

### Task 6: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `cd /Users/jp/ws/x/grimoire/plugins/jp/skills/wolfpack && for t in tests/test-*.sh; do echo "--- $t ---"; bash "$t"; done`
Expected: All PASS.

- [ ] **Step 2: Review diff for PR scope**

Run: `git diff main --stat` and `git log main..HEAD --oneline`
Expected: ~80 LOC across 7 files, 5 commits, coherent "layout parity" narrative.
