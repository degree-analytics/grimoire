#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/groom.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Review-dir uses nested owner/repo layout. Set up one MERGED and one OPEN
# worktree under campusiq/admin_app, plus a minimal .git dir so sync tries.
REV="$TMP/review"
mkdir -p "$REV/campusiq/admin_app/.worktrees/pr-1234" \
         "$REV/campusiq/admin_app/.worktrees/pr-1237" \
         "$REV/campusiq/admin_app/.git" \
         "$REV/.reports/archive"

# Reports are owner-qualified to prevent cross-owner filename collisions.
: > "$REV/.reports/campusiq__admin_app-pr1234.md"
: > "$REV/.reports/campusiq__admin_app-pr1237.md"

# Stub `gh`, `gt`, `git` on PATH.
#   gh  — returns MERGED for 1234, OPEN for 1237, CLOSED for anything else
#   gt  — records sync invocations; exits 0
#   git — records fetch invocations; delegates everything else to real git
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
REAL_GIT="$(command -v git)"

cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
seen_view=0
num=""
for a in "$@"; do
  if [ "$seen_view" = "1" ]; then num="$a"; break; fi
  [ "$a" = "view" ] && seen_view=1
done
case "$num" in
  1234) echo MERGED ;;
  1237) echo OPEN ;;
  *)    echo CLOSED ;;
esac
STUB
chmod +x "$STUB_BIN/gh"

cat > "$STUB_BIN/gt" <<STUB
#!/usr/bin/env bash
echo "gt \$*" >> "$TMP/gt.log"
exit 0
STUB
chmod +x "$STUB_BIN/gt"

cat > "$STUB_BIN/git" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "-C" ] && [ "\$3" = "fetch" ]; then
  echo "git fetch \$4 \$5" >> "$TMP/git-fetch.log"
  exit 0
fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$STUB_BIN/git"

# Default run: sync + cleanup. No --repo-owner needed — owner comes from path.
PATH="$STUB_BIN:$PATH" "$SCRIPT" --review-dir "$REV"

# 1234 should be gone, 1237 should remain
[ ! -d "$REV/campusiq/admin_app/.worktrees/pr-1234" ] || { echo "FAIL: pr-1234 worktree still present"; exit 1; }
[ -d "$REV/campusiq/admin_app/.worktrees/pr-1237" ]   || { echo "FAIL: pr-1237 worktree removed"; exit 1; }

# Report for 1234 archived under owner-qualified name
[ -f "$REV/.reports/archive/campusiq__admin_app-pr1234.md" ] || { echo "FAIL: report for 1234 not archived"; exit 1; }
[ -f "$REV/.reports/campusiq__admin_app-pr1237.md" ]         || { echo "FAIL: report for 1237 removed"; exit 1; }

# Sync ran on campusiq/admin_app (either gt or git fetch)
{ [ -f "$TMP/gt.log" ] || [ -f "$TMP/git-fetch.log" ]; } \
  || { echo "FAIL: no sync command was invoked"; exit 1; }

# --no-sync skips the sync step
rm -f "$TMP/gt.log" "$TMP/git-fetch.log"
mkdir -p "$REV/campusiq/admin_app/.worktrees/pr-1240"
PATH="$STUB_BIN:$PATH" "$SCRIPT" --review-dir "$REV" --no-sync
[ ! -f "$TMP/gt.log" ] && [ ! -f "$TMP/git-fetch.log" ] \
  || { echo "FAIL: --no-sync still ran sync"; exit 1; }

# Cross-owner groom: a second org with the same short repo name must be
# handled independently and not confused with the first.
mkdir -p "$REV/acme/admin_app/.worktrees/pr-5555" "$REV/acme/admin_app/.git"
: > "$REV/.reports/acme__admin_app-pr5555.md"
PATH="$STUB_BIN:$PATH" "$SCRIPT" --review-dir "$REV" --all --no-sync
[ ! -d "$REV/acme/admin_app/.worktrees/pr-5555" ] \
  || { echo "FAIL: --all did not remove acme/admin_app worktree"; exit 1; }
[ -f "$REV/.reports/archive/acme__admin_app-pr5555.md" ] \
  || { echo "FAIL: acme/admin_app report not archived"; exit 1; }

echo "PASS: test-groom.sh"
