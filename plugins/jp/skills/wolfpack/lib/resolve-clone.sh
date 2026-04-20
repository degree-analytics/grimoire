#!/usr/bin/env bash
# resolve-clone.sh - given a review dir and nameWithOwner, find the actual clone path.
# Source this file, then call: resolve_clone_path <review_dir> <nwo>
# Output on stdout: the absolute clone path (nested or flat layout).
# Exit 1 if no matching clone is found.

# Depends on derive-owner.sh being sourced in the same shell.
if ! command -v derive_owner >/dev/null 2>&1; then
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/derive-owner.sh"
fi

resolve_clone_path() {
  local review_dir="$1" nwo="$2"
  local repo="${nwo##*/}"

  # Nested layout (preferred): $review_dir/<owner>/<repo>/.git
  if [ -d "$review_dir/$nwo/.git" ]; then
    echo "$review_dir/$nwo"
    return 0
  fi

  # Flat layout: $review_dir/<repo>/.git with origin URL matching nwo
  if [ -d "$review_dir/$repo/.git" ]; then
    local flat_nwo="" _fo _fr
    if IFS=$'\t' read -r _fo _fr < <(derive_owner "$review_dir/$repo"); then
      flat_nwo="$_fo/$_fr"
    fi
    if [ "$flat_nwo" = "$nwo" ]; then
      echo "$review_dir/$repo"
      return 0
    fi
  fi

  return 1
}
