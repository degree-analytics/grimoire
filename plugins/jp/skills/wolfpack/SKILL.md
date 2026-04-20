---
name: wolfpack
description: Batch-review multiple PRs from your GitHub review inbox in parallel using Wolf + adjudication. Subcommands - `hunt` reviews up to 3 PRs in isolated worktrees, `groom` cleans up merged/closed PR worktrees. Use when you have multiple PRs awaiting your review on repos cloned under ~/ws/review/.
---

# Wolfpack

Send a pack of review subagents at your GitHub review inbox.

## Subcommands

- `/wolfpack hunt` — review up to 3 PRs from your review inbox in parallel
- `/wolfpack groom` — sync review repos, prune worktrees for merged/closed PRs, archive reports

## Dispatch

Parse the first positional arg:
- `hunt` → follow the HUNT workflow below
- `groom` → follow the GROOM workflow (placeholder; Task 9 will fill this in)
- anything else (including empty) → print usage and stop

```
Usage:
  /wolfpack hunt
  /wolfpack groom
```

---

## HUNT workflow

Assumptions:
- Review directory: `~/ws/review/`
- Clone layout: nested `~/ws/review/<owner>/<repo>/` (preferred; prevents same-name collisions across orgs). Flat `~/ws/review/<repo>/` is also accepted — owner is derived from the clone's `origin` URL. Hunt creates new clones in nested layout only.
- Helper scripts live at `${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/scripts/`
- Subagent prompt template: `${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/references/subagent-prompt.md`

### Phase 1: Preflight

Run in Bash:

```bash
gh auth status >/dev/null 2>&1 || {
  echo "gh is not authenticated. Run: gh auth login"
  exit 1
}
mkdir -p ~/ws/review/.reports
```

If this exits non-zero, stop and surface the message.

### Phase 2: Fetch inbox

```bash
INBOX=$(${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/scripts/inbox.sh)
COUNT=$(echo "$INBOX" | jq 'length')
```

If `$COUNT` is 0, print:

```
no PRs requesting your review — nothing to hunt
```

...and stop.

### Phase 3: Verify clones

Derive repo/nameWithOwner pairs from the inbox, feed them to ensure-clone.sh:

```bash
MISSING=$(echo "$INBOX" \
  | jq -r '.[] | [.repo, .nameWithOwner] | @tsv' \
  | sort -u \
  | ${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/scripts/ensure-clone.sh --review-dir ~/ws/review --check-only)
```

If `$MISSING` is non-empty, use **AskUserQuestion** with these options:

- "Auto-clone all missing repos" → run ensure-clone.sh again with `--clone`
- "Skip PRs in missing repos" → filter them out of `$INBOX`
- "Cancel" → stop

### Phase 4: PR selection

Compute the final selection set:

- If `$COUNT <= 3`: use all PRs.
- If `$COUNT > 3`: render a table of all PRs (columns: PR, repo, title truncated to 60 chars, author, +/-, checks, updated) and ask the user via **AskUserQuestion** (multiSelect: true) which to hunt. **Enforce a cap of 3 selected.** If the user picks more, ask again.

### Phase 5: Dispatch subagents in parallel

For each selected PR (up to 3):

