#!/usr/bin/env bash
# groom.sh — remove wolfpack worktrees for merged/closed PRs; archive their reports.
# Usage:
#   groom.sh --review-dir <dir> --repo-owner <owner> [--all]
# --all removes every wolfpack worktree regardless of PR state.
set -euo pipefail

REVIEW_DIR=""
OWNER=""
ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --review-dir) REVIEW_DIR="$2"; shift 2 ;;
    --repo-owner) OWNER="$2";      shift 2 ;;
    --all)        ALL=1;           shift ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$REVIEW_DIR" ] && [ -n "$OWNER" ] || { echo "usage: --review-dir <dir> --repo-owner <owner>" >&2; exit 2; }
[ -d "$REVIEW_DIR" ] || { echo "review dir does not exist: $REVIEW_DIR" >&2; exit 2; }

REMOVED=0; KEPT=0
mkdir -p "$REVIEW_DIR/.reports/archive"

shopt -s nullglob
for wt in "$REVIEW_DIR"/*/.worktrees/pr-*; do
  [ -d "$wt" ] || continue
  repo=$(basename "$(dirname "$(dirname "$wt")")")
  pr=$(basename "$wt" | sed 's/^pr-//')

  if [ "$ALL" = "1" ]; then
    state="FORCE"
  else
    state=$(gh pr view "$pr" --repo "$OWNER/$repo" --json state -q .state 2>/dev/null || echo UNKNOWN)
  fi

  case "$state" in
    MERGED|CLOSED|FORCE)
      # Remove the worktree
      parent=$(dirname "$(dirname "$wt")")  # ~/ws/review/<repo>
      git -C "$parent" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
      # Archive the report, if any
      report="$REVIEW_DIR/.reports/${repo}-pr${pr}.md"
      summary="$REVIEW_DIR/.reports/${repo}-pr${pr}.summary.json"
      [ -f "$report"  ] && mv "$report"  "$REVIEW_DIR/.reports/archive/"
      [ -f "$summary" ] && mv "$summary" "$REVIEW_DIR/.reports/archive/"
      REMOVED=$((REMOVED+1))
      echo "removed $repo#$pr ($state)"
      ;;
    *)
      KEPT=$((KEPT+1))
      echo "kept    $repo#$pr ($state)"
      ;;
  esac
done
shopt -u nullglob

# Prune any lingering worktree metadata in each repo clone
for clone in "$REVIEW_DIR"/*/; do
  [ -d "$clone/.git" ] && git -C "$clone" worktree prune 2>/dev/null || true
done

echo
echo "Groom summary: $REMOVED removed, $KEPT kept"
