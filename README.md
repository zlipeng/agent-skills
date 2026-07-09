# agent-skills

[![skills.sh](https://skills.sh/b/zlipeng/agent-skills)](https://skills.sh/zlipeng/agent-skills)

Personal collection of [skills.sh](https://www.skills.sh/docs)-compatible agent skills, installable across Claude Code, Cursor, and any other agent that speaks the skills.sh protocol.

## Available Skills

| Skill | Trigger | Description |
|---|---|---|
| [`plan-execution-gate`](skills/plan-execution-gate/SKILL.md) | "生成方案并落地" / "执行 plan" / "写个 plan" / "review phase" | End-to-end workflow: generate a multi-phase plan, save it in an external Obsidian vault (per project), execute phase-by-phase with subagent review gates, commit only the code per Phase, and append test cases on completion. |
| [`memory-keeper`](skills/memory-keeper/SKILL.md) | "保存记忆" / "记住这个" / "读取该项目记忆" / "remember this" / "load project memory" | Save **and load** durable project facts, context, and user preferences in a per-project memory store under `~/.agents/memories/`, with an `index.md` table of contents and one semantic file per fact. |
| [`swagger-explorer`](skills/swagger-explorer/SKILL.md) | "解析 swagger" / "swagger 里 /xxx 的入参" / "find an endpoint in this api-docs" / pasting a Swagger UI URL | Parse Swagger 2.0 / OpenAPI 3.x JSON specs by URL — accepts both raw `api-docs` URLs and Swagger UI URLs (auto-resolved via `/v3/api-docs/swagger-config` or `/swagger-resources`) — without loading the whole document into context. `jq` + local cache (`~/.cache/swagger-skill/`) — list / search the index, then fetch single endpoints by path or `operationId` with `$ref`s inlined. Includes a path-prefix registry so `fetch.sh --path <api-path>` recovers the swagger URL when the user only gives an API path; fetch.sh auto-registers a spec's common prefix on success. |
| [`frontend-module-api-digest`](skills/frontend-module-api-digest/SKILL.md) | "调研某页面的模块和接口" / "字段来自哪个接口" / "这些 code 怎么展示成名称" / "Dashboard 这个卡片的数据从哪来" | Investigate any frontend view (page, Section/Tab, modal, drawer, Dashboard card, chart, filter form, list, detail page) and summarize each module's displayed fields (label / key / column / filter item / metric) against the query API that feeds them. Only query endpoints, real HTTP method + path (not the generated fn name), per-field source tracing, full code->name mapping chains, per-view-type field schemas, ending with a global query-endpoint summary table. |

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
    ├── memory-keeper/
    │   ├── SKILL.md
    │   ├── metadata.json
    │   └── README.md
    ├── swagger-explorer/
    │   ├── SKILL.md
    │   ├── metadata.json
    │   ├── scripts/      # resolve / fetch / list / search / get
    │   └── references/   # jq cookbook, v2-vs-v3 notes
    └── frontend-module-api-digest/
        ├── SKILL.md
        ├── metadata.json
        └── README.md
```

See [`AGENTS.md`](AGENTS.md) for the directory convention, SKILL.md template, and the workflow for adding new skills.

## License

[MIT](LICENSE) © 2026 zlipeng