1. Resolve base ref: `gh pr view <n> --repo <nameWithOwner> --json baseRefName -q .baseRefName`.
2. Detect whether the PR is part of a graphite stack — i.e. its base is **not** the repo's default branch. Query the default branch once per repo:
   ```bash
   DEFAULT=$(gh repo view <nameWithOwner> --json defaultBranchRef -q .defaultBranchRef.name)
   ```
   If `baseRefName` equals `DEFAULT` or is `dev`/`main`/`master`, `stacked=false`. Otherwise `stacked=true` (the PR stacks on another PR's branch).
3. Resolve the actual clone path (nested or flat layout):
   ```bash
   source ${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/lib/resolve-clone.sh
   CLONE_PATH=$(resolve_clone_path ~/ws/review <nameWithOwner>)
   ```
   Then call `prep-worktree.sh --clone "$CLONE_PATH" --pr <n> --base-ref <baseRefName>` → captures worktree path. The `--base-ref` fetch is cheap and idempotent; always pass it so `origin/<baseRefName>` is guaranteed to exist for Wolf's diff, whether the PR is stacked or not.
4. Load the template at `${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/references/subagent-prompt.md` and substitute placeholders, including:
   - `report_md_path` = `~/ws/review/.reports/<owner>__<repo>-pr<n>.md`
   - `report_json_path` = `~/ws/review/.reports/<owner>__<repo>-pr<n>.summary.json`
   - `stacked` = `true` or `false` from step 2
5. Add an Agent tool call (subagent_type: `general-purpose`) with the substituted prompt.

**Send all Agent tool calls in a single message** — the Claude Code runtime runs them concurrently. Do NOT loop and wait per PR.

**Graphite stacks:** when `stacked=true`, Wolf is intentionally told to compare against the parent PR's branch only — reviewers see just this PR's incremental diff, matching Graphite's per-PR review model. The base ref fetched in step 3 makes that comparison possible even if the parent branch hasn't been fetched before.

### Phase 6: Collect and render

Each subagent's final response is a JSON summary (per `references/subagent-contract.md`). For each:

1. Parse the JSON.
2. If `status != "ok"`, still include it in the output with its error.

Render a single consolidated table and print it to the user:

```
Wolfpack hunted N PRs:

| PR | repo | stack | verdict breakdown | crit | top issue | report |
|----|------|-------|-------------------|------|-----------|--------|
| ...                                                              |

Worktrees kept at:
  <path>
  ...

Run /wolfpack groom to clean up merged/closed PR worktrees.
```

The `stack` column shows `→<base-branch>` when the PR stacks on another PR; empty otherwise. This helps reviewers recognize why a diff may look small — they're reviewing incremental changes against a parent PR.

End of hunt.

---

## GROOM workflow

```
Usage:
  /wolfpack groom [--all] [--no-sync]
```

Parse any flags after `groom`:
- `--all` → pass to groom.sh (removes every wolfpack worktree)
- `--no-sync` → pass to groom.sh (skips the per-repo sync pass)

Initialize the flag variable explicitly before invoking:

```bash
EXTRA_FLAGS=""
for arg in "$@"; do
  case "$arg" in
    --all|--no-sync) EXTRA_FLAGS="$EXTRA_FLAGS $arg" ;;
  esac
done
```

### Step 1: Preflight

```bash
gh auth status >/dev/null 2>&1 || {
  echo "gh is not authenticated. Run: gh auth login"
  exit 1
}
```

### Step 2: Invoke groom.sh

```bash
${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/scripts/groom.sh \
  --review-dir ~/ws/review \
  $EXTRA_FLAGS
```

Stream its output directly. That's the entire groom UX. Owner and repo are derived per-worktree from the `<owner>/<repo>/` path, so cross-org reviews work out of the box.

Groom runs in two passes:

1. **Sync** (unless `--no-sync`): for each `<owner>/<repo>` clone under `~/ws/review/`, run `gt sync -f` when the repo is gt-initialized (Graphite's recommended fetch + trunk update + merged-branch delete), falling back to `git fetch --all --prune`. This keeps origin refs fresh so the next `/wolfpack hunt` has up-to-date PR head and base refs.
2. **Prune**: remove worktrees whose PR is `MERGED` or `CLOSED` (or all wolfpack worktrees if `--all`), archive their reports under `.reports/archive/`, and prune stale worktree metadata.

---

## Notes

- Worktrees are **never** removed by `hunt` — only by `groom`.
- Reports accumulate in `~/ws/review/.reports/` until groom archives them.
- If `hunt` dies mid-run, reruning it reuses existing worktrees; any already-written summary JSON files will surface in the next run's output table automatically (the template step 1 writes `fetch_error` only when the worktree can't be prepared, not when it already exists).
