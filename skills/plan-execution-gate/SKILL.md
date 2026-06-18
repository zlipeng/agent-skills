---
name: plan-execution-gate
description: |
  End-to-end workflow for multi-phase plans: generate → persist in an external Obsidian vault (per project) → branch → execute Phase-by-Phase with pre-Phase re-planning + isolated-context review gates → one commit per Phase (code only, no plan metadata) → append Test Cases.
  TRIGGER: "generate a plan and land it" / "write a plan" / "execute the plan" / "review the phase" / "生成方案并落地" / "写个 plan" / "执行 plan" / "review 一下 phase"; also when the user asks to save a plan, run an existing plan, review a completed Phase, or append Test Cases.
  DO NOT TRIGGER for pure brainstorming, work that does not need persistence, or single-step tasks.
---

# Plan Execution Gate

A complete loop: plan generation → persistence → phase-by-phase execution → review → test cases.

## 1. Plan Generation and Persistence

Plan documents are **not** stored inside the code repository. They live in an external Obsidian vault, organised per project, so that local plans never pollute the repo or other developers' history.

### Where plans are stored

Resolve the storage directory at runtime:

```bash
# Vault root: env var wins, otherwise the default Obsidian location.
PLANS_VAULT_DIR="${PLANS_VAULT_DIR:-$HOME/Documents/Obsidian/Plans}"
# Per-project subfolder, named by the repo (human-readable for Obsidian browsing).
PROJECT_NAME="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
PLAN_DIR="$PLANS_VAULT_DIR/$PROJECT_NAME"
mkdir -p "$PLAN_DIR"
```

- **Vault root**: `$PLANS_VAULT_DIR` if set, otherwise `~/Documents/Obsidian/Plans`.
- **Project subfolder**: the basename of the git toplevel (e.g. `agent-skills`). Two different repos that share a basename are disambiguated by the `project_root` field written into each plan's frontmatter (below); if a real collision occurs, suffix the folder (`agent-skills-2`) and keep `project_root` as the source of truth.

### Generation flow

When the user asks to generate a plan and land it:

