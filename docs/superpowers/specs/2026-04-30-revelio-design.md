# Revelio — PR Summary Skill

A read-only skill that synthesizes a PR's purpose and execution into a
structured report. Named after the revealing charm — it strips away the
surface and shows what's really there.

## Use Cases

- **Catching up on merged work:** PRs landed while you were away; understand
  what changed and why without reading every diff.
- **Self-review before merge:** Sanity-check that your implementation matches
  ticket intent before merging.

## Invocation

```
/revelio                    # auto-detect repo + PR from current dir/branch
/revelio 1234               # explicit PR, auto-detect repo
/revelio bifrost            # explicit repo, auto-detect PR
/revelio bifrost 1234       # both explicit
/revelio 1234 bifrost       # same — order doesn't matter
```

Args are unordered: numeric → PR number, non-numeric → repo name.

## Input: detect-pr.sh

A deterministic shell script handles arg parsing and detection.

**Logic:**

1. Classify each arg: numeric = PR number, non-numeric = repo name.
2. Repo (if not in args): `gh repo view --json nameWithOwner -q .nameWithOwner`
3. PR (if not in args): `gh pr view --json number -q .number` on current branch.
4. Normalize repo: bare name → `degree-analytics/<name>`.
5. Validate: `gh pr view <number> --repo degree-analytics/<repo> --json number`.
6. Output: `{"repo": "degree-analytics/bifrost", "pr": 1234}`

**Errors:**

| Condition | Message |
|-----------|---------|
| Not in a git repo | "Run from inside a git repo, or pass a repo name" |
| No GitHub remote | "No GitHub remote found. Pass a repo name" |
| Branch has no PR | "No PR for branch `foo`. Pass a PR number" |
| PR doesn't exist | "PR #1234 not found on degree-analytics/bifrost" |

## Data Gathering

Four layers, gathered after detection succeeds. Layers 1–2 and 3–4 can
run in parallel.

### Layer 1 — Ticket context (the "why")

1. `linearis detect-ticket` (auto-detects from git branch name; falls
   back to parsing PR title and body if branch detection fails).
2. If found: `linearis issues read <ticket-id>` → title, description,
   acceptance criteria, state.
3. If no ticket found: note the gap, proceed.

### Layer 2 — PR metadata (the "what")

1. `gh pr view <number> --repo <repo> --json title,body,state,author,baseRefName,headRefName,labels,mergedAt,additions,deletions,changedFiles`

### Layer 3 — Discussion (the "discourse")

1. `huginn pr comments <number> --repo <repo>` → review threads,
   feedback, author responses.
2. Captures reviewer concerns, decisions made during review, and scope
   adjustments that happened post-opening.

### Layer 4 — Implementation (the "how")

1. `gh pr diff <number> --repo <repo>` for the full diff.
2. `huginn pr review <number> --repo <repo> --format summary` for
   AI-analyzed diff summary, risk assessment, and test coverage.

## Report Structure

Printed to conversation. Not persisted to file.

```
# Revelio: PR #1234 — <PR title>

## TLDR
2-3 sentences. What was the goal, what was done, does it land clean.

## Purpose
- **Ticket:** ENG-1234 — <ticket title> (<ticket state>)
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
responded, what changed as a result. Omitted if no review comments exist.

## Concerns
- **Ticket↔implementation gaps:** anything the ticket asked for that
  the diff doesn't deliver, or things the diff does that the ticket
  didn't ask for
- **Reviewer flags:** unresolved concerns from review threads
- **Risks:** anything surfaced by huginn's risk analysis

If nothing to flag in any category, say so explicitly ("No concerns").
```

## Edge Cases

| Situation | Behavior |
|-----------|----------|
| No ticket ID found | Purpose section says "No linked ticket." Uses PR description for intent. |
| PR has no description | Purpose section notes "No PR description provided." Relies on ticket. |
| Neither ticket nor description | Purpose says "No ticket or description — intent unclear." Still produces Execution and Concerns from the diff. |
| No review comments | Discussion section omitted entirely. |
| Diff is very large (1000+ lines) | Lean on `huginn pr review` summary. Note "Large diff — summary based on AI analysis." |
| PR is draft | Note draft status in TLDR. |
| PR is closed (not merged) | Note closure without merge. Adjust framing accordingly. |

## Boundaries

This skill is read-only. It does NOT:

- Post anything to GitHub
- Modify any files
- Judge whether the PR should merge (that's wolfpack/review territory)

## Dependencies

- `gh` (GitHub CLI, authenticated)
- `huginn` (PR comments, review analysis)
- `linearis` (Linear ticket detection and reading)

## Skill Location

`plugins/jp/skills/revelio/SKILL.md` with `detect-pr.sh` as a supporting script.
