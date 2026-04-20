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

# Discover clones in both layouts:
#   nested: $REVIEW_DIR/<owner>/<repo>/.git
#   flat:   $REVIEW_DIR/<repo>/.git   (owner derived from `origin` URL)
# Entries are "path|owner|repo".
CLONES=()
shopt -s nullglob
for clone in "$REVIEW_DIR"/*/*/; do
  [ -d "${clone}.git" ] || continue
  _owner=$(basename "$(dirname "$clone")")
  _repo=$(basename "$clone")
  CLONES+=("${clone%/}|$_owner|$_repo")
done
for clone in "$REVIEW_DIR"/*/; do
  [ -d "${clone}.git" ] || continue
  _url=$(git -C "$clone" remote get-url origin 2>/dev/null) || continue
  # Extract owner/repo from git@host:owner/repo(.git) or https://host/owner/repo(.git)
  _path=$(printf '%s' "$_url" | sed -E 's#\.git/?$##; s#.*[:/]([^/:]+)/([^/]+)$#\1/\2#')
  case "$_path" in
    */*) _owner="${_path%/*}"; _repo="${_path##*/}" ;;
    *)   continue ;;
  esac
  [ -n "$_owner" ] && [ -n "$_repo" ] || continue
  CLONES+=("${clone%/}|$_owner|$_repo")
done
shopt -u nullglob

# Sync pass: keep every clone's origin refs fresh before checking PR states.
# Uses `gt sync -f` when the repo is gt-initialized; falls back to `git fetch
# --all --prune`.
if [ "$SYNC" = "1" ]; then
  echo "Syncing review repos..."
  for entry in "${CLONES[@]}"; do
    IFS='|' read -r clone owner repo <<< "$entry"
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
  echo
fi

shopt -s nullglob
for entry in "${CLONES[@]}"; do
  IFS='|' read -r clone owner repo <<< "$entry"
  for wt in "$clone"/.worktrees/pr-*; do
    [ -d "$wt" ] || continue
    pr=$(basename "$wt" | sed 's/^pr-//')
    label="$owner/$repo#$pr"

    if [ "$ALL" = "1" ]; then
      state="FORCE"
    else
      state=$(gh pr view "$pr" --repo "$owner/$repo" --json state -q .state 2>/dev/null || echo UNKNOWN)
    fi

    case "$state" in
      MERGED|CLOSED|FORCE)
        git -C "$clone" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
        report="$REVIEW_DIR/.reports/${owner}__${repo}-pr${pr}.md"
        summary="$REVIEW_DIR/.reports/${owner}__${repo}-pr${pr}.summary.json"
        [ -f "$report"  ] && mv "$report"  "$REVIEW_DIR/.reports/archive/"
        [ -f "$summary" ] && mv "$summary" "$REVIEW_DIR/.reports/archive/"
        # Pre-migration flat-layout clones used <repo>-pr<n> (no owner prefix).
        # Archive those too so groom doesn't leave stale reports behind.
        legacy_report="$REVIEW_DIR/.reports/${repo}-pr${pr}.md"
        legacy_summary="$REVIEW_DIR/.reports/${repo}-pr${pr}.summary.json"
        [ -f "$legacy_report"  ] && mv "$legacy_report"  "$REVIEW_DIR/.reports/archive/"
        [ -f "$legacy_summary" ] && mv "$legacy_summary" "$REVIEW_DIR/.reports/archive/"
        REMOVED=$((REMOVED+1))
        echo "removed $label ($state)"
        ;;
      *)
        KEPT=$((KEPT+1))
        echo "kept    $label ($state)"
        ;;
    esac
  done
done
shopt -u nullglob

# Prune any lingering worktree metadata in each repo clone
for entry in "${CLONES[@]}"; do
  IFS='|' read -r clone _ _ <<< "$entry"
  git -C "$clone" worktree prune 2>/dev/null || true
done

echo
if [ "$SYNC" = "1" ]; then
  echo "Groom summary: $SYNCED synced, $REMOVED removed, $KEPT kept"
else
  echo "Groom summary: $REMOVED removed, $KEPT kept (sync skipped)"
fi
