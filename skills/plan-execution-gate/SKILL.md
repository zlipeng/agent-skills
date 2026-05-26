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

When executing a multi-phase plan under `plans/`, **after every Phase completion you MUST spawn a subagent to run an independent review; only after that review passes may you move on to the next Phase.**

### Required flow

1. **Complete every task inside the Phase** — every `[ ]` checkbox under the Phase is ticked, and the project's static gates (type-check / lint / build, if any) all pass.
2. **Run the impacted test suite (if it exists)** — identify the tests covering the code this Phase touched (unit, integration, or component tests), and run them with the project's own test command. When the project supports monorepo filters, tag filters, path filters, etc., **run only the relevant subset; full-suite runs are not required**. This step catches regressions of the form "code change type-checks but a runtime / rendering / unit-test assumption is broken" (typical example: a copy migration breaks a hard-coded assertion; a new Provider dependency in a component is not covered by the test wrapper). If the project has no test framework or the area touched by the current Phase has no existing tests, skip this step. If tests fail, fix them and re-run the review — skipping is forbidden.
3. **Spawn the review subagent** — use the `Agent` tool (`subagent_type: "code-reviewer"`) and pass:
   - The current Phase number and the file paths it covers
   - The corresponding plan document path (e.g. `plans/xxx-plan.md`)
   - The Phase's Acceptance Criteria
   - An explicit requirement: **verify each checklist item is actually implemented**, not merely that an interface exists.
   - An explicit requirement: **verify impacted tests still pass**, and write the executed test commands / results into the review output.
4. **Act on the review verdict**:
   - All pass → mark every task in this Phase as `[x]` in the plan document and append a line `**Reviewed**: <date> by code-reviewer`.
   - Anything outstanding → stay in the current Phase and fix it. **Do NOT** proceed to the next Phase.
5. **Phase Commit Gate (mandatory commit)** — once the review passes and the plan document's checkboxes are updated, **you MUST create a single dedicated git commit before starting the next Phase**:
   - Scope: include only the files this Phase actually changed (including the plan document's checkbox/Reviewed update). If unrelated dirty files exist, confirm with the user instead of mixing them in.
   - The project's static gates (type-check / lint / build) must pass; **never** skip commit hooks (no `--no-verify`, no `--no-gpg-sign`, etc.).
   - The commit message must point back to the Plan and Phase. Recommended format:
     - Subject: `<type>(plan-<NNN>): phase <n> - <Phase name>` (`type` is `feat` / `refactor` / `fix` etc., subject line ≤ 72 characters).
     - Body: list the checklist items completed in this Phase + a line `Reviewed by code-reviewer on <date>`.
   - After creating the commit, run `git status` / `git log -1` to confirm success, then move to the next Phase.
   - **Forbidden**: bundling multiple Phases into one commit; committing while review has not passed; modifying Phase content after the commit (if a fix is needed, create a new follow-up commit and note it in the plan document).
6. **No parallel work across Phases** — unless the plan explicitly marks two Phases as dependency-free, run them strictly sequentially.

### Review subagent prompt template

```
Review the implementation of Phase {n} in {plan_path}.

Files covered: {file_list}

Requirements:
- Do not trust the task description; read the actual code.
- Verify every checklist item: items declared as deleted must be actually gone; items declared as added must be wired into the default path.
- If something looks "done" only as docs / type / scaffolding while the runtime path is still disconnected, you MUST mark it failed.
- Verify each Acceptance Criterion is genuinely satisfied.
- Run impacted tests: first identify the project's test runner and filtering mechanism (package.json scripts / Makefile / pyproject.toml / Cargo.toml / `go test` ...), use the project-native command to run only the test subset relevant to the touched files, and record the result in the report. Any test failure → FAIL. If the touched area has no existing tests, explicitly state "no impacted tests".

Output format:
- PASS / FAIL
- Per-checklist verification result (✅/❌ + evidence)
- Actual test commands executed + pass/fail summary (or "no impacted tests")
- If FAIL, list concrete problems and suggested fixes.
```

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
