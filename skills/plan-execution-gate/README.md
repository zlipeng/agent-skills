# plan-execution-gate

A workflow skill that turns ad-hoc "let's plan this out" requests into a disciplined loop:

1. **Generate** a multi-phase plan document under `plans/NNN-<kebab-title>.md`.
2. **Branch** off the project's main development branch before any Phase commit.
3. **Execute** each Phase, run scoped tests, then spawn a `code-reviewer` subagent to verify the checklist actually landed.
4. **Commit** per Phase with a `<type>(plan-NNN): phase <n> - <name>` message — no batching, no skipping the hook.
5. **Finalize** by appending a `## Test Cases` section that maps every Acceptance Criterion to a runnable case.

## When it triggers

- "生成方案并落地" / "写个 plan" / "save a plan to plans/"
- "执行 plan 003" / "run plans/003-foo.md"
- "review phase 2" / "补充 test cases"

## Quick example

```
User: 帮我设计一下消息中心的重构方案，并落地。
→ Skill generates plans/NNN-message-center-refactor.md with Goals/Non-Goals/Phases/AC.
→ User says "开始执行".
→ Skill creates feat/plan-NNN-message-center branch, executes Phase 1, runs scoped tests,
  spawns code-reviewer, commits, then asks before starting Phase 2.
```

## Where it does NOT trigger

- Pure brainstorming with no intent to save.
- Single-step tasks (one command, one file edit).
- Discussions about an existing plan that don't ask for execution or review.

See [`SKILL.md`](SKILL.md) for the full protocol, branch gate recovery flow, review subagent prompt template, and Test Cases requirements.
