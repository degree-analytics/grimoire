---
name: oppugno
description: Use when you have multiple PRs awaiting review — tidys stale worktrees, then dispatches parallel review agents at your GitHub inbox with Wolf + adjudication
---

# Oppugno

Send a flock of review agents at your GitHub review inbox.

Tidys first (syncs repos, prunes merged/closed worktrees), then hunts
(fetches inbox, triages, dispatches parallel review agents).

```
Usage:
  /oppugno              # tidy + hunt
  /oppugno --no-sync    # skip repo sync during tidy
```

Parse flags:
- `--no-sync` → pass to tidy.sh (skips per-repo sync pass)
- `--all` → pass to tidy.sh (prunes every oppugno worktree, not just merged/closed)

---

## Phase 0: Preflight

Assumptions:
- Review directory: `~/ws/review/`
- Clone layout: nested `~/ws/review/<owner>/<repo>/` (preferred; prevents same-name collisions across orgs). Flat `~/ws/review/<repo>/` is also accepted — owner is derived from the clone's `origin` URL. Hunt creates new clones in nested layout only.
- Helper scripts live at `${CLAUDE_PLUGIN_ROOT}/skills/oppugno/scripts/`
- Subagent prompt template: `${CLAUDE_PLUGIN_ROOT}/skills/oppugno/references/subagent-prompt.md`

Run in Bash:

```bash
gh auth status >/dev/null 2>&1 || {
  echo "gh is not authenticated. Run: gh auth login"
  exit 1
}
mkdir -p ~/ws/review/.reports
```

If this exits non-zero, stop and surface the message.

## Phase 1: Tidy

Sync repos and prune stale worktrees before hunting.

```bash
EXTRA_FLAGS=""
# Pass through --no-sync and --all flags from user args
for arg in "$@"; do
  case "$arg" in
    --all|--no-sync) EXTRA_FLAGS="$EXTRA_FLAGS $arg" ;;
  esac
done

${CLAUDE_PLUGIN_ROOT}/skills/oppugno/scripts/tidy.sh \
  --review-dir ~/ws/review \
  $EXTRA_FLAGS
```

Stream its output directly. Tidy runs two passes:

1. **Sync** (unless `--no-sync`): for each `<owner>/<repo>` clone under `~/ws/review/`, run `gt sync -f` when the repo is gt-initialized, falling back to `git fetch --all --prune`.
2. **Prune**: remove worktrees whose PR is `MERGED` or `CLOSED` (or all oppugno worktrees if `--all`), archive their reports under `.reports/archive/`.

If tidy fails, log the error but continue to hunt — a tidy failure shouldn't block reviews.

## Phase 2: Fetch inbox

```bash
INBOX=$(${CLAUDE_PLUGIN_ROOT}/skills/oppugno/scripts/inbox.sh)
COUNT=$(echo "$INBOX" | jq 'length')
```

If `$COUNT` is 0, print:

```
no PRs requesting your review — nothing to hunt
```

...and stop.

## Phase 3: Verify clones

Derive repo/nameWithOwner pairs from the inbox, feed them to ensure-clone.sh:

```bash
MISSING=$(echo "$INBOX" \
  | jq -r '.[] | [.repo, .nameWithOwner] | @tsv' \
  | sort -u \
  | ${CLAUDE_PLUGIN_ROOT}/skills/oppugno/scripts/ensure-clone.sh --review-dir ~/ws/review --check-only)
```

If `$MISSING` is non-empty, use **AskUserQuestion** with these options:

- "Auto-clone all missing repos" → run ensure-clone.sh again with `--clone`
- "Skip PRs in missing repos" → filter them out of `$INBOX`
- "Cancel" → stop

## Phase 4: Triage

Determine which PRs are actually ready for review. For each PR in `$INBOX`, run triage:

```bash
VIEWER=$(gh api user --jq .login)
TRIAGE_RESULTS=""
while read -r pr_json; do
  result=$(echo "$pr_json" | ${CLAUDE_PLUGIN_ROOT}/skills/oppugno/scripts/triage.sh --viewer "$VIEWER")
  TRIAGE_RESULTS="${TRIAGE_RESULTS}${result}"$'\n'
done < <(echo "$INBOX" | jq -c '.[]')
```

Split PRs into three buckets based on `verdict`:

- **ready** — eligible for review, pass through to selection.
- **not_ready** — draft or CI failing, and we haven't commented yet (or author replied to our comment asking for review anyway).
- **already_flagged** — we already left a comment and author hasn't replied. Auto-skip these.

If there are **already_flagged** PRs, print a summary line:

```
Skipping N PRs (already flagged as not ready, no author response):
  - #1234 campusiq/admin_app — "WIP: new auth flow" (draft)
  - #567  campusiq/bifrost   — "Add metrics" (CI: FAILURE)
```

