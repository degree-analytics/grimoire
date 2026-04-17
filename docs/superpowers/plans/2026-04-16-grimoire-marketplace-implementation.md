# Grimoire Marketplace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the first tome (`jp`) inside the grimoire marketplace, migrate the existing loose skills (`standup-draft`, `wolfpack`) into it, and verify the installed plugin invokes them correctly across machines.

**Architecture:** Secondbrain-lite. Single plugin named `jp` at `grimoire/plugins/jp/` with the standard Claude Code plugin layout (`.claude-plugin/plugin.json`, `skills/`, `commands/`, `agents/`, `hooks/`). Marketplace manifest at `grimoire/.claude-plugin/marketplace.json` registers the tome. No CI, no validation pipeline.

**Tech Stack:** Claude Code plugin system (`.claude-plugin/` manifests), `${CLAUDE_PLUGIN_ROOT}` env var for intra-plugin path references, bash scripts, git.

**Working directory for all tasks:** `/Users/jp/ws/x/grimoire`

---

## File Structure

After this plan completes:

```
grimoire/
├── .claude-plugin/
│   └── marketplace.json                  # MODIFIED: plugins[] lists jp
├── plugins/
│   └── jp/                               # NEW: first tome
│       ├── .claude-plugin/
│       │   └── plugin.json               # NEW: plugin metadata
│       ├── skills/
│       │   ├── standup-draft/
│       │   │   └── SKILL.md              # NEW: migrated from ~/.claude/skills/
│       │   └── wolfpack/
│       │       ├── SKILL.md              # NEW: migrated + paths rewritten
│       │       ├── scripts/              # NEW: migrated
│       │       ├── references/           # NEW: migrated
│       │       └── tests/                # NEW: migrated
│       ├── commands/.gitkeep             # NEW: placeholder
│       ├── agents/.gitkeep               # NEW: placeholder
│       ├── hooks/.gitkeep                # NEW: placeholder
│       └── CHANGELOG.md                  # NEW: empty skeleton
└── docs/superpowers/
    ├── specs/2026-04-16-grimoire-marketplace-design.md   # already exists
    └── plans/2026-04-16-grimoire-marketplace-implementation.md  # this file
```

After implementation completes and is verified:
- `~/.claude/skills/standup-draft/` — **deleted** (migrated)
- `~/.claude/skills/wolfpack/` — **deleted** (migrated)

---

## Task 1: Scaffold the `jp` tome directory structure

**Files:**
- Create: `plugins/jp/skills/.gitkeep`
- Create: `plugins/jp/commands/.gitkeep`
- Create: `plugins/jp/agents/.gitkeep`
- Create: `plugins/jp/hooks/.gitkeep`

- [ ] **Step 1: Create the directory tree and placeholder files**

```bash
cd /Users/jp/ws/x/grimoire
mkdir -p plugins/jp/{skills,commands,agents,hooks,.claude-plugin}
touch plugins/jp/skills/.gitkeep plugins/jp/commands/.gitkeep plugins/jp/agents/.gitkeep plugins/jp/hooks/.gitkeep
```

- [ ] **Step 2: Verify layout**

```bash
find plugins/jp -type d | sort
```

Expected:
```
plugins/jp
plugins/jp/.claude-plugin
plugins/jp/agents
plugins/jp/commands
plugins/jp/hooks
plugins/jp/skills
```

- [ ] **Step 3: Commit**

```bash
git add plugins/jp
git commit -m "feat: scaffold jp tome directory tree"
```

---

## Task 2: Create the `jp` tome's `plugin.json` and `CHANGELOG.md`

**Files:**
- Create: `plugins/jp/.claude-plugin/plugin.json`
- Create: `plugins/jp/CHANGELOG.md`

- [ ] **Step 1: Write `plugin.json`**

Create `plugins/jp/.claude-plugin/plugin.json` with this exact content:

```json
{
  "name": "jp",
  "version": "0.1.0",
  "description": "Personal skills, commands, and hooks.",
  "author": {
    "name": "jparkypark",
    "url": "https://github.com/jparkypark"
  }
}
```

- [ ] **Step 2: Write `CHANGELOG.md`**

Create `plugins/jp/CHANGELOG.md` with this exact content:

```markdown
# Changelog

## [0.1.0] - 2026-04-16

### Added
- Initial jp tome scaffolding
- Migrated `standup-draft` skill
- Migrated `wolfpack` skill
```

