#!/usr/bin/env bash
# ensure-clone.sh — report which repos are missing a clone under REVIEW_DIR.
# Reads tab-separated "repo<TAB>nameWithOwner" pairs from stdin.
# Usage:
#   ensure-clone.sh --review-dir <dir> --check-only
#     → prints missing pairs (tab-separated) to stdout, exits 0
#   ensure-clone.sh --review-dir <dir> --clone
#     → clones missing repos via `gh repo clone`
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/derive-owner.sh"

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
  # Key the clone path on nameWithOwner so two repos with the same short
  # name under different owners (e.g. acme/admin_app vs beta/admin_app)
  # don't collide on ~/ws/review/<repo>.
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
done
