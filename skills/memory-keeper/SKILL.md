---
name: memory-keeper
description: |
  Summarize and persist durable knowledge — project facts, conversation context, or user requirements/preferences — into a per-project memory store under `~/.agents/memories/`.
  TRIGGER when: (1) the user invokes this skill directly; (2) the user says things like "save this to memory", "remember this", "记一下", "保存记忆", "记住这个", "把这个存到记忆里"; (3) the user states a durable preference, decision, or constraint worth carrying across sessions; (4) the user asks to summarize the project / context and keep it for later.
  DO NOT TRIGGER when: the fact only matters to the current turn, is already recorded in the repo (code, README, git history), or the user is just asking a question without wanting anything persisted.
---

# Memory Keeper

Distill what matters into one fact per file, and save it to a per-project memory store so it survives across sessions and agents.

## When to use

- The user explicitly asks to remember / save something ("保存记忆", "remember this", "记住").
- A durable fact surfaces that future sessions would benefit from: a user preference, a project goal or constraint, a non-obvious decision, or a pointer to an external resource.
- The user asks to summarize the project or current context for later reuse.

Do **not** save: things only relevant to this turn, facts already captured in the repo (code structure, past fixes, git history, CLAUDE.md/AGENTS.md), or secrets/credentials.

## Storage layout

All memories live under `~/.agents/memories/`, partitioned by the **project root path** so each project has its own namespace:

```
~/.agents/memories/
└── <encoded-project-path>/
    ├── index.md              # index of every memory in this project (always present)
    ├── <topic>-<detail>.md   # one fact per file, semantic kebab-case name
    └── ...
```

### Encoding the project path (Claude Code projects format)

The subdirectory name is the **absolute project root path** with every non-alphanumeric character replaced by `-`. This matches how Claude Code names its `~/.claude/projects/` directories.

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENCODED="$(printf '%s' "$PROJECT_ROOT" | sed 's/[^a-zA-Z0-9]/-/g')"
MEM_DIR="$HOME/.agents/memories/$ENCODED"
```

Example: `/Users/alice/Documents/github_workspace/agent-skills` → `-Users-alice-Documents-github-workspace-agent-skills`.

If there is no project context at all (no git root and the cwd is not meaningful), ask the user which project this memory belongs to rather than guessing.

## Workflow

1. **Resolve the memory directory** — compute `MEM_DIR` with the snippet above and create it: `mkdir -p "$MEM_DIR"`.
2. **Distill the fact** — reduce the content to the durable essence (1–2 short paragraphs). One file = one coherent fact. If the user dumped several unrelated facts, create several files.
3. **Check for duplicates first** — look at `index.md` and existing files in `MEM_DIR`. If a memory already covers this topic, **update that file in place** instead of creating a near-duplicate. Delete memories that have become wrong.
4. **Ensure the index exists** — if `index.md` is absent, create it from the [index template](#indexmd-template) before adding the first memory.
5. **Write the memory file** — name it `<topic>-<detail>.md` in semantic kebab-case (e.g. `build-pnpm-commands.md`, `user-prefers-terse-replies.md`, `auth-jwt-decision.md`). Use the [memory file template](#memory-file-template). Avoid generic names like `note-1.md`.
6. **Update the index** — add or update a one-line pointer in `index.md`: `` - [`<file>`](<file>) — <one-line hook> `` under the matching type heading.
7. **Confirm** — report the saved absolute path(s) back to the user.

## Memory file template

Each memory file is self-contained with light YAML frontmatter:

```markdown
---
title: <human-readable title>
type: user | feedback | project | reference
created: <YYYY-MM-DD>
tags: [<optional>, <kebab-tags>]
---

<The fact, stated plainly. For `feedback` and `project` memories, follow with:>

**Why:** <the reason / motivation this matters>
**How to apply:** <what to do differently because of it>

<Link related memories with [[other-file-slug]] (the filename without .md).>
```

Memory types:

- **user** — who the user is: role, expertise, standing preferences.
- **feedback** — guidance on how the agent should work (corrections or confirmed approaches); always include **Why** and **How to apply**.
- **project** — ongoing goals, constraints, or decisions not derivable from the code or git history; convert relative dates ("next week") to absolute dates.
- **reference** — pointers to external resources (URLs, tickets, dashboards).

## index.md template

```markdown
# Project memory index

> Memories for `<PROJECT_ROOT>`. One file per fact; this index is the table of contents.

## User
- [`user-prefers-terse-replies.md`](user-prefers-terse-replies.md) — wants concise, markdown answers

## Feedback
- [`feedback-branch-before-commit.md`](feedback-branch-before-commit.md) — always branch off main before committing

## Project
- [`project-q3-migration-goal.md`](project-q3-migration-goal.md) — migrate auth to OAuth2 by 2026-09-30

## Reference
- [`reference-design-doc.md`](reference-design-doc.md) — link to the architecture RFC
```

Keep the index to one line per memory — never put memory bodies in `index.md`. When a file is updated or deleted, update its index line to match (or remove it).

## Recall

These memories are written to be re-read at the start of future work on the same project: resolve `MEM_DIR` the same way, read `index.md`, and open the files whose hooks look relevant. A memory reflects what was true when written — if it names a file, flag, or function, verify that still exists before acting on it.
