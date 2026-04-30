#!/usr/bin/env bash
# prep-worktree.sh — idempotently create a worktree for a PR head.
# Usage:
#   prep-worktree.sh --clone <path> --pr <number> [--base-ref <branch>]
# --base-ref additionally fetches that branch into origin refs so Wolf can
# diff against it. Used for graphite-stacked PRs whose base is another PR's
# branch. A missing base branch is logged but not fatal.
# Output: prints the worktree path on success.
set -euo pipefail

CLONE=""
PR=""
BASE_REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --clone)    CLONE="$2";    shift 2 ;;
    --pr)       PR="$2";       shift 2 ;;
    --base-ref) BASE_REF="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$CLONE" ] && [ -n "$PR" ] || { echo "usage: --clone <path> --pr <number> [--base-ref <branch>]" >&2; exit 2; }

BRANCH="oppugno-pr$PR"
FETCH_REF="refs/remotes/origin/pr-$PR-head"
WT="$CLONE/.worktrees/pr-$PR"

# Fetch PR head into a temporary ref in the clone
git -C "$CLONE" fetch -q origin "pull/$PR/head:$FETCH_REF" 2>/dev/null \
  || git -C "$CLONE" fetch -q origin "refs/pull/$PR/head:$FETCH_REF"

# If a base ref was given (stacked-PR case), refresh that branch too so
# origin/<base> resolves locally. Non-fatal if the branch is gone upstream.
if [ -n "$BASE_REF" ]; then
  git -C "$CLONE" fetch -q origin "$BASE_REF:refs/remotes/origin/$BASE_REF" 2>/dev/null \
    || echo "warn: could not fetch base ref '$BASE_REF' (parent branch may be deleted)" >&2
fi

if [ -d "$WT" ]; then
  # Worktree already exists — update it to the latest PR head
  # Clone-side fetch above already refreshed $FETCH_REF; just reset the worktree
  git -C "$WT" reset --hard -q "$FETCH_REF"
else
  git -C "$CLONE" worktree add -q "$WT" "$FETCH_REF"
fi

echo "$WT"
