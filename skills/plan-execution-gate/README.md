# plan-execution-gate

A workflow skill that turns ad-hoc "let's plan this out" requests into a disciplined loop:

1. **Generate** a multi-phase plan document in an external Obsidian vault — `${PLANS_VAULT_DIR:-~/Documents/Obsidian/Plans}/<project-name>/NNN-<kebab-title>.md` — so local plans never pollute the code repo.
2. **Branch** off the project's main development branch before any Phase commit.
3. **Re-plan before each Phase** (from Phase 2 onward) — re-validate the remaining steps against what earlier Phases actually produced, and update the plan document in place if reality has diverged.
4. **Execute** each Phase, run scoped tests, then run an independent review pass in an **isolated context** (sub-agent or fresh session, using the bundled reviewer prompt) to verify the checklist actually landed.
5. **Commit** per Phase with a normal conventional-commit message describing only the code change — no plan number or Phase metadata in the message, and the vault plan file is never committed. Checkbox/Reviewed/commit-hash updates are written to the plan in the vault.
6. **Finalize** by appending a `## Test Cases` section that maps every Acceptance Criterion to a runnable case.

## Runtime-agnostic

The review pass is described as a *capability* (fresh context + reviewer persona), not as a specific tool. The skill ships its own reviewer prompt in [`references/reviewer-prompt.md`](references/reviewer-prompt.md) and provides adapters for Claude Code (`Agent` tool), Codex CLI (subprocess session), and generic agents (inline role switch). See `SKILL.md` § "Agent runtime adapters".

## When it triggers

- "生成方案并落地" / "写个 plan" / "save a plan"
- "执行 plan 003" / "run the message-center plan"
- "review phase 2" / "补充 test cases"

## Quick example

```
User: 帮我设计一下消息中心的重构方案，并落地。
→ Skill generates ~/Documents/Obsidian/Plans/<project>/NNN-message-center-refactor.md
  (with Obsidian frontmatter + Goals/Non-Goals/Phases/AC).
→ User says "开始执行".
→ Skill creates a feat/message-center branch, executes Phase 1, runs scoped tests,
  runs an independent review pass, commits the code only, updates the plan in the vault,
  then asks before starting Phase 2.
```

## Where it does NOT trigger

- Pure brainstorming with no intent to save.
- Single-step tasks (one command, one file edit).
- Discussions about an existing plan that don't ask for execution or review.

See [`SKILL.md`](SKILL.md) for the full protocol, branch gate recovery flow, reviewer-prompt invocation, runtime adapters, and Test Cases requirements.
