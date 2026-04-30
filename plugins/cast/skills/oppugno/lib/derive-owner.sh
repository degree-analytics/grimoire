#!/usr/bin/env bash
# derive-owner.sh - given a git clone path, derive owner and repo from origin URL.
# Source this file, then call: derive_owner <clone-path>
# Output on stdout: "owner<TAB>repo"
# Exit 1 if origin URL cannot be parsed.

derive_owner() {
  local clone="$1"
  local url path owner repo

  url=$(git -C "$clone" remote get-url origin 2>/dev/null) || return 1

  # Strip trailing .git and optional slash, then extract owner/repo from:
  #   git@host:owner/repo(.git) or https://host/owner/repo(.git)
  path=$(printf '%s' "$url" | sed -E 's#\.git/?$##; s#.*[:/]([^/:]+)/([^/]+)$#\1/\2#')

  case "$path" in
    */*)
      owner="${path%/*}"
      repo="${path##*/}"
      [ -n "$owner" ] && [ -n "$repo" ] || return 1
      printf '%s\t%s\n' "$owner" "$repo"
      ;;
    *)
      return 1
      ;;
  esac
}
