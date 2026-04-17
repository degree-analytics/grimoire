#!/usr/bin/env bash
# prep-worktree.sh — idempotently create a worktree for a PR head.
# Usage:
#   prep-worktree.sh --clone <path> --pr <number>
# Output: prints the worktree path on success.
set -euo pipefail

CLONE=""
PR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --clone) CLONE="$2"; shift 2 ;;
    --pr)    PR="$2";    shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$CLONE" ] && [ -n "$PR" ] || { echo "usage: --clone <path> --pr <number>" >&2; exit 2; }

BRANCH="wolfpack-pr$PR"
FETCH_REF="refs/remotes/origin/pr-$PR-head"
WT="$CLONE/.worktrees/pr-$PR"

# Fetch PR head into a temporary ref in the clone
git -C "$CLONE" fetch -q origin "pull/$PR/head:$FETCH_REF" 2>/dev/null \
  || git -C "$CLONE" fetch -q origin "refs/pull/$PR/head:$FETCH_REF"

if [ -d "$WT" ]; then
  # Worktree already exists — update it to the latest PR head
  # Clone-side fetch above already refreshed $FETCH_REF; just reset the worktree
  git -C "$WT" reset --hard -q "$FETCH_REF"
else
  git -C "$CLONE" worktree add -q "$WT" "$FETCH_REF"
fi

echo "$WT"
