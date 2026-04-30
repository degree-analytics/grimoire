# grimoire

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace.

> A grimoire is a book of spells. This one holds mine.

## Spellbook

| Spell | What it does |
|-------|-------------|
| `/cast:praepario` | Situational awareness — recent completions, active work, PR status, project progress, flags, and recommendations |
| `/cast:oppugno` | Batch PR review — tidies stale worktrees, then dispatches parallel review agents at your GitHub inbox |
| `/cast:revelio` | PR summary — synthesizes ticket context, implementation, review discussion, and concerns into a structured report |

## Install

```bash
# In Claude Code:
/plugin marketplace add jparkypark/grimoire

# Or in terminal:
claude plugin marketplace add jparkypark/grimoire
```

Then browse available plugins:

```bash
/plugin
```

## Structure

```
grimoire/
├── .claude-plugin/
│   └── marketplace.json    # marketplace manifest
├── plugins/
│   └── cast/               # personal spellbook
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── skills/
│       │   ├── praepario/
│       │   ├── oppugno/
│       │   └── revelio/
│       ├── commands/
│       └── hooks/
└── README.md
```

## Adding a new plugin

1. Create `plugins/<name>/.claude-plugin/plugin.json`
2. Add skills, commands, or hooks under that directory
3. Register in `.claude-plugin/marketplace.json` under `plugins`

## License

MIT
