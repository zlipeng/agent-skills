# agent-skills

[![skills.sh](https://skills.sh/b/zlipeng/agent-skills)](https://skills.sh/zlipeng/agent-skills)

Personal collection of [skills.sh](https://www.skills.sh/docs)-compatible agent skills, installable across Claude Code, Cursor, and any other agent that speaks the skills.sh protocol.

## Available Skills

| Skill | Trigger | Description |
|---|---|---|
| [`plan-execution-gate`](skills/plan-execution-gate/SKILL.md) | "生成方案并落地" / "执行 plan" / "写个 plan" / "review phase" | End-to-end workflow: generate a multi-phase plan, save it in an external Obsidian vault (per project), execute phase-by-phase with subagent review gates, commit only the code per Phase, and append test cases on completion. |
| [`memory-keeper`](skills/memory-keeper/SKILL.md) | "保存记忆" / "记住这个" / "读取该项目记忆" / "remember this" / "load project memory" | Save **and load** durable project facts, context, and user preferences in a per-project memory store under `~/.agents/memories/`, with an `index.md` table of contents and one semantic file per fact. |

## Installation

```bash
npx skills add zlipeng/agent-skills
```

This pulls every skill in this repo into your local skills directory (e.g. `~/.claude/skills/` for Claude Code). Run the command again to update.

To install a single skill only:

```bash
npx skills add zlipeng/agent-skills/plan-execution-gate
```

## Repository Layout

```
agent-skills/
├── AGENTS.md           # Conventions for AI agents maintaining this repo
├── CLAUDE.md           # Pointer for Claude Code → AGENTS.md
├── README.md           # This file
├── skills.sh.json      # Grouping + discovery metadata for skills.sh
├── LICENSE             # MIT
└── skills/
    ├── plan-execution-gate/
    │   ├── SKILL.md
    │   ├── metadata.json
    │   └── references/
    └── memory-keeper/
        ├── SKILL.md
        ├── metadata.json
        └── README.md
```

See [`AGENTS.md`](AGENTS.md) for the directory convention, SKILL.md template, and the workflow for adding new skills.

## License

[MIT](LICENSE) © 2026 zlipeng
