---
name: praepario
description: Use when you need situational awareness — shows recent completions, active work, project progress, flags, and recommends what to pick up next
allowed-tools: Bash, Read, AskUserQuestion
uses-tools: [linearis, gh]
---

# Praepario

Situational awareness for your workstreams. Answers three questions:
what just happened, what's in flight, and what should I do next.

**Announce at start:** "Casting praepario — pulling your work context."

## When to Use

- Start of day, returning from PTO, or anytime you need to orient
- Before running `/eng:standup-dev`
- User says "what's my status", "what should I work on", "praepario"

## Constants

### Workstream Windows

| Window | Label | Prefix | Owner |
|--------|-------|--------|-------|
| Product | `work:product` | P | Emma |
| Quick Wins | `work:quick-wins` | Q | Emma |
| Engineering | `work:engineering` | E | Chad |

### Active States

`Todo`, `In Progress`, `In Review`, `Deployed to Development`, `Ready for Production`, `Blocked`

### Done States

`Done`, `Deployed to Production`, `Canceled`

---

## Step 1: Identify Operator

Get the operator identity from SessionStart context or `~/.secondbrain/identity.yaml`.

## Step 2: Gather Data

No user input needed. Pull all sources before showing anything.

### 2a. Recent completions

Tickets that moved to a done state in the last 7 days:

```bash
linearis issues list \
  --assignee "$USER_NAME" \
  --status "Done,Deployed to Production,Canceled" \
  --updated-after "$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)" \
  --sort-by updatedAt \
  --sort-dir desc \
  --limit 15
```

### 2b. Active tickets

All tickets in active states across all three workstream windows:

```bash
linearis issues list \
  --assignee "$USER_NAME" \
  --status "Todo,In Progress,In Review,Deployed to Development,Ready for Production,Blocked" \
  --label "work:product,work:quick-wins,work:engineering" \
  --sort-by priority \
  --sort-dir asc
```

Also fetch tickets with no `work:*` label (for flags):

```bash
linearis issues list \
  --assignee "$USER_NAME" \
  --status "In Progress,In Review,Deployed to Development"
```

Filter to only tickets missing any `work:*` label.

### 2c. Blocking relations

For each ticket in active states:

```bash
linearis issues relations <TICKET_ID>
```

### 2d. GitHub PR activity

PRs from the last 48 hours:

```bash
gh pr list --author "$USER_NAME" --state all \
  --json number,title,state,headRefName,statusCheckRollup,reviews,mergedAt,createdAt \
  --limit 20
```

Cross-reference PR branch names against Linear ticket IDs.

### 2e. PRs awaiting your review

```bash
gh search prs --review-requested=@me --state=open \
  --json number,title,author,repository,updatedAt \
  --limit 10
```

### 2f. Your PRs with new reviews

```bash
gh search prs --author=@me --state=open --reviewed-by=@me \
  --json number,title,repository,updatedAt \
  --limit 10
```

This doesn't filter well, so instead fetch your open PRs and check for reviews:

```bash
gh pr list --author "@me" --state open \
  --json number,title,headRefName,reviews,repository \
  --limit 15
```

Filter to PRs where any review has `state == "APPROVED"` or
`state == "CHANGES_REQUESTED"` — those need your attention.

### 2g. Project progress

