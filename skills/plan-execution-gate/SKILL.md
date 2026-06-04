---
name: plan-execution-gate
description: |
  End-to-end workflow for generating, persisting, and executing multi-phase plans with strict Phase-by-Phase review gates.
  TRIGGER when: (1) user asks to generate a plan / spec / proposal and save it under `plans/`; (2) user asks to execute a multi-phase plan from `plans/`; (3) the conversation contains intents like "generate a plan and land it", "write a plan", "execute the plan", "review the phase", "生成方案并落地", "写个 plan", "执行 plan", "review 一下 phase"; (4) user wants to review a completed Phase or append a Test Cases section.
  DO NOT TRIGGER when: the user is only brainstorming, does not need persistence, or the task is a single-step operation.
---

# Plan Execution Gate

A complete loop: plan generation → persistence → phase-by-phase execution → review → test cases.

## 1. Plan Generation and Persistence

When the user asks to generate a plan and land it:

1. Explore the relevant code to understand the current state.
2. Align with the user on requirements and boundaries.
3. Use the [plan template](references/plan-template.md) to draft a complete plan document.
4. Scan the `plans/` directory, take the largest existing number `+1` (e.g. if the largest is `016-xxx.md`, the new file becomes `017-xxx.md`).
5. File name format: `{NNN}-{kebab-case-title}.md`.
6. Save it under `plans/` using the Write tool.
7. Confirm the saved path with the user.

The plan document MUST contain: background and current-state analysis, Goals / Non-Goals, key decisions (with rationale), phase-by-phase implementation steps (each Phase contains a `[ ]` checklist), Acceptance Criteria for each Phase, and dependency notes.

### Document language priority

The generated plan document's natural language MUST be selected in this order:

1. **Explicit user request** — if the user states a language for the document itself (e.g. "write the plan in Chinese", "用英文写这份 plan", "draft it in Japanese"), use that language.
2. **Conversation language** — otherwise, match the dominant natural language the user has been using in the current conversation. If the user has been writing in Chinese, the plan document is written in Chinese; if in Japanese, the plan is in Japanese; and so on.
3. **English fallback** — only when neither of the above gives a clear signal (e.g. mixed-language conversation with no preference stated, or a brand-new session with no user message yet), default to English.

Once the language is chosen, apply it consistently across the entire plan document — section headings, task descriptions, acceptance criteria, risk table, and review/commit annotations. Do not silently mix languages mid-document. The only exceptions are: code blocks, file paths, command snippets, identifiers, and proper nouns that have no natural translation.

## 2. Branch Gate (create a feature branch before execution)

**Before executing any Plan (before the first Phase 1 commit), you MUST create a dedicated feature branch off the main development branch.** Pushing Phase commits directly to `dev` / `main` is forbidden.

### Required flow

1. **Verify the current branch** — before any Phase edit, run `git branch --show-current` and `git status`.
2. **Branch off the main development branch**:
   - Naming convention: first run `git branch -a | head -20` to observe the repository's existing feature-branch naming style (prefix such as `feat/` / `feature/` / `plan-` etc., whether it carries a number) and follow it. If the repo has no clear convention, default to `feat/plan-<NNN>-<short-kebab>`.
   - Command: `git checkout <base-branch> && git pull --ff-only && git checkout -b <new-branch>`, where `<base-branch>` is the repo's actual main development branch (commonly `main` / `master` / `dev` / `develop`).
3. **The first Phase commit MUST land on this new branch.** All subsequent Phase commits, Test Cases additions, and commit-hash backfills happen on the same branch.
4. **Do NOT push or open a PR on your own initiative** — branch push and PR timing are decided by the user, unless the user explicitly tells you otherwise.
5. **Do NOT switch back to `dev` / `main` to make plan-related changes.**

### Recovery when a Phase commit lands on the main branch by mistake

If a Phase commit has already been committed directly to a main branch (`main` / `master` / `dev` etc.):

1. **Do NOT** run `git reset --hard` directly on the main branch (destructive and easy to lose work in progress).
2. Create a new branch at the current HEAD to preserve all commits: `git checkout -b <new-feature-branch>`.
3. Move the main-branch pointer back to origin: `git branch -f <base-branch> origin/<base-branch>` (you are already on the feature branch, so this is safe and does not touch the working tree).
4. Verify: `git log --oneline <base-branch> -1` should equal `origin/<base-branch>`, and `git log --oneline <new-feature-branch> -1` should still point to the latest Phase commit.

### Exemptions

- When the Plan explicitly declares it is a documentation-only change (no code changes) and has only one Phase, a single commit directly on the main branch is allowed.
- The user explicitly instructs you in the conversation to "commit directly to the main branch".

## 3. Plan Execution Gate (Phase-by-Phase Review)

When executing a multi-phase plan under `plans/`, **after every Phase completion you MUST run an independent review pass; only after that review passes may you move on to the next Phase.**

"Independent review pass" means: the reviewer evaluates the Phase using the persona and checklist in [`references/reviewer-prompt.md`](references/reviewer-prompt.md), without being anchored to the implementer's reasoning. How that isolation is achieved depends on the host agent runtime — see [Agent runtime adapters](#agent-runtime-adapters) below.

### Required flow

