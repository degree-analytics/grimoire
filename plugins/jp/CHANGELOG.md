# Changelog

## [0.2.0] - 2026-04-17

### Added
- `wolfpack groom` now syncs each review-dir clone before pruning worktrees (uses `gt sync -f` when available, falls back to `git fetch --all --prune`); `--no-sync` bypasses
- `wolfpack hunt` detects Graphite PR stacks (base is not default/dev/main/master), fetches the parent base branch locally, and tells the subagent to review only the incremental diff; output table gains a `stack` column

### Changed
- `prep-worktree.sh` accepts `--base-ref <branch>` to fetch arbitrary bases
- Subagent summary JSON now includes `base_ref` and `stacked`

## [0.1.0] - 2026-04-16

### Added
- Initial jp tome scaffolding
- Migrated `standup-draft` skill
- Migrated `wolfpack` skill