- [ ] **Step 3: Verify `plugin.json` is valid JSON**

```bash
jq . plugins/jp/.claude-plugin/plugin.json
```

Expected: JSON echoed back, no parse errors.

- [ ] **Step 4: Commit**

```bash
git add plugins/jp/.claude-plugin/plugin.json plugins/jp/CHANGELOG.md
git commit -m "feat: add jp tome manifest and changelog"
```

---

## Task 3: Register `jp` in the marketplace manifest

**Files:**
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Rewrite `marketplace.json`**

Replace the entire content of `.claude-plugin/marketplace.json` with:

```json
{
  "name": "grimoire",
  "owner": {
    "name": "jparkypark",
    "url": "https://github.com/jparkypark"
  },
  "metadata": {
    "description": "Personal Claude Code marketplace — a collection of spells (skills), tomes (plugins), incantations (commands), and runes (hooks).",
    "version": "0.1.0"
  },
  "plugins": [
    {
      "name": "jp",
      "source": "./plugins/jp",
      "description": "Personal skills, commands, and hooks.",
      "version": "0.1.0",
      "author": {
        "name": "jparkypark"
      }
    }
  ]
}
```

- [ ] **Step 2: Verify JSON is valid and registers the tome**

```bash
jq '.plugins[] | .name' .claude-plugin/marketplace.json
```

