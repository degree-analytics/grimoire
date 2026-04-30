---
name: revelio
description: Use when you want to understand a PR — synthesizes ticket context, implementation, review discussion, and concerns into a structured report
allowed-tools: Bash, Read
uses-tools: [gh, huginn, linearis]
argument-hint: "[repo-name] [pr-number]"
---

# Revelio

The revealing charm. Synthesizes a PR's purpose and execution into a
structured report by reading the ticket, PR description, review
discussion, and diff.

**Announce at start:** "Casting revelio on PR #<number>..."

## When to Use

- Catching up on merged work
- Self-review before merge
- User says "summarize PR", "what does this PR do", "revelio"

## Workflow

### Step 1: Detect PR

Run the detection script:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/revelio/scripts/detect-pr.sh <args>
```

Pass through whatever the user provided as arguments. The script
handles arg classification (numeric = PR, non-numeric = repo) and
auto-detection from git context.

Parse the JSON output to get `repo` and `pr`.

If it exits non-zero, surface the error message and stop.

### Step 2: Gather data (parallel where possible)

Run these four data-gathering steps. Layers 1–2 are independent of
layers 3–4, so run them in parallel batches.

**Batch A (run in parallel):**

**Layer 1 — Ticket context:**

```bash
TICKET_ID=$(linearis detect-ticket 2>/dev/null || echo "")
```

If `TICKET_ID` is non-empty:

```bash
linearis issues read "$TICKET_ID"
```

Capture: title, description, acceptance criteria, state.

**Layer 2 — PR metadata:**

```bash
gh pr view <pr> --repo <repo> \
  --json title,body,state,author,baseRefName,headRefName,labels,mergedAt,additions,deletions,changedFiles,isDraft
```

**Batch B (run in parallel):**

**Layer 3 — Discussion:**

```bash
huginn pr comments <pr> --repo <repo>
```

If this returns no comments, the Discussion section will be omitted.

**Layer 4 — Implementation:**

```bash
gh pr diff <pr> --repo <repo>
```

```bash
huginn pr review <pr> --repo <repo> --format summary
```

For large diffs (1000+ lines in the raw diff), lean on the huginn
summary rather than reading the full diff. Note "Large diff — summary
based on AI analysis" in the report.

### Step 3: Synthesize report

Using all gathered data, produce a report in the following structure.
Print it directly to the conversation.

```
# Revelio: PR #<number> — <PR title>

## TLDR
2-3 sentences. What was the goal, what was done, does it land clean.

## Purpose
- **Ticket:** <ticket-id> — <ticket title> (<ticket state>)
- **Problem:** What the ticket describes as the issue/need
- **Goal:** What success looks like per the acceptance criteria

## Execution
### Files changed (<N> files, +<additions> -<deletions>)
Grouped by logical concern — not a flat file list. E.g.:
- **API layer:** added new endpoint in routes/foo.ts, updated middleware
- **Data model:** new migration, schema change in models/bar.ts
- **Tests:** 3 new test files covering the new endpoint

### Key decisions
Notable implementation choices — patterns used, libraries chosen,
approaches taken that aren't obvious from the file list.

## Discussion
Summary of review threads — what reviewers flagged, how the author
responded, what changed as a result. Omitted if no review comments.

## Concerns
- **Ticket↔implementation gaps:** anything the ticket asked for that
  the diff doesn't deliver, or things the diff does that the ticket
  didn't ask for
- **Reviewer flags:** unresolved concerns from review threads
- **Risks:** anything surfaced by huginn's risk analysis

If nothing to flag, say "No concerns."
```

**Edge case handling during synthesis:**

| Situation | Behavior |
|-----------|----------|
| No ticket ID found | Purpose says "No linked ticket." Use PR description for intent. |
| PR has no description | Purpose notes "No PR description provided." Rely on ticket. |
| Neither ticket nor description | Purpose says "No ticket or description — intent unclear." Still produce Execution and Concerns. |
| No review comments | Omit Discussion section entirely. |
| PR is draft | Note draft status in TLDR. |
| PR is closed (not merged) | Note closure without merge. Adjust framing. |

## Boundaries

This skill is read-only. It does NOT:

- Post anything to GitHub
- Modify any files
- Judge whether the PR should merge
