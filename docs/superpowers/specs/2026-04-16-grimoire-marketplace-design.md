# Grimoire Marketplace — Design

**Date:** 2026-04-16
**Status:** Design approved, pending implementation plan

## Problem

I want a personal Claude Code plugin marketplace — a single repo where my custom skills, slash commands, and hooks live under version control, survive `~/.claude/` wipes, and sync across machines. Today my personal skills live loose in `~/.claude/skills/` (`standup-draft`, `wolfpack`), with no git, no packaging, no cross-machine sync.

## Goals

- Single source of truth for all my personal Claude Code assets
- Versioned, pushable, installable on any machine I work from
- Lightweight — no CI, no validation pipelines, no contribution workflow
- Consistent with the plugin shape I already use daily (secondbrain's ciq/eng/exp/ops plugins)

## Non-goals

Explicitly **not** building (vs secondbrain):

- CI / GitHub Actions / pre-commit hooks
- SKILL.md schema validation or linting
- Maturity model, scoring, or graduation workflow
- `namespace-config.json`, bragi scoring, install-count tracking
- Submission or contribution docs
- Marketplace-level `bin/`, `tests/`, `conftest.py`, `config/`, `data/`

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Marketplace name | `grimoire` | Already scaffolded; personal, memorable |
| Remote | `github.com/jparkypark/grimoire` | Personal GitHub, private, cross-machine sync |
| Approach | "Secondbrain-lite" | Same structural patterns, none of the marketplace-level tooling |
| First tome | `jp` | Matches the `ciq:` / `eng:` / `exp:` / `ops:` convention |
| Number of tomes | One for now | Split later if the tome grows unwieldy |
| Scope | Full plugin (skills, commands, agents, hooks) | Future-proof the shape even if early content is skills-only |

**Vocabulary note:** The README uses themed names (grimoire / tome / spell / incantation / rune) as a vocabulary table. They should stay light flavoring, not force-applied throughout the codebase. File paths, manifest keys, and technical docs use the Claude Code canonical terms (plugin, skill, command, hook).

## Architecture

### Current repo state (already scaffolded)

```
grimoire/
├── .claude-plugin/
│   └── marketplace.json       # manifest, plugins: [] empty
├── plugins/
│   └── .gitkeep
├── .gitignore
└── README.md
```

### Target state after implementation

```
grimoire/
├── .claude-plugin/
│   └── marketplace.json       # plugins: [{ name: "jp", source: "./plugins/jp", ... }]
├── plugins/
│   └── jp/
│       ├── .claude-plugin/
│       │   └── plugin.json    # name, version, description
│       ├── skills/
│       │   ├── standup-draft/SKILL.md
│       │   └── wolfpack/SKILL.md
│       ├── commands/
│       │   └── .gitkeep
│       ├── agents/
│       │   └── .gitkeep
│       ├── hooks/
│       │   └── .gitkeep
│       └── CHANGELOG.md
├── docs/
│   └── superpowers/specs/
│       └── 2026-04-16-grimoire-marketplace-design.md
├── .gitignore
└── README.md
```

Empty directories get `.gitkeep` until populated.

## Migration

Existing loose skills at `~/.claude/skills/` move into the `jp` tome:

1. Copy `~/.claude/skills/standup-draft/` → `grimoire/plugins/jp/skills/standup-draft/`
2. Copy `~/.claude/skills/wolfpack/` → `grimoire/plugins/jp/skills/wolfpack/`
3. Install grimoire locally, verify `jp:standup-draft` and `jp:wolfpack` invoke correctly
4. Delete the original `~/.claude/skills/<name>/` directories (one source of truth)

Post-migration, the skills surface with `jp:` prefix matching the marketplace-loaded convention.

## Dev workflow

- **Edit**: directly in `~/ws/x/grimoire/plugins/jp/skills/<name>/SKILL.md`
- **Install locally (first time)**: `/plugin marketplace add ~/ws/x/grimoire`, then `/plugin install jp@grimoire`
- **Iterate**: edit files; Claude picks up changes on next session (plugin manifest/frontmatter reloads on session start; SKILL.md body is read at invocation)
- **Ship**: `git commit && git push`
- **Install on other machines**: `/plugin marketplace add jparkypark/grimoire` + `/plugin install jp@grimoire`

## Risks and open questions

- **Skill namespace collisions**: unlikely since `jp:` is not used by any other installed marketplace, but worth verifying at install time.
- **Migration correctness**: if `standup-draft` or `wolfpack` reference absolute paths under `~/.claude/skills/`, those references will break after the move. Plan step should audit their internals before copying.
- **Future tome split**: if this balloons, we add a second tome and the marketplace manifest already supports multiple entries. No refactor cost.

## Success criteria

- `grimoire/plugins/jp/` exists with the directory shape above
- `grimoire/.claude-plugin/marketplace.json` lists the `jp` tome
- `/plugin install jp@grimoire` succeeds locally and the migrated skills are invocable as `jp:standup-draft` and `jp:wolfpack`
- `~/.claude/skills/standup-draft/` and `~/.claude/skills/wolfpack/` have been removed after verification
- Changes committed to the grimoire git repo and pushed to `github.com/jparkypark/grimoire`
