#!/usr/bin/env bash
# groom.sh — sync review repos, remove wolfpack worktrees for merged/closed PRs,
# and archive their reports.
# Usage:
#   groom.sh --review-dir <dir> [--all] [--no-sync]
# --all      removes every wolfpack worktree regardless of PR state.
# --no-sync  skips the per-repo sync pass (gt sync / git fetch).
#
# Review-dir layout: $REVIEW_DIR/<owner>/<repo>/.worktrees/pr-<n>
# Report layout:    $REVIEW_DIR/.reports/<owner>__<repo>-pr<n>.md
set -euo pipefail

REVIEW_DIR=""
ALL=0
SYNC=1
while [ $# -gt 0 ]; do
  case "$1" in
    --review-dir) REVIEW_DIR="$2"; shift 2 ;;
    --all)        ALL=1;           shift ;;
    --no-sync)    SYNC=0;          shift ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$REVIEW_DIR" ] || { echo "usage: --review-dir <dir> [--all] [--no-sync]" >&2; exit 2; }
[ -d "$REVIEW_DIR" ] || { echo "review dir does not exist: $REVIEW_DIR" >&2; exit 2; }

REMOVED=0; KEPT=0; SYNCED=0
mkdir -p "$REVIEW_DIR/.reports/archive"

# Sync pass: keep every clone's origin refs fresh before checking PR states.
# Uses `gt sync -f` when the repo is gt-initialized; falls back to `git fetch
# --all --prune`.
if [ "$SYNC" = "1" ]; then
  echo "Syncing review repos..."
  shopt -s nullglob
  for clone in "$REVIEW_DIR"/*/*/; do
    [ -d "$clone/.git" ] || continue
    owner=$(basename "$(dirname "$clone")")
    repo=$(basename "$clone")
    label="$owner/$repo"
    if command -v gt >/dev/null 2>&1 && [ -f "$clone/.git/.graphite_repo_config" ]; then
      (cd "$clone" && gt sync -f >/dev/null 2>&1) \
        || git -C "$clone" fetch --all --prune >/dev/null 2>&1 \
        || { echo "  warn: sync failed for $label" >&2; continue; }
    else
      git -C "$clone" fetch --all --prune >/dev/null 2>&1 \
        || { echo "  warn: fetch failed for $label" >&2; continue; }
    fi
    SYNCED=$((SYNCED+1))
    echo "  synced $label"
  done
  shopt -u nullglob
  echo
fi

shopt -s nullglob
for wt in "$REVIEW_DIR"/*/*/.worktrees/pr-*; do
  [ -d "$wt" ] || continue
  parent=$(dirname "$(dirname "$wt")")       # $REVIEW_DIR/<owner>/<repo>
  repo=$(basename "$parent")
  owner=$(basename "$(dirname "$parent")")
  pr=$(basename "$wt" | sed 's/^pr-//')
  label="$owner/$repo#$pr"

  if [ "$ALL" = "1" ]; then
    state="FORCE"
  else
    state=$(gh pr view "$pr" --repo "$owner/$repo" --json state -q .state 2>/dev/null || echo UNKNOWN)
  fi

  case "$state" in
    MERGED|CLOSED|FORCE)
      git -C "$parent" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
      report="$REVIEW_DIR/.reports/${owner}__${repo}-pr${pr}.md"
      summary="$REVIEW_DIR/.reports/${owner}__${repo}-pr${pr}.summary.json"
      [ -f "$report"  ] && mv "$report"  "$REVIEW_DIR/.reports/archive/"
      [ -f "$summary" ] && mv "$summary" "$REVIEW_DIR/.reports/archive/"
      REMOVED=$((REMOVED+1))
      echo "removed $label ($state)"
      ;;
    *)
      KEPT=$((KEPT+1))
      echo "kept    $label ($state)"
      ;;
  esac
done
shopt -u nullglob

# Prune any lingering worktree metadata in each repo clone
shopt -s nullglob
for clone in "$REVIEW_DIR"/*/*/; do
  [ -d "$clone/.git" ] && git -C "$clone" worktree prune 2>/dev/null || true
done
shopt -u nullglob

echo
if [ "$SYNC" = "1" ]; then
  echo "Groom summary: $SYNCED synced, $REMOVED removed, $KEPT kept"
else
  echo "Groom summary: $REMOVED removed, $KEPT kept (sync skipped)"
fi
