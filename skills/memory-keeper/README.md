# memory-keeper

A skill for persisting durable knowledge across sessions. It distills project facts, conversation context, and user requirements/preferences into a per-project memory store under `~/.agents/memories/`.

## How it works

- **Per-project namespace.** Each project's memories live under `~/.agents/memories/<encoded-project-path>/`. The subdirectory name is the absolute project root path with every non-alphanumeric character replaced by `-`, mirroring how Claude Code names its `~/.claude/projects/` directories.
- **Index first.** An `index.md` table of contents is created before the first memory and kept in sync afterward — one line per memory, never the memory body.
- **One fact per file.** Each memory is a semantically-named `<topic>-<detail>.md` (e.g. `build-pnpm-commands.md`) with light YAML frontmatter classifying it as `user`, `feedback`, `project`, or `reference`.

## Triggering

The user can invoke the skill directly, or issue an instruction such as:

- "save this to memory" / "remember this"
- "记一下" / "保存记忆" / "记住这个"
- "summarize the project and keep it for later"

It deliberately does **not** fire for facts that only matter to the current turn, things already recorded in the repo, or secrets.

See [`SKILL.md`](SKILL.md) for the full storage layout, path-encoding rule, templates, and workflow.
