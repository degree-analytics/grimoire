# Subagent output contract

Every `/wolfpack hunt` subagent writes the same two artifacts and returns the summary JSON verbatim.

## `<repo>-pr<n>.summary.json`

Example:

    {
      "pr": 1234,
      "repo": "admin_app",
      "nameWithOwner": "campusiq/admin_app",
      "title": "Add rate limiting to login endpoint",
      "url": "https://github.com/campusiq/admin_app/pull/1234",
      "verdict_counts": {
        "implement": 3,
        "discuss": 1,
        "skip": 2,
        "inconclusive": 0
      },
      "critical_count": 1,
      "top_issue": "Missing rate limiting (auth.py:67)",
      "report_path": "/Users/jp/ws/review/.reports/admin_app-pr1234.md",
      "worktree_path": "/Users/jp/ws/review/admin_app/.worktrees/pr-1234",
      "status": "ok"
    }

### Field semantics

| field | type | notes |
|---|---|---|
| `pr` | integer | PR number |
| `repo` | string | short repo name |
| `nameWithOwner` | string | `owner/repo` |
| `title` | string | PR title, unmodified |
| `url` | string | direct link to PR |
| `verdict_counts` | object | integer counts keyed by verdict |
| `critical_count` | integer | number of findings adjudicated as `implement` AND Wolf-priority `critical` |
| `top_issue` | string\|null | one-line description of the highest-priority implement finding; null if none |
| `report_path` | string | absolute path to markdown report |
| `worktree_path` | string | absolute path to PR worktree |
| `status` | enum | `ok` \| `fetch_error` \| `wolf_error` \| `parse_error` \| `partial` |
| `error` | string | (optional) present when status != `ok` |

## `<repo>-pr<n>.md`

Human-readable markdown: adjudicated findings table + per-finding detail blocks, matching the format `eng:code-review` Phase 5 produces — minus the "Select items to act on" prompt.

## Error status examples

### fetch_error

    {
      "pr": 892,
      "repo": "bifrost",
      "nameWithOwner": "campusiq/bifrost",
      "title": "WIP: new auth flow",
      "url": "https://github.com/campusiq/bifrost/pull/892",
      "status": "fetch_error",
      "error": "fatal: couldn't find remote ref pull/892/head"
    }

### wolf_error

    {
      "pr": 1240,
      "repo": "admin_app",
      "status": "wolf_error",
      "error": "codex-wrapper timeout after 300s"
    }
