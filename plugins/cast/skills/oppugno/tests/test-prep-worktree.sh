#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/prep-worktree.sh"

# Create a fake "remote" repo with a "PR branch"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

REMOTE="$TMP/remote.git"
git init --bare "$REMOTE" >/dev/null

WORK="$TMP/work"
git init -q "$WORK"
cd "$WORK"
git config user.email t@t.t && git config user.name t
echo base > f && git add f && git commit -q -m base
git branch -M main
git remote add origin "$REMOTE"
git push -q origin main

# Create a PR branch on the remote (simulate)
git checkout -qb feature-pr
echo change > f && git commit -qam change
git push -q origin feature-pr:refs/pull/42/head
git checkout -q main
git branch -qD feature-pr

# Create a parent PR branch on the remote (stacked-PR base simulation)
git checkout -qb parent-feature
echo parent > pf && git add pf && git commit -qam parent
git push -q origin parent-feature
git checkout -q main
git branch -qD parent-feature

# Clone it under a fake review dir
CLONE="$TMP/review/admin_app"
mkdir -p "$TMP/review"
git clone -q "$REMOTE" "$CLONE"

# Run prep-worktree twice (idempotency test)
"$SCRIPT" --clone "$CLONE" --pr 42
"$SCRIPT" --clone "$CLONE" --pr 42

WT="$CLONE/.worktrees/pr-42"
[ -d "$WT" ] || { echo "FAIL: worktree not created at $WT"; exit 1; }
cd "$WT"
CONTENT=$(cat f)
[ "$CONTENT" = "change" ] || { echo "FAIL: worktree has wrong content: $CONTENT"; exit 1; }
cd "$TMP"

# --base-ref should fetch that branch into origin refs
"$SCRIPT" --clone "$CLONE" --pr 42 --base-ref parent-feature >/dev/null
git -C "$CLONE" rev-parse --verify -q refs/remotes/origin/parent-feature >/dev/null \
  || { echo "FAIL: --base-ref did not fetch parent-feature into origin refs"; exit 1; }

# --base-ref with a nonexistent branch must not fail the command (stacked parent may be gone)
"$SCRIPT" --clone "$CLONE" --pr 42 --base-ref does-not-exist >/dev/null \
  || { echo "FAIL: --base-ref with missing branch should not fail"; exit 1; }

echo "PASS: test-prep-worktree.sh"
