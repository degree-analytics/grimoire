# Changelog

## [0.3.0] - 2026-04-30

### Added
- **revelio** skill — PR summary that synthesizes ticket, description,
  review discussion, and diff into a structured report

## [0.2.0] - 2026-04-17

### Added
- `wolfpack groom` now syncs each review-dir clone before pruning worktrees (uses `gt sync -f` when available, falls back to `git fetch --all --prune`); `--no-sync` bypasses
- `wolfpack hunt` detects Graphite PR stacks (base is not default/dev/main/master), fetches the parent base branch locally, and tells the subagent to review only the incremental diff; output table gains a `stack` column

### Changed
- Clone layout is now `~/ws/review/<owner>/<repo>/` (was `~/ws/review/<repo>/`) so cross-org reviews with the same repo short name don't collide
- Report filenames are now `<owner>__<repo>-pr<n>.md` (was `<repo>-pr<n>.md`)
- `groom.sh` derives owner per-worktree from the path — the `--repo-owner` flag is removed
- `prep-worktree.sh` accepts `--base-ref <branch>` to fetch arbitrary bases
- Subagent summary JSON now includes `base_ref` and `stacked`

### Fixed
- `wolfpack groom` no longer breaks on an empty review inbox (the `--repo-owner` derivation that crashed on null has been eliminated)

## [0.1.0] - 2026-04-16

### Added
- Initial jp tome scaffolding
- Migrated `standup-draft` skill
- Migrated `wolfpack` skill