If there are **not_ready** PRs, present each one via **AskUserQuestion** (one question per PR, or batched if ≤3):

```
PR #892 campusiq/bifrost — "WIP: new auth flow"
Status: draft
```

Options:
- **"Leave a comment and skip"** — post a comment via `gh pr comment <n> --repo <nwo> --body "..."` using a polite template (see below) and remove from the selection pool.
- **"Review anyway"** — keep it in the selection pool despite not being ready.
- **"Skip silently"** — remove from selection pool without commenting.

For PRs where `author_replied` is true, amend the question to note:

```
PR #892 campusiq/bifrost — "WIP: new auth flow"
Status: draft
Note: Author replied after your last comment — they may want early feedback.
```

**Comment templates** (choose based on reasons):

Draft only:
> Holding off on review — this is still in draft. Let me know when it's ready and I'll take a look.

CI failing only:
> Holding off on review — CI is failing. Let me know when it's green and I'll take a look.

Both:
> Holding off on review — this is still in draft and CI is failing. Let me know when both are resolved and I'll take a look.

After triage, replace `$INBOX` with only the PRs that passed through (ready + "review anyway" selections). If no PRs remain, print:

```
no review-ready PRs after triage — nothing to hunt
```

...and stop.

## Phase 5: PR selection

Compute the final selection set:

- If `$COUNT <= 3`: use all PRs.
- If `$COUNT > 3`: render a table of all PRs (columns: PR, repo, title truncated to 60 chars, author, +/-, checks, updated) and ask the user via **AskUserQuestion** (multiSelect: true) which to hunt. **Enforce a cap of 3 selected.** If the user picks more, ask again.

## Phase 6: Dispatch subagents in parallel

For each selected PR (up to 3):

1. Resolve base ref: `gh pr view <n> --repo <nameWithOwner> --json baseRefName -q .baseRefName`.
2. Detect whether the PR is part of a graphite stack — i.e. its base is **not** the repo's default branch. Query the default branch once per repo:
   ```bash
   DEFAULT=$(gh repo view <nameWithOwner> --json defaultBranchRef -q .defaultBranchRef.name)
   ```
   If `baseRefName` equals `DEFAULT` or is `dev`/`main`/`master`, `stacked=false`. Otherwise `stacked=true` (the PR stacks on another PR's branch).
3. Resolve the actual clone path (nested or flat layout):
   ```bash
   source ${CLAUDE_PLUGIN_ROOT}/skills/oppugno/lib/resolve-clone.sh
   CLONE_PATH=$(resolve_clone_path ~/ws/review <nameWithOwner>)
   ```
   Then call `prep-worktree.sh --clone "$CLONE_PATH" --pr <n> --base-ref <baseRefName>` → captures worktree path. The `--base-ref` fetch is cheap and idempotent; always pass it so `origin/<baseRefName>` is guaranteed to exist for Wolf's diff, whether the PR is stacked or not.
4. Load the template at `${CLAUDE_PLUGIN_ROOT}/skills/oppugno/references/subagent-prompt.md` and substitute placeholders, including:
   - `report_md_path` = `~/ws/review/.reports/<owner>__<repo>-pr<n>.md`
   - `report_json_path` = `~/ws/review/.reports/<owner>__<repo>-pr<n>.summary.json`
   - `stacked` = `true` or `false` from step 2
5. Add an Agent tool call (subagent_type: `general-purpose`) with the substituted prompt.

**Send all Agent tool calls in a single message** — the Claude Code runtime runs them concurrently. Do NOT loop and wait per PR.

**Graphite stacks:** when `stacked=true`, Wolf is intentionally told to compare against the parent PR's branch only — reviewers see just this PR's incremental diff, matching Graphite's per-PR review model. The base ref fetched in step 3 makes that comparison possible even if the parent branch hasn't been fetched before.

## Phase 7: Collect and render

Each subagent's final response is a JSON summary (per `references/subagent-contract.md`). For each:

1. Parse the JSON.
2. If `status != "ok"`, still include it in the output with its error.

Render a single consolidated table and print it to the user:

```
Oppugno reviewed N PRs:

| PR | repo | stack | verdict breakdown | crit | top issue | report |
|----|------|-------|-------------------|------|-----------|--------|
| ...                                                              |

Worktrees kept at:
  <path>
  ...

```

The `stack` column shows `→<base-branch>` when the PR stacks on another PR; empty otherwise. This helps reviewers recognize why a diff may look small — they're reviewing incremental changes against a parent PR.

---

## Notes

- Tidy always runs before hunt — stale worktrees are cleaned up before new reviews start.
- Worktrees created during hunt persist until the next `/oppugno` run tidys them.
- Reports accumulate in `~/ws/review/.reports/` until tidy archives them.
- If hunt dies mid-run, rerunning `/oppugno` tidys first, then reuses existing worktrees.