Expected: `"jp"`

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "feat: register jp tome in marketplace manifest"
```

---

## Task 4: Migrate `standup-draft` skill

**Files:**
- Create: `plugins/jp/skills/standup-draft/SKILL.md` (copy of existing)
- Delete: `plugins/jp/skills/.gitkeep` (no longer needed once skill is present)

- [ ] **Step 1: Copy the skill directory into the tome**

```bash
cp -R ~/.claude/skills/standup-draft plugins/jp/skills/standup-draft
```

- [ ] **Step 2: Verify the copy landed correctly**

```bash
ls plugins/jp/skills/standup-draft/
```

Expected: `SKILL.md` (and no other files — standup-draft is a single-file skill).

- [ ] **Step 3: Verify frontmatter is intact**

```bash
head -5 plugins/jp/skills/standup-draft/SKILL.md
```

Expected: frontmatter block starting with `---` and containing `name: standup-draft` and `description:`.

- [ ] **Step 4: Confirm no absolute path references to rewrite**

```bash
grep -rn "\.claude/skills/" plugins/jp/skills/standup-draft/ || echo "clean"
```

Expected: `clean`

- [ ] **Step 5: Remove the now-redundant `.gitkeep`**

```bash
rm plugins/jp/skills/.gitkeep
```

- [ ] **Step 6: Commit**

```bash
git add plugins/jp/skills/standup-draft plugins/jp/skills/.gitkeep
git commit -m "feat: migrate standup-draft skill into jp tome"
```

---

## Task 5: Migrate `wolfpack` skill (including script path rewrite)

**Files:**
- Create: `plugins/jp/skills/wolfpack/` (copy of existing, including subdirs)
- Modify: `plugins/jp/skills/wolfpack/SKILL.md` (rewrite 7 path references)

Wolfpack's SKILL.md references its own scripts by absolute path (`~/.claude/skills/wolfpack/...`) in 7 locations. Those will break after the move because the installed plugin lives under `~/.claude/plugins/cache/...`, not `~/.claude/skills/`. Claude Code exposes `${CLAUDE_PLUGIN_ROOT}` which resolves to the installed plugin's root; we use that instead.

- [ ] **Step 1: Copy the entire skill directory**

```bash
cp -R ~/.claude/skills/wolfpack plugins/jp/skills/wolfpack
```

- [ ] **Step 2: Verify all subdirectories copied**

```bash
find plugins/jp/skills/wolfpack -type f | sort
```

Expected (13 files):
```
plugins/jp/skills/wolfpack/SKILL.md
plugins/jp/skills/wolfpack/references/subagent-contract.md
plugins/jp/skills/wolfpack/references/subagent-prompt.md
plugins/jp/skills/wolfpack/scripts/ensure-clone.sh
plugins/jp/skills/wolfpack/scripts/groom.sh
plugins/jp/skills/wolfpack/scripts/inbox.sh
plugins/jp/skills/wolfpack/scripts/prep-worktree.sh
plugins/jp/skills/wolfpack/tests/fixtures/gh-search-prs.json
plugins/jp/skills/wolfpack/tests/test-ensure-clone.sh
plugins/jp/skills/wolfpack/tests/test-groom.sh
plugins/jp/skills/wolfpack/tests/test-inbox.sh
plugins/jp/skills/wolfpack/tests/test-prep-worktree.sh
```

- [ ] **Step 3: Confirm the expected path references exist before rewrite**

```bash
grep -n "~/.claude/skills/wolfpack/" plugins/jp/skills/wolfpack/SKILL.md
```

Expected: 7 matching lines referencing `~/.claude/skills/wolfpack/scripts/` or `~/.claude/skills/wolfpack/references/`.

- [ ] **Step 4: Rewrite absolute paths to use `${CLAUDE_PLUGIN_ROOT}`**

```bash
sed -i '' 's|~/\.claude/skills/wolfpack/|${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/|g' plugins/jp/skills/wolfpack/SKILL.md
```

- [ ] **Step 5: Verify rewrite replaced all 7 occurrences**

```bash
grep -c "~/\.claude/skills/wolfpack/" plugins/jp/skills/wolfpack/SKILL.md
```

Expected: `0`

```bash
grep -c '\${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/' plugins/jp/skills/wolfpack/SKILL.md
```

Expected: `7`

- [ ] **Step 6: Verify the scripts in the tome are executable**

```bash
ls -la plugins/jp/skills/wolfpack/scripts/*.sh | awk '{print $1, $NF}'
```

Expected: each line shows `-rwxr-xr-x` (or at least user-executable `x` bit). If any lack `x`, run `chmod +x plugins/jp/skills/wolfpack/scripts/*.sh plugins/jp/skills/wolfpack/tests/*.sh`.

- [ ] **Step 7: Also rewrite paths in any wolfpack script/reference files that reference themselves absolutely**

```bash
grep -rn "~/.claude/skills/wolfpack/" plugins/jp/skills/wolfpack/scripts plugins/jp/skills/wolfpack/references plugins/jp/skills/wolfpack/tests || echo "clean"
```

If `clean`, skip to Step 8. Otherwise, for each file listed:

```bash
sed -i '' 's|~/\.claude/skills/wolfpack/|${CLAUDE_PLUGIN_ROOT}/skills/wolfpack/|g' <file>
```

Then re-run the grep and confirm `clean`.

- [ ] **Step 8: Commit**

```bash
git add plugins/jp/skills/wolfpack
git commit -m "feat: migrate wolfpack skill into jp tome and rewrite paths to CLAUDE_PLUGIN_ROOT"
```

---

## Task 6: Install the grimoire marketplace locally and verify invocation

This task is interactive — it requires running slash commands inside a Claude Code session.

**Files:** none (runtime verification only)

- [ ] **Step 1: Add grimoire as a local marketplace**

In a Claude Code session, run:

```
/plugin marketplace add /Users/jp/ws/x/grimoire
```

Expected: confirmation that the `grimoire` marketplace was added.

- [ ] **Step 2: Install the `jp` plugin**

```
/plugin install jp@grimoire
```

Expected: confirmation that `jp` was installed.

- [ ] **Step 3: Start a fresh Claude Code session**

Plugin discovery happens at session start, so exit and restart the session to load the new skills.

- [ ] **Step 4: Confirm both skills appear under the `jp:` namespace**

In the new session, the skill list (loaded at session start) should include:
- `jp:standup-draft`
- `jp:wolfpack`

Ask Claude to list available skills matching "standup-draft" or "wolfpack" and confirm the namespace prefix is `jp:`.

- [ ] **Step 5: Smoke-test `jp:standup-draft` invocation**

Invoke the skill:

```
/jp:standup-draft
```

Or in a message: "use the jp:standup-draft skill".

Expected: the skill loads and begins its standard workflow (reviews last standup, scans backlog, etc.). No path-resolution errors.

- [ ] **Step 6: Smoke-test `jp:wolfpack` invocation**

Invoke the skill:

```
/jp:wolfpack
```

Expected: the skill loads and prints the usage block (since no subcommand was provided). The `${CLAUDE_PLUGIN_ROOT}` path references should resolve without error.

- [ ] **Step 7: Troubleshooting if either skill fails to load**

If the skill does not appear under `jp:` after a session restart:
- Verify the plugin shows as installed: check `~/.claude/plugins/installed_plugins.json` for a `jp` entry.
- Verify plugin.json parses: `jq . ~/.claude/plugins/cache/grimoire/*/plugins/jp/.claude-plugin/plugin.json`.
- Check Claude Code logs for plugin-loading errors.

If wolfpack fails with a path-resolution error:
- Verify `${CLAUDE_PLUGIN_ROOT}` resolves at runtime — add a debug echo in a test invocation.
- Confirm no `~/.claude/skills/wolfpack/` references remain: `grep -rn "\.claude/skills/wolfpack" ~/.claude/plugins/cache/grimoire/`.

Do not proceed to Task 7 until both skills invoke cleanly.

- [ ] **Step 8: No commit — verification only**

No file changes in this task.

---

## Task 7: Remove the original loose skills from `~/.claude/skills/`

Only run this task after Task 6 confirms both migrated skills work from the installed plugin. This establishes single-source-of-truth.

**Files:**
- Delete: `~/.claude/skills/standup-draft/`
- Delete: `~/.claude/skills/wolfpack/`

- [ ] **Step 1: Double-check the migrated copies are intact before removing originals**

```bash
test -f ~/ws/x/grimoire/plugins/jp/skills/standup-draft/SKILL.md && echo "standup-draft migrated OK"
test -f ~/ws/x/grimoire/plugins/jp/skills/wolfpack/SKILL.md && echo "wolfpack migrated OK"
```

Expected: both lines print their OK message.

- [ ] **Step 2: Remove the originals**

```bash
rm -rf ~/.claude/skills/standup-draft
rm -rf ~/.claude/skills/wolfpack
```

- [ ] **Step 3: Verify only expected contents remain under `~/.claude/skills/`**

```bash
ls ~/.claude/skills/ 2>/dev/null || echo "empty"
```

Expected: `empty` (or, if other personal skills have been added since this plan was written, only those — not `standup-draft` or `wolfpack`).

- [ ] **Step 4: Start a fresh Claude Code session and confirm skills still resolve under `jp:`**

The `jp:standup-draft` and `jp:wolfpack` skills should still work (they now only exist in the installed plugin). If they stop working, the originals were the ones Claude was loading — revert by re-copying from the migrated tome into `~/.claude/skills/` and investigate why the plugin install is not providing them.

- [ ] **Step 5: No commit — filesystem cleanup outside the git repo**

No changes to the grimoire repo in this task.

---

## Task 8: Push grimoire to GitHub

**Files:** none (remote operation)

- [ ] **Step 1: Confirm working tree is clean and all tasks committed**

```bash
cd /Users/jp/ws/x/grimoire
git status
```

Expected: `nothing to commit, working tree clean`.

- [ ] **Step 2: Review the commit log**

```bash
git log --oneline -n 10
```

Expected: the following commits from this plan are present (at the top, in order):
- feat: scaffold jp tome directory tree
- feat: add jp tome manifest and changelog
- feat: register jp tome in marketplace manifest
- feat: migrate standup-draft skill into jp tome
- feat: migrate wolfpack skill into jp tome and rewrite paths to CLAUDE_PLUGIN_ROOT
- docs: add grimoire marketplace design spec
- chore: initial scaffold

- [ ] **Step 3: Push to the remote**

```bash
git push origin main
```

Expected: push succeeds; remote tracking updates.

- [ ] **Step 4: Verify the remote received the commits**

```bash
git log --oneline origin/main -n 10
```

Expected: the same commits as Step 2 appear.

---

## Success criteria

All items from the spec's Success Criteria section:

- [x] `grimoire/plugins/jp/` exists with the directory shape defined in the spec — **Tasks 1, 2**
- [x] `grimoire/.claude-plugin/marketplace.json` lists the `jp` tome — **Task 3**
- [x] `/plugin install jp@grimoire` succeeds locally and the migrated skills are invocable as `jp:standup-draft` and `jp:wolfpack` — **Task 6**
- [x] `~/.claude/skills/standup-draft/` and `~/.claude/skills/wolfpack/` have been removed after verification — **Task 7**
- [x] Changes committed to the grimoire git repo and pushed to `github.com/jparkypark/grimoire` — **Task 8**
