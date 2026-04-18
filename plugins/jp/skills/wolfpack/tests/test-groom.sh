#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/groom.sh"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Set up review-dir with two fake worktrees, one MERGED, one OPEN.
# Also create a minimal .git dir on the clone so the sync step tries to run.
REV="$TMP/review"
mkdir -p "$REV/admin_app/.worktrees/pr-1234" "$REV/admin_app/.worktrees/pr-1237"
mkdir -p "$REV/.reports/archive"
mkdir -p "$REV/admin_app/.git"
: > "$REV/.reports/admin_app-pr1234.md"
: > "$REV/.reports/admin_app-pr1237.md"

# Create stub `gh`, `gt`, `git` on PATH.
#   gh   — returns MERGED for 1234, OPEN for 1237
#   gt   — records sync invocations; exits 0
#   git  — records fetch invocations; for any other subcommand, exec real git
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
# Record the invocation so the test can assert sync ran.
echo "gt \$*" >> "$TMP/gt.log"
exit 0
STUB
chmod +x "$STUB_BIN/gt"

cat > "$STUB_BIN/git" <<STUB
#!/usr/bin/env bash
# Record fetch invocations; delegate everything else to the real git.
if [ "\$1" = "-C" ] && [ "\$3" = "fetch" ]; then
  echo "git fetch \$4 \$5" >> "$TMP/git-fetch.log"
  exit 0
fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$STUB_BIN/git"

# Default run: sync + cleanup
PATH="$STUB_BIN:$PATH" "$SCRIPT" --review-dir "$REV" --repo-owner campusiq

# 1234 should be gone, 1237 should remain
[ ! -d "$REV/admin_app/.worktrees/pr-1234" ] || { echo "FAIL: pr-1234 worktree still present"; exit 1; }
[ -d "$REV/admin_app/.worktrees/pr-1237" ]   || { echo "FAIL: pr-1237 worktree removed"; exit 1; }

# Report for 1234 should be archived
[ -f "$REV/.reports/archive/admin_app-pr1234.md" ] || { echo "FAIL: report for 1234 not archived"; exit 1; }
[ -f "$REV/.reports/admin_app-pr1237.md" ]         || { echo "FAIL: report for 1237 removed"; exit 1; }

# Sync should have run on admin_app (gt or git fetch)
{ [ -f "$TMP/gt.log" ] || [ -f "$TMP/git-fetch.log" ]; } \
  || { echo "FAIL: no sync command was invoked"; exit 1; }

# --no-sync should skip the sync step
rm -f "$TMP/gt.log" "$TMP/git-fetch.log"
mkdir -p "$REV/admin_app/.worktrees/pr-1240"
PATH="$STUB_BIN:$PATH" "$SCRIPT" --review-dir "$REV" --repo-owner campusiq --no-sync
[ ! -f "$TMP/gt.log" ] && [ ! -f "$TMP/git-fetch.log" ] \
  || { echo "FAIL: --no-sync still ran sync"; exit 1; }

echo "PASS: test-groom.sh"
