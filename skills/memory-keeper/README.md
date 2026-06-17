# memory-keeper

A skill for persisting **and recalling** durable knowledge across sessions. It distills project facts, conversation context, and user requirements/preferences into a per-project memory store under `~/.agents/memories/`, and loads them back when you return to the project.

## How it works

- **Per-project namespace.** Each project's memories live under `~/.agents/memories/<encoded-project-path>/`. The subdirectory name is the absolute project root path with every non-alphanumeric character replaced by `-`, mirroring how Claude Code names its `~/.claude/projects/` directories.
- **Index first.** An `index.md` table of contents is created before the first memory and kept in sync afterward — one line per memory, never the memory body.
- **One fact per file.** Each memory is a semantically-named `<topic>-<detail>.md` (e.g. `build-pnpm-commands.md`) with light YAML frontmatter classifying it as `user`, `feedback`, `project`, or `reference`.

## Triggering

The user can invoke the skill directly, or issue an instruction.

**Save:**

- "save this to memory" / "remember this"
- "记一下" / "保存记忆" / "记住这个"
- "summarize the project and keep it for later"

Saving is confirm-before-write: the skill first shows a report of exactly what it would persist (target paths, new vs. update, type, full content, index changes) and writes only after the user approves — so inaccurate content never lands and has to be reworked.

**Load:**

- "load project memory" / "read my memories" / "what do you remember about this project"
- "读取该项目记忆" / "加载记忆" / "回忆一下这个项目"

Loading reads `index.md` first for a cheap overview, then opens the relevant memory files (all of them on a broad request, only the matching ones on a scoped request), applies the facts, and gives a short briefing instead of dumping raw files.

It deliberately does **not** fire for facts that only matter to the current turn, things already recorded in the repo, or secrets.

See [`SKILL.md`](SKILL.md) for the full storage layout, path-encoding rule, templates, and workflow.
