#!/usr/bin/env bash
# groom.sh — sync review repos, remove wolfpack worktrees for merged/closed PRs,
# and archive their reports.
# Usage:
#   groom.sh --review-dir <dir> --repo-owner <owner> [--all] [--no-sync]
# --all      removes every wolfpack worktree regardless of PR state.
# --no-sync  skips the per-repo sync pass (gt sync / git fetch).
set -euo pipefail

REVIEW_DIR=""
OWNER=""
ALL=0
SYNC=1
while [ $# -gt 0 ]; do
  case "$1" in
    --review-dir) REVIEW_DIR="$2"; shift 2 ;;
    --repo-owner) OWNER="$2";      shift 2 ;;
    --all)        ALL=1;           shift ;;
    --no-sync)    SYNC=0;          shift ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$REVIEW_DIR" ] && [ -n "$OWNER" ] || { echo "usage: --review-dir <dir> --repo-owner <owner> [--all] [--no-sync]" >&2; exit 2; }
[ -d "$REVIEW_DIR" ] || { echo "review dir does not exist: $REVIEW_DIR" >&2; exit 2; }

REMOVED=0; KEPT=0; SYNCED=0
mkdir -p "$REVIEW_DIR/.reports/archive"

# Sync pass: keep every review-dir clone's origin refs fresh before we check
# PR states or derive any other remote-dependent info. Uses Graphite's
# recommended `gt sync -f` when the repo is gt-initialized; falls back to
# `git fetch --all --prune`.
if [ "$SYNC" = "1" ]; then
  echo "Syncing review repos..."
  for clone in "$REVIEW_DIR"/*/; do
    [ -d "$clone/.git" ] || continue
    name=$(basename "$clone")
    if command -v gt >/dev/null 2>&1 && [ -f "$clone/.git/.graphite_repo_config" ]; then
      (cd "$clone" && gt sync -f >/dev/null 2>&1) \
        || git -C "$clone" fetch --all --prune >/dev/null 2>&1 \
        || { echo "  warn: sync failed for $name" >&2; continue; }
    else
      git -C "$clone" fetch --all --prune >/dev/null 2>&1 \
        || { echo "  warn: fetch failed for $name" >&2; continue; }
    fi
    SYNCED=$((SYNCED+1))
    echo "  synced $name"
  done
  echo
fi

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
if [ "$SYNC" = "1" ]; then
  echo "Groom summary: $SYNCED synced, $REMOVED removed, $KEPT kept"
else
  echo "Groom summary: $REMOVED removed, $KEPT kept (sync skipped)"
fi
