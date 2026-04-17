---
name: wolfpack
description: Batch-review multiple PRs from your GitHub review inbox in parallel using Wolf + adjudication. Subcommands - `hunt` reviews up to 3 PRs in isolated worktrees, `groom` cleans up merged/closed PR worktrees. Use when you have multiple PRs awaiting your review on repos cloned under ~/ws/review/.
---

# Wolfpack

Send a pack of review subagents at your GitHub review inbox.

## Subcommands

- `/wolfpack hunt` — review up to 3 PRs from your review inbox in parallel
- `/wolfpack groom` — prune worktrees for merged/closed PRs, archive reports

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

1. Call `prep-worktree.sh --clone ~/ws/review/<repo> --pr <n>` → captures worktree path.
2. Resolve base ref: `gh pr view <n> --repo <nameWithOwner> --json baseRefName -q .baseRefName`.
3. Load the template at `${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/references/subagent-prompt.md` and substitute placeholders.
4. Add an Agent tool call (subagent_type: `general-purpose`) with the substituted prompt.

**Send all Agent tool calls in a single message** — the Claude Code runtime runs them concurrently. Do NOT loop and wait per PR.

### Phase 6: Collect and render

Each subagent's final response is a JSON summary (per `references/subagent-contract.md`). For each:

1. Parse the JSON.
2. If `status != "ok"`, still include it in the output with its error.

Render a single consolidated table and print it to the user:

```
Wolfpack hunted N PRs:

| PR | repo | verdict breakdown | crit | top issue | report |
|----|------|-------------------|------|-----------|--------|
| ...                                                      |

Worktrees kept at:
  <path>
  ...

Run /wolfpack groom to clean up merged/closed PR worktrees.
```

End of hunt.

---

## GROOM workflow

Parse any flags after `groom`:
- `--all` → pass to groom.sh (removes every wolfpack worktree)

Initialize the flag variable explicitly before invoking:

```bash
EXTRA_FLAGS=""
[ "${1:-}" = "--all" ] && EXTRA_FLAGS="--all"
```

### Step 1: Preflight

```bash
gh auth status >/dev/null 2>&1 || {
  echo "gh is not authenticated. Run: gh auth login"
  exit 1
}
```

### Step 2: Derive owner and run groom

The inbox owner (for `gh pr view --repo <owner>/<repo>`) comes from the first seen PR in the current inbox. Fetch it via:

```bash
OWNER=$(${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/scripts/inbox.sh 2>/dev/null \
  | jq -r '.[0].nameWithOwner | split("/")[0] // "campusiq"')
```

If the inbox is empty, default to `campusiq`. (If the user reviews cross-org later, we add `--owner` to the subcommand.)

### Step 3: Invoke groom.sh

```bash
${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/scripts/groom.sh \
  --review-dir ~/ws/review \
  --repo-owner "$OWNER" \
  $EXTRA_FLAGS
```

Stream its output directly. That's the entire groom UX.

---

## Notes

- Worktrees are **never** removed by `hunt` — only by `groom`.
- Reports accumulate in `~/ws/review/.reports/` until groom archives them.
- If `hunt` dies mid-run, reruning it reuses existing worktrees; any already-written summary JSON files will surface in the next run's output table automatically (the template step 1 writes `fetch_error` only when the worktree can't be prepared, not when it already exists).