1. Explore the relevant code to understand the current state.
2. Align with the user on requirements and boundaries.
3. Use the [plan template](references/plan-template.md) to draft a complete plan document, including the Obsidian frontmatter (below).
4. Resolve `PLAN_DIR` as above. Scan it, take the largest existing number `+1` (e.g. if the largest is `016-xxx.md`, the new file becomes `017-xxx.md`); if the folder is empty, start at `001`.
5. File name format: `{NNN}-{kebab-case-title}.md`.
6. Save it under `PLAN_DIR` using the Write tool (an absolute path outside the repo).
7. Ensure a per-project `_index.md` exists in `PLAN_DIR`; create it from the [index note](#per-project-index-note) on first use and add a row for the new plan.
8. Confirm the saved absolute path with the user.

### Obsidian frontmatter

Every plan begins with YAML frontmatter so Obsidian's Dataview / Tasks plugins can aggregate across projects:

```yaml
---
project: agent-skills
project_root: /abs/path/to/repo      # true identity of the owning repo
status: draft                        # draft | in-progress | done
created: {YYYY-MM-DD}
phase: 0/{N}                         # updated as Phases complete
tags: [plan]
---
```

### Per-project index note

`_index.md` is a lightweight map-of-content listing every plan in this project's folder and its status (one line per plan, e.g. `` - [[001-foo]] — in-progress (phase 2/4) ``). Keep it in sync when plans are added or change status; never put plan bodies in it.

### File-path references (clickable from Obsidian)

The plan lives in the vault, but the source code lives in the repo at `project_root` — a completely different location on disk. **Never cite a source file with a repo-relative or vault-relative path inside a markdown link**: Obsidian resolves the link target against the vault, the file isn't there, and the click fails.

Instead, write every source-file reference as a **VS Code deep link with an absolute path anchored at `project_root`**, including the line number when known:

```
[<short readable label>](vscode://file/<project_root>/<repo-relative-path>:<line>)
```

- Example: `[useAuth.ts:42](vscode://file/Users/me/work/plus-ops-frontend/src/hooks/useAuth.ts:42)` — clicking opens that file at line 42 in VS Code.
- The label stays human-readable (the repo-relative path or a symbol name); only the link **target** is the absolute `vscode://file/...` URI.
- `project_root` comes from the plan's frontmatter; `<project_root>` already begins with `/`, so `vscode://file` + the absolute path yields a single slash (`vscode://file/Users/...`).
- For a line **range**, link to the starting line (`:174`). For a whole-file reference, omit `:<line>`.
- This rule applies **everywhere** a file is cited: `Target area`, the current-state audit table, each Phase's `Files covered`, task descriptions, and the Test Cases `Paths` field.

The plan document MUST contain: background and current-state analysis, Goals / Non-Goals, key decisions (with rationale), phase-by-phase implementation steps (each Phase contains a `[ ]` checklist), Acceptance Criteria for each Phase, and dependency notes.

### Document language priority

The generated plan document's natural language MUST be selected in this order:

1. **Explicit user request** — if the user states a language for the document itself (e.g. "write the plan in Chinese", "用英文写这份 plan", "draft it in Japanese"), use that language.
2. **Conversation language** — otherwise, match the dominant natural language the user has been using in the current conversation. If the user has been writing in Chinese, the plan document is written in Chinese; if in Japanese, the plan is in Japanese; and so on.
3. **English fallback** — only when neither of the above gives a clear signal (e.g. mixed-language conversation with no preference stated, or a brand-new session with no user message yet), default to English.

Once the language is chosen, apply it consistently across the entire plan document — section headings, task descriptions, acceptance criteria, risk table, and review/commit annotations. Do not silently mix languages mid-document. The only exceptions are: code blocks, file paths, command snippets, identifiers, and proper nouns that have no natural translation.

## 2. Branch Gate (create a feature branch before execution)

**Before executing any Plan (before the first Phase 1 commit), you MUST create a dedicated feature branch off the main development branch.** Pushing Phase commits directly to `dev` / `main` is forbidden.

### Branch gate flow

1. **Verify the current branch** — before any Phase edit, run `git branch --show-current` and `git status`.
2. **Branch off the main development branch**:
   - Naming convention: first run `git branch -a | head -20` to observe the repository's existing feature-branch naming style (prefix such as `feat/` / `feature/` etc.) and follow it. If the repo has no clear convention, default to `feat/<short-kebab>`. **Do not embed the plan number in the branch name** — the plan lives outside the repo and its numbering must not leak into shared git history.
   - Command: `git checkout <base-branch> && git pull --ff-only && git checkout -b <new-branch>`, where `<base-branch>` is the repo's actual main development branch (commonly `main` / `master` / `dev` / `develop`).
3. **The first Phase commit MUST land on this new branch**, and so must every subsequent Phase commit. The plan-document updates (checkbox ticks, `**Reviewed**` notes, Test Cases, commit-hash backfill) are written to the plan file **in the Obsidian vault**, never committed to the repo.
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

## 3. Plan Execution Gate (Plan → Execute → Review, per Phase)

When executing a multi-phase plan (stored in the Obsidian vault, see §1), every Phase MUST follow a strict **re-plan → execute → review** loop. The two hard gates are:

- **Before** executing a Phase (from the second Phase onward), you MUST re-evaluate the remaining plan against what the previous Phases actually produced, and adjust it if necessary — so every Phase starts from an up-to-date plan rather than a stale one. See [Pre-Phase re-planning gate](#pre-phase-re-planning-gate).
- **After** completing a Phase, you MUST run a review **in an isolated context** (a sub-agent / fresh session that has NOT seen the implementer's reasoning); only after that review passes may you move on to the next Phase. See [Post-Phase review gate](#post-phase-review-gate).

### Pre-Phase re-planning gate

The plan written in §1 is a hypothesis. Earlier Phases routinely surface facts that invalidate later Phases (an API differs from what was assumed, a file was already refactored, a dependency is heavier than expected). **Executing a later Phase against an unrevised plan is forbidden** — re-confirm first.

Before starting **Phase 2 and every subsequent Phase**:

1. **Gather the actual outcomes of all completed Phases** — the review verdicts, the diffs that actually landed, any deviations recorded in the plan document, and any new constraints discovered.
2. **Compare them against the upcoming Phase's steps and Acceptance Criteria.** Ask explicitly: do the assumptions this Phase was written on still hold? Did earlier work already cover, remove, or change anything this Phase planned?
3. **Decide and act**:
   - **No change needed** → record a one-line note in the plan document (e.g. `**Re-planned**: <date> — no change, assumptions hold`) and proceed.
   - **Change needed** → update the plan document in place: rewrite the affected Phase's steps / checklist / Acceptance Criteria, add or remove Phases as required, and append a short `**Re-planned**: <date> — <what changed and why>` note. Keep the file-numbering and structure rules from §1. If the change is large enough to alter scope or user-visible behavior, confirm with the user before continuing.
4. **Only then** begin executing the Phase. The plan document is always the single source of truth — never carry plan changes only in your head.

This keeps every Phase on an explicit plan → execute path: you never execute a step that hasn't just been re-validated against reality.

### Post-Phase review gate

"Isolated review" means: the reviewer evaluates the Phase using the persona and checklist in [`references/reviewer-prompt.md`](references/reviewer-prompt.md) **from a clean context** — it must not inherit the implementer's chat history, intermediate reasoning, or hypotheses, so it cannot rubber-stamp its own assumptions. The reviewer re-reads the files from disk and judges only the evidence. How that isolation is achieved depends on the host agent runtime — see [Agent runtime adapters](#agent-runtime-adapters) below.

### Phase execution flow

1. **Complete every task inside the Phase** — every `[ ]` checkbox under the Phase is ticked, and the project's static gates (type-check / lint / build, if any) all pass.
2. **Run the impacted test suite (if it exists)** — identify the tests covering the code this Phase touched (unit, integration, or component tests), and run them with the project's own test command. When the project supports monorepo filters, tag filters, path filters, etc., **run only the relevant subset; full-suite runs are not required**. This step catches regressions of the form "code change type-checks but a runtime / rendering / unit-test assumption is broken" (typical example: a copy migration breaks a hard-coded assertion; a new Provider dependency in a component is not covered by the test wrapper). If the project has no test framework or the area touched by the current Phase has no existing tests, skip this step. If tests fail, fix them and re-run the review — skipping is forbidden.
3. **Run the review pass** — load [`references/reviewer-prompt.md`](references/reviewer-prompt.md) in full and fill the Part 2 template with:
   - `{n}` — the current Phase number
   - `{plan_path}` — the plan document path in the vault (e.g. `~/Documents/Obsidian/Plans/agent-skills/017-foo.md`)
   - `{file_list}` — every file path this Phase touched
   - `{acceptance_criteria}` — the Phase's Acceptance Criteria, verbatim

   Then execute the review **in an isolated context (a sub-agent or fresh session)** using the runtime-specific mechanism from [Agent runtime adapters](#agent-runtime-adapters). The reviewer prompt itself is identical across runtimes; only the *invocation mechanism* changes. Inline same-context review is a last resort, allowed only when the runtime has no sub-agent primitive.
4. **Act on the review verdict**:
   - PASS → mark every task in this Phase as `[x]` in the plan document and append a line `**Reviewed**: <date> by reviewer`.
   - FAIL → stay in the current Phase and fix the listed problems. **Do NOT** proceed to the next Phase. Re-run the review pass after fixes.
5. **Phase Commit Gate (mandatory commit)** — once the review passes, **you MUST create a single dedicated git commit before starting the next Phase**:
   - **Scope: commit only the key content — the source files this Phase actually changed.** The plan document lives in the external vault and **MUST NOT** be added to the commit; never `git add` the plan file or the vault. If unrelated dirty files exist, confirm with the user instead of mixing them in.
   - The project's static gates (type-check / lint / build) must pass; **never** skip commit hooks (no `--no-verify`, no `--no-gpg-sign`, etc.).
   - **The commit message describes only the actual code change**, as a normal conventional commit: `<type>(<scope>): <what changed>` (`type` is `feat` / `refactor` / `fix` etc., subject ≤ 72 chars), with an optional body summarising the key changes. **Do NOT embed the plan number, Phase number, "Reviewed on", or any other plan-process metadata in the message** — that information stays in the vault plan document, so local plans never leak into the shared repo history.
   - After creating the commit, run `git status` / `git log -1` to confirm success. Then update the plan document **in the vault**: tick this Phase's checkboxes, add the `**Reviewed**: <date>` note, bump `phase:` / `status:` in frontmatter, and backfill the commit hash + subject. Only then move to the next Phase.
   - **Forbidden**: committing the plan file (or anything from the vault) into the repo; bundling multiple Phases into one commit; committing while review has not passed; modifying Phase content after the commit (if a fix is needed, create a new follow-up commit and note it in the plan document).
6. **No parallel work across Phases** — unless the plan explicitly marks two Phases as dependency-free, run them strictly sequentially.

### Agent runtime adapters

The review pass has one non-negotiable requirement: **it must run in a context isolated from the implementation work** — a sub-agent or a fresh session that carries the reviewer persona but none of the implementer's history. Inheriting the current context defeats the gate, because a reviewer that already "knows" what the code was meant to do will confirm its own assumptions. Pick the strongest isolation your runtime offers, top to bottom:

- **Claude Code** — invoke the `/code-review` skill first (it runs the review against the diff in its own context). Pass the file list and plan context so the review targets the exact Phase diff. If `/code-review` is not available or fails, spawn a **dedicated sub-agent** via the `Agent` tool with `subagent_type: "code-reviewer"` (or `"general-purpose"`), passing the filled Part 2 template as the `prompt` with the Part 1 persona prepended. The sub-agent starts with a clean context by construction — this is the isolation guarantee, so prefer it over any inline pass.
- **Codex CLI** — run the native `/review` command first (fresh-context review of the Phase diff), piping the Phase diff and plan context. If `/review` is not available or fails, spawn a **new session** via the runtime's exec / subprocess command, piping the full filled `reviewer-prompt.md` (Part 1 + Part 2) as the initial message — again a clean context, not the current one.
- **Generic — only when the runtime truly has no sub-agent or sub-session primitive** — fall back to an *inline* review pass within the same agent. This is a degraded mode: it cannot fully shed the current context, so treat it as a last resort and call it out in the report. Mitigate the contamination as much as possible:
  1. Output a hard divider (e.g. `--- REVIEW PASS ---`) so the boundary is visible.
  2. Load the full `reviewer-prompt.md` and restate the persona before evaluating.
  3. Do NOT reference the implementation reasoning, partial diffs, or hypothesis from earlier in the session — re-read the files from disk and judge only what is on disk.
  4. Emit the review report in the exact output format defined by Part 2, and add a one-line note that the review ran inline (no isolated context available).

In all modes, the report MUST follow the output format in Part 2 of `reviewer-prompt.md`. The review verdict is the *report* produced in the isolated context, not the host agent's summary of it.

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
   - **Paths involved** — cite each source file as a VS Code deep link anchored at `project_root` (see [File-path references](#file-path-references-clickable-from-obsidian)), e.g. `[foo.ts:42](vscode://file/<project_root>/path/to/foo.ts:42)`; for UI cases include the page route / component path
   - **Expected result** (observable UI, log line, DB state, or event)
4. **Use the template** in [Plan template - Test Cases section](references/plan-template.md).
5. **Forbidden**: vague descriptions like "verify the feature works"; missing path references; no executable steps.

### Language

The `## Test Cases` section MUST use the same natural language as the rest of the plan document (per the document language priority defined in §1). Do not switch languages between the body of the plan and its test cases.

### Exemptions

Documentation-only plans (no code changes) do not need test cases.
