# AGENTS.md

Guidance for AI agents (Claude Code, Cursor, etc.) maintaining this repository.

## Directory Conventions

- All skills live under `skills/<kebab-case-name>/`.
- Each skill directory MUST contain a `SKILL.md` with YAML frontmatter (`name` + `description`).
- Optional siblings: `metadata.json` (version, abstract, references), `README.md` (human-facing overview), `references/` (progressive-disclosure assets loaded on demand).
- Skill `name` in frontmatter MUST equal the directory name.
- Never put skill content at repo root — root is reserved for meta files (`README.md`, `AGENTS.md`, `CLAUDE.md`, `skills.sh.json`, `LICENSE`, `.gitignore`).

## SKILL.md Template

```markdown
---
name: my-skill
description: One-line trigger description. Include explicit trigger phrases users will say ("when X", "for Y workflow"). Keep under ~200 chars.
---

# My Skill

## When to use
- Trigger condition 1
- Trigger condition 2

## Workflow
1. Step one
2. Step two

## References
- See `references/<file>.md` for detail loaded on demand.
```

The `description` is the single most important field — it is what an agent's router matches against. Lead with action verbs and concrete trigger phrases, not abstract capability claims.

## Context Efficiency

- Keep `SKILL.md` under ~500 lines. Push long examples, schemas, or reference data into `references/` and link from `SKILL.md`.
- Progressive disclosure: only the SKILL.md is auto-loaded — referenced files are pulled in by the agent when needed.
- Avoid duplicating content between `SKILL.md` and `README.md`; the README is for humans browsing GitHub, the SKILL.md is for agent execution.
- Don't bake project-specific paths or usernames into skill content — keep skills portable.

## Adding a New Skill

1. Create `skills/<kebab-name>/SKILL.md` with valid frontmatter.
2. Add the skill name to the appropriate `groupings[].skills` array in `skills.sh.json` (or leave it ungrouped — it falls under `notGrouped`).
3. Append a row to the README "Available Skills" table.
4. Bump or set `metadata.json.version` (semver) for the skill.
5. Open a PR; the SKILL.md frontmatter is the contract — review it like an API change.
