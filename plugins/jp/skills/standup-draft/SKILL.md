---
name: standup-draft
description: Prep tomorrow's standup — review last update, scan backlog, and draft priority picks per workstream
allowed-tools: Bash, Read, AskUserQuestion
---

# Standup Draft

## Overview

Pre-flight for `/eng:standup-dev`. Reviews your last standup, checks ticket state changes,
scans your backlog across all three workstream windows, surfaces discipline flags, and
recommends picks.

**Announce at start:** "Drafting tomorrow's standup. Let me pull your last update and current backlog."

## When to Use

- Night before standup
- Anytime you want to review priorities before posting
- User says "prep standup", "standup draft", "what should I pick for standup"

## Constants

### Workstream Windows

| Window | Label | Prefix | Owner |
|--------|-------|--------|-------|
| Product | `work:product` | P | Emma |
| Quick Wins | `work:quick-wins` | Q | Emma |
| Engineering | `work:engineering` | E | Chad |

### Active States

Tickets in these Linear states appear on the board:
`Todo`, `In Progress`, `In Review`, `Deployed to Development`, `Ready for Production`, `Blocked`

---

## Workflow

### Step 1: Identify Operator

Get the operator identity from SessionStart context or `~/.secondbrain/identity.yaml`.

### Step 2: Pull Last Standup from #dev

Read recent messages from #dev and find the operator's most recent standup post.

```bash
eval "$(bifrost env --provider slack)" && huginn slack history --channel dev --since 7d --limit 200
```

Search output for the operator's standup (look for the format: `Name -- Mon DD` followed by
window-prefixed lines like `P:`, `Q:`, `E:`). Extract:
- Date of last standup
- Ticket IDs mentioned
- Forecasts given ("ships today", "no movement")

### Step 3: Check Ticket State Changes

For each ticket from the last standup, read current state from Linear:

```bash
linearis issues read <TICKET_ID>
```

Build a comparison table:

```
Last standup (Mar 26):

| Ticket   | What you said   | Current state     |
|----------|-----------------|-------------------|
| ENG-XXXX | "ships today"   | Done / In Progress / etc. |
| ENG-YYYY | "no movement"   | Todo / In Progress / etc. |
```