Identify which projects the operator's active tickets belong to. For each
unique project, fetch all tickets (not just the operator's) to compute
progress:

```bash
linearis issues list --project "<PROJECT_NAME>" --limit 100
```

Group by status into three buckets:
- **Done:** Done, Deployed to Production, Canceled
- **Active:** In Progress, In Review, Deployed to Development, Ready for Production, Blocked
- **Remaining:** Todo, Backlog, Triage

---

## Step 3: Render Report

### 3a. Recently Completed

```
RECENTLY COMPLETED (last 7d):
  [done] ENG-5501  Campus Flow search      [Done, 2d ago]
  [done] ENG-5400  Fix login timeout       [Deployed to Production, 5d ago]
  [cancel] ENG-5200  Old metrics endpoint  [Canceled, 6d ago]
```

If no recent completions, print "No tickets completed in the last 7 days."

### 3b. Active Work

Grouped by workstream window:

```
ACTIVE WORK:

WINDOW 1 — Product (P):
  1. [bullet] ENG-5820  Dashboard filters       [In Progress, 2d]
  2. [circle] ENG-5900  Export CSV              [Todo, 1d]

WINDOW 2 — Quick Wins (Q):
  1. [circle] ENG-5320  Map tooltip overlap     [Todo, 6d]

WINDOW 3 — Engineering (E):
  1. [bullet] ENG-5710  CI flake in spacewalker [In Progress, 3d]
  2. [blocked] ENG-5600  Migrate to vitest      [Blocked, 12d] — blocked by ENG-5710
```

Display rules:
- `[bullet]` = In Progress / In Review / Deployed to Development / Ready for Production
- `[circle]` = Todo
- `[blocked]` = Blocked — append reason
- Numbered positions reflect priority (1=Urgent → 4=Low)
- Show days in state

### 3c. PR Status

Two sections: PRs waiting for your review, and your PRs that have been reviewed.

```
PR STATUS:

  Awaiting your review:
    #445 campusiq/bifrost — "Add rate limiting" (alice, updated 3h ago)
    #312 campusiq/admin_app — "Fix SSO redirect" (bob, updated 1d ago)

  Your PRs with reviews:
    #501 campusiq/bifrost — "Dashboard filters" — APPROVED (chad)
    #498 campusiq/admin_app — "Migrate auth" — CHANGES REQUESTED (emma)
```

If no PRs in either category, print "No PRs awaiting review." or "No reviews on your PRs."

### 3d. Project Progress

For each project the operator has active tickets in:

```
PROJECT PROGRESS:

  Campus Flow (Q1 Launch):
    Done: 12/20 (60%)  |  Active: 5  |  Remaining: 3
    ████████████░░░░░░░░ 60%

  Platform Reliability:
    Done: 8/15 (53%)   |  Active: 4  |  Remaining: 3
    ██████████░░░░░░░░░░ 53%
```

If a project has milestones, show the current milestone's progress instead
of the full project.

### 3e. Flags

Surface discipline issues:

| Flag | Condition |
|------|-----------|
| Unprioritized work | In Progress + no `work:*` label |
| Stale ticket | In Progress + no activity in 48h |
| Ghost velocity | PRs merged recently but Linear ticket has no state change |
| Priority mismatch | Active ticket is not highest-priority unblocked item in its window |
| Blocked dependency | Ticket blocked by another ticket in same window or queue |
| Empty window | 0 tickets in a window while another has 2+ |
| Unresolved blocker | Blocked >24h with no resolution |
| Missing size label | In Progress ticket has no `size:*` label |

```
FLAGS:
  [warn] STALE: ENG-5600 [In Progress] — no activity in 48h
  [warn] EMPTY WINDOW: 0 tickets in Quick Wins, 2+ in Product
```

If no flags, print "No flags."

### 3f. Recommendations

For each window, recommend the top pick and any strong alternates:

1. **Already in progress** beats Todo (momentum)
2. **Higher priority** beats lower (Urgent > High > Medium > Low)
3. **Smaller size** beats larger for velocity
4. **Blockers** disqualify a ticket
5. **Severity labels** (S1, S2) escalate urgency
6. **Discipline flags** should be resolved before picking new work

```
RECOMMENDATIONS:

  Product: ENG-5820 Dashboard filters — in progress, high priority, size M
  Quick Wins: ENG-5320 Map tooltip overlap — only ticket, unblocked
  Engineering: ENG-5710 CI flake — in progress, but blocked on Todd
    → Consider: ENG-5600 Migrate to vitest [Todo] if blocker persists
```

If a window has no actionable tickets, say so.

---

## Boundaries

This skill is read-only. It does NOT:

- Post to Slack
- Modify tickets or labels
- Apply any changes

Use `/eng:standup-dev` to apply label fixes and post to Slack.

---

## Error Handling

- **linearis issues list** or **linearis issues relations** fails: cannot proceed, display error and exit
- **gh pr list** or **gh search prs** fails: continue without GitHub/PR data, warn that PR activity is unavailable
- **linearis issues list --project** fails: skip project progress section, warn

## Usage

```bash
/praepario
```

## Related

- `/eng:standup-dev` — apply label fixes and post standup to #dev
- `/eng:workstreams-mine` — shows current work across all 3 windows
- `/eng:pick-next` — finds next ticket by workstream priority
