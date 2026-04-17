#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/groom.sh"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Set up review-dir with two fake worktrees, one MERGED, one OPEN
REV="$TMP/review"
mkdir -p "$REV/admin_app/.worktrees/pr-1234" "$REV/admin_app/.worktrees/pr-1237"
mkdir -p "$REV/.reports/archive"
: > "$REV/.reports/admin_app-pr1234.md"
: > "$REV/.reports/admin_app-pr1237.md"

# Create a stub `gh` on PATH that returns MERGED for 1234 and OPEN for 1237
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Only handles: gh pr view <n> --repo <r> --json state -q .state
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

PATH="$STUB_BIN:$PATH" "$SCRIPT" --review-dir "$REV" --repo-owner campusiq

# 1234 should be gone, 1237 should remain
[ ! -d "$REV/admin_app/.worktrees/pr-1234" ] || { echo "FAIL: pr-1234 worktree still present"; exit 1; }
[ -d "$REV/admin_app/.worktrees/pr-1237" ]   || { echo "FAIL: pr-1237 worktree removed"; exit 1; }

# Report for 1234 should be archived
[ -f "$REV/.reports/archive/admin_app-pr1234.md" ] || { echo "FAIL: report for 1234 not archived"; exit 1; }
[ -f "$REV/.reports/admin_app-pr1237.md" ]         || { echo "FAIL: report for 1237 removed"; exit 1; }

echo "PASS: test-groom.sh"