Flag anything surprising (ticket you said would move but didn't, or ticket that completed unexpectedly).

### Step 4: Gather Data

#### 4a. Pull Linear Queue

Fetch all tickets assigned to the dev across all three windows, sorted by priority:

```bash
linearis issues list \
  --assignee "$USER_NAME" \
  --status "Todo,In Progress,In Review,Deployed to Development,Ready for Production,Blocked" \
  --label "work:product,work:quick-wins,work:engineering" \
  --sort-by priority \
  --sort-dir asc
```

Also fetch tickets with no `work:*` label (for discipline flags):

```bash
linearis issues list \
  --assignee "$USER_NAME" \
  --status "In Progress,In Review,Deployed to Development"
```

Filter the second result to only tickets missing any `work:*` label.

#### 4b. Query Blocking Relations

For each ticket in active states, check blocking relationships:

```bash
linearis issues relations <TICKET_ID>
```

Mark tickets that are blocked by another ticket. Store the blocking ticket ID for display.

#### 4c. Pull GitHub Activity

Fetch PRs from the last 24 hours:

```bash
gh pr list --author "$USER_NAME" --state all --json number,title,state,headRefName,statusCheckRollup,reviews,mergedAt,createdAt --limit 20
```

Cross-reference PR branch names against Linear ticket IDs to link PRs to tickets.

### Step 5: Display Board

Render the board with numbered priority positions within each window:

```
<name> -- Standup Prep (<date>)

SINCE LAST STANDUP:
  [checkmark] ENG-5501 In Progress -> In Review (PR #445 opened)
  [speech] ENG-5320 -- Emma commented: "deprioritize this"
  [merge] ENG-5501 -- PR #445: 1 approval, CI green

WINDOW 1 -- Product (P):
  1. [bullet] ENG-5501  Campus Flow search      [In Review, 4d]
  2. [bullet] ENG-5820  Dashboard filters       [In Progress, 2d]

WINDOW 2 -- Quick Wins (Q):
  1. [circle] ENG-5320  Map tooltip overlap     [Todo, 6d]

WINDOW 3 -- Engineering (E):
  1. [bullet] ENG-5710  CI flake in spacewalker [In Progress, 3d]
  2. [circle] ENG-5600  Migrate to vitest       [Todo, 12d]
```

Display rules:
- `[bullet]` = In Progress / In Review / Deployed to Development / Ready for Production
- `[circle]` = Todo
- `[blocked]` = Blocked -- append ` -- blocked by <BLOCKING_TICKET_ID>` after the state
- Numbered positions reflect ticket priority (1=Urgent → 4=Low)
- Show days in state after the state name (e.g., `[In Progress, 3d]`)

### Step 6: Surface Discipline Flags

After the board, display any applicable flags:

| Flag | Condition |
|------|-----------|
| Unprioritized work | In Progress + no `work:*` label |
| Stale ticket | In Progress + no activity in 48h |
| Ghost velocity | PRs merged in last 24h but Linear ticket has no state change |
| Priority mismatch | Active ticket is not highest-priority unblocked item in that window |
| Blocked dependency | Ticket blocked by another ticket in the same window or dev's queue |
| Empty window | Dev has 0 tickets in a window while another window has 2+ |
| Unresolved blocker | Ticket marked blocked for >24h with no resolution |
| Missing size label | In Progress ticket has no `size:*` label |

```
FLAGS:
  [warn] UNPRIORITIZED: ENG-6561 [In Progress] -- no work:* label
  [warn] STALE: ENG-5600 [In Progress] -- no activity in 48h
  [warn] EMPTY WINDOW: 0 tickets in Quick Wins, 2+ in Product
```

### Step 7: Recommendations

For each window (Product, Quick Wins, Engineering), recommend the top pick and any
strong alternates. Use this reasoning framework:

1. **Already in progress** beats Todo (momentum matters)
2. **Higher priority** beats lower (Urgent > High > Medium > Low)
3. **Smaller size** beats larger for "ships today" credibility
4. **Blockers** disqualify a ticket from being a pick
5. **Severity labels** (S1, S2) escalate urgency
6. **Discipline flags** should be resolved before picking new work

Format:

```
Recommendations:

Product (Owner: Emma):
  Top pick: ENG-XXXX — [reason: in progress, urgent, small, clear path]
  Also strong: ENG-YYYY — [reason: high priority, but larger scope]

Quick Wins (Owner: Emma):
  Top pick: ENG-XXXX — [reason: small, unblocked, quick win]

Engineering (Owner: Chad):
  Top pick: ENG-XXXX — [reason: medium priority, already started, small]
  Also strong: ENG-YYYY — [reason: medium priority, quick win]
```

If a window has no actionable tickets, say so.

### Step 8: Draft Preview

Show what tomorrow's standup TLDR would look like based on the top picks:

```
Draft TLDR for tomorrow:

  [green] P: ENG-5501 Campus Flow search [In Review]
  [green] P: ENG-5820 Dashboard filters [In Progress]
  [red] E: ENG-5710 CI flake spacewalker -- blocked: needs Todd access
  [circle] Q: ENG-5320 Map tooltip overlap -- deprioritized per Emma
```

TLDR format rules:
- `[green]` = actively moving (In Progress, In Review, Deployed to Development, Ready for Production)
- `[red]` = blocked (always include reason)
- `[circle]` = notable Todo items (deprioritized, newly assigned, etc.)
- Window prefix: P (Product), Q (Quick Wins), E (Engineering)

Remind the user: "Run `/eng:standup-dev` tomorrow morning to finalize forecasts and post."

## The Iron Law

**NEVER POST TO SLACK. THIS IS READ-ONLY PREP.**

This skill gathers data and makes recommendations. It does not post anything. The actual standup post happens via `/eng:standup-dev` the next morning.

---

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "The picks are obvious, skip the backlog scan" | You might miss a ticket that changed state or priority since you last looked. Always scan. |
| "Just show In Progress tickets, skip Todo" | Todo tickets can be better picks if they're higher priority and small. Show both. |
| "Post it now since we already have the picks" | This is prep, not posting. Forecasts happen fresh tomorrow morning. |
| "Skip the flags, they're just noise" | Flags surface issues standup-dev will catch anyway. Fix them now so morning is clean. |
| "Skip GitHub data, it's not essential" | PR cross-reference catches ghost velocity and state mismatches. Pull it. |

---

## Red Flags - STOP and Restart

**If you observe ANY of these, stop immediately and investigate:**

1. **Slack token not available** - If bifrost env fails, tell the user to run `bifrost auth refresh slack` or check their token setup. Do not skip the last-standup review.

2. **Linear queries return empty** - The operator may have no assigned tickets, or the identity may be wrong. Verify against operator identity.

3. **Last standup is more than 5 days old** - Flag this to the user. They may have missed standups and should be aware of the gap.

## Usage

```bash
/standup-draft
```

## Related

- `/eng:standup-dev` -- The actual standup posting skill (run after this)
- `/eng:workstreams-mine` -- Shows current work across all 3 windows
- `/eng:pick-next` -- Finds next ticket by workstream priority
