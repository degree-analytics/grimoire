# grimoire

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace.

> A grimoire is a book of spells. This one holds mine.

## Vocabulary

| Term | Meaning |
|------|---------|
| **grimoire** | this marketplace |
| **tomes** | plugins (grouped collections) |
| **spells** | skills |
| **incantations** | slash commands |
| **runes** | hooks |

## Install

```bash
# In Claude Code:
/plugin marketplace add jparkypark/grimoire

# Or in terminal:
claude plugin marketplace add jparkypark/grimoire
```

Then browse available tomes:

```bash
/plugin
```

## Structure

```
grimoire/
├── .claude-plugin/
│   └── marketplace.json    # marketplace manifest
├── plugins/                # tomes live here
│   └── <tome-name>/
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── skills/         # spells
│       ├── commands/       # incantations
│       └── hooks/          # runes
└── README.md
```

## Adding a new tome

1. Create `plugins/<tome-name>/.claude-plugin/plugin.json`
2. Add skills, commands, or hooks under that directory
3. Register the tome in `.claude-plugin/marketplace.json` under `plugins`

## License

MIT