1. **Complete every task inside the Phase** — every `[ ]` checkbox under the Phase is ticked, and the project's static gates (type-check / lint / build, if any) all pass.
2. **Run the impacted test suite (if it exists)** — identify the tests covering the code this Phase touched (unit, integration, or component tests), and run them with the project's own test command. When the project supports monorepo filters, tag filters, path filters, etc., **run only the relevant subset; full-suite runs are not required**. This step catches regressions of the form "code change type-checks but a runtime / rendering / unit-test assumption is broken" (typical example: a copy migration breaks a hard-coded assertion; a new Provider dependency in a component is not covered by the test wrapper). If the project has no test framework or the area touched by the current Phase has no existing tests, skip this step. If tests fail, fix them and re-run the review — skipping is forbidden.
3. **Run the review pass** — load [`references/reviewer-prompt.md`](references/reviewer-prompt.md) in full and fill the Part 2 template with:
   - `{n}` — the current Phase number
   - `{plan_path}` — the plan document path (e.g. `plans/017-foo.md`)
   - `{file_list}` — every file path this Phase touched
   - `{acceptance_criteria}` — the Phase's Acceptance Criteria, verbatim

   Then execute the review using the runtime-specific mechanism from [Agent runtime adapters](#agent-runtime-adapters). The reviewer prompt itself is identical across runtimes; only the *invocation mechanism* changes.
4. **Act on the review verdict**:
   - PASS → mark every task in this Phase as `[x]` in the plan document and append a line `**Reviewed**: <date> by reviewer`.
   - FAIL → stay in the current Phase and fix the listed problems. **Do NOT** proceed to the next Phase. Re-run the review pass after fixes.
5. **Phase Commit Gate (mandatory commit)** — once the review passes and the plan document's checkboxes are updated, **you MUST create a single dedicated git commit before starting the next Phase**:
   - Scope: include only the files this Phase actually changed (including the plan document's checkbox/Reviewed update). If unrelated dirty files exist, confirm with the user instead of mixing them in.
   - The project's static gates (type-check / lint / build) must pass; **never** skip commit hooks (no `--no-verify`, no `--no-gpg-sign`, etc.).
   - The commit message must point back to the Plan and Phase. Recommended format:
     - Subject: `<type>(plan-<NNN>): phase <n> - <Phase name>` (`type` is `feat` / `refactor` / `fix` etc., subject line ≤ 72 characters).
     - Body: list the checklist items completed in this Phase + a line `Reviewed on <date>`.
   - After creating the commit, run `git status` / `git log -1` to confirm success, then move to the next Phase.
   - **Forbidden**: bundling multiple Phases into one commit; committing while review has not passed; modifying Phase content after the commit (if a fix is needed, create a new follow-up commit and note it in the plan document).
6. **No parallel work across Phases** — unless the plan explicitly marks two Phases as dependency-free, run them strictly sequentially.

### Agent runtime adapters

The review pass needs *fresh context* and *reviewer persona* — nothing more. Pick the mechanism that fits your runtime. **Always prefer the runtime's native review command over a generic sub-agent when one is available:**

- **Claude Code** — invoke the `/code-review` skill first. Pass the file list and plan context so the review targets the exact Phase diff. If `/code-review` is not available or fails, fall back to the `Agent` tool with `subagent_type: "code-reviewer"` (or `"general-purpose"`), passing the filled Part 2 template as the `prompt` with the Part 1 persona prepended.
- **Codex CLI** — run the native `/review` command first, piping the Phase diff and plan context. If `/review` is not available or fails, fall back to spawning a new session via the runtime's exec / subprocess command, piping the full filled `reviewer-prompt.md` (Part 1 + Part 2) as the initial message.
- **Generic / no sub-agent primitive available** — perform an *inline* review pass within the same agent, but with explicit role switching:
  1. Output a hard divider (e.g. `--- REVIEW PASS ---`) so the boundary is visible.
  2. Load the full `reviewer-prompt.md` and restate the persona before evaluating.
  3. Do NOT reference the implementation reasoning, partial diffs, or hypothesis from earlier in the session — re-read the files from disk.
  4. Emit the review report in the exact output format defined by Part 2.

In all three modes, the report MUST follow the output format in Part 2 of `reviewer-prompt.md`. The review verdict is the *report*, not the host agent's summary of it.

### Exemptions

A plan that is documentation-only or contains a single task (only one Phase) is not required to go through this gate.

## 4. Plan Completion Test Cases

Once every Phase of the Plan is complete and review has passed, **you MUST append a `## Test Cases` section to the end of the plan document.**

### Requirements

1. **Location**: append at the very bottom of the plan document, right after the last Phase's `**Reviewed**` annotation.
2. **Coverage**: every Acceptance Criterion declared in the Plan must have at least one matching test case; key interactions and boundary scenarios get their own cases.
3. **Each test case MUST contain**:
   - **Title** (a short description of what is verified)
   - **Preconditions** (environment, data, entry state)
   - **Steps** (numbered 1/2/3..., each step concrete to a click / input / command)
   - **Paths involved** (source-file path + line number, format `path/to/file.ts:42`; for UI cases include the page route / component path)
   - **Expected result** (observable UI, log line, DB state, or event)
4. **Use the template** in [Plan template - Test Cases section](references/plan-template.md).
5. **Forbidden**: vague descriptions like "verify the feature works"; missing path references; no executable steps.

### Language

The `## Test Cases` section MUST use the same natural language as the rest of the plan document (per the document language priority defined in §1). Do not switch languages between the body of the plan and its test cases.

### Exemptions

Documentation-only plans (no code changes) do not need test cases.
