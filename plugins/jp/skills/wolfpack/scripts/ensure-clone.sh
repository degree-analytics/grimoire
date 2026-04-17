#!/usr/bin/env bash
# ensure-clone.sh — report which repos are missing a clone under REVIEW_DIR.
# Reads tab-separated "repo<TAB>nameWithOwner" pairs from stdin.
# Usage:
#   ensure-clone.sh --review-dir <dir> --check-only
#     → prints missing pairs (tab-separated) to stdout, exits 0
#   ensure-clone.sh --review-dir <dir> --clone
#     → clones missing repos via `gh repo clone`
set -euo pipefail

REVIEW_DIR=""
MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --review-dir) REVIEW_DIR="$2"; shift 2 ;;
    --check-only) MODE="check"; shift ;;
    --clone)      MODE="clone"; shift ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$REVIEW_DIR" ] || { echo "missing --review-dir" >&2; exit 2; }
[ -n "$MODE" ]       || { echo "missing --check-only or --clone" >&2; exit 2; }
mkdir -p "$REVIEW_DIR"

while IFS=$'\t' read -r repo nwo; do
  [ -z "$repo" ] && continue
  if [ -d "$REVIEW_DIR/$repo" ]; then
    continue
  fi
  if [ "$MODE" = "check" ]; then
    printf '%s\t%s\n' "$repo" "$nwo"
  else
    gh repo clone "$nwo" "$REVIEW_DIR/$repo" >&2
  fi
done
