# Plan template

Use the structure below when generating a Plan document. The plan is saved in the Obsidian vault at `${PLANS_VAULT_DIR:-~/Documents/Obsidian/Plans}/<project-name>/`, not in the code repo. Number the file from `max(existing plans in that folder) + 1`.

> **Language note**: this template is shown in English, but the actual plan document must be written in the language selected by the SKILL.md "Document language priority" rule — the user's explicit request first, the conversation language second, English only as the final fallback. Translate the section headings below into the chosen language when you generate the plan.

```markdown
---
project: {project-name}
project_root: {/abs/path/to/repo}
status: draft            # draft | in-progress | done
created: {YYYY-MM-DD}
phase: 0/{N}
tags: [plan]
---

# Plan {NNN} — {Title}

> **Status**: Draft
> **Owner**: TBD
> **Created**: {YYYY-MM-DD}
> **Depends on**: {external dependency or prior plan; write "none" if there is none}
> **Target area**: {primary directories or file paths involved}

## 1. Background

### 1.1 Problem statement

{User pain point, business requirement, or technical debt being addressed.}

### 1.2 Current-state audit

{Audit of the current code / architecture. A table comparing "current" vs "target" works well.}

| Dimension | Current implementation | Target state |
|---|---|---|
| ... | ... | ... |

### 1.3 Design goals

{Numbered list of 3–5 core design goals.}

## 2. Goals

{Numbered list of the concrete outcomes this Plan must deliver. Each item should be verifiable.}

## 3. Non-Goals

{Items that are explicitly out of scope but could otherwise be misread as in-scope.}

## 4. Key decisions

### 4.1 {Decision title}

{Decision content + rationale + comparison with alternatives.}

## 5. Implementation plan

### Phase 1: {Phase name}

**Goal**: {One-sentence description of the effect this Phase produces.}

**Files covered**:
- `path/to/file1.ts`
- `path/to/file2.tsx`

**Tasks**:
- [ ] Task 1 description
- [ ] Task 2 description
- [ ] Task 3 description

**Acceptance Criteria**:
1. {Verifiable completion criterion 1}
2. {Verifiable completion criterion 2}

<!-- Backfill after execution:
**Reviewed**: <date> by reviewer
**Commit**: <commit hash> <commit message subject>
-->

---

### Phase 2: {Phase name}

{Same structure as above.}

## 6. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| ... | ... | ... |
```

## Test Cases template

Once every Phase is complete and review has passed, append the following section to the end of the plan document:

```markdown
## Test Cases

### TC-001: {Case title}

- **Preconditions**: {environment / data / entry state}
- **Steps**:
  1. {Concrete operation — click / input / command}
  2. {Concrete operation}
  3. {Concrete operation}
- **Paths**: `packages/.../foo.ts:L12`, `packages/renderer/src/pages/Bar.tsx`
- **Expected**: {observable UI, log line, DB state, or event}

### TC-002: {Case title}

- **Preconditions**: ...
- **Steps**:
  1. ...
  2. ...
- **Paths**: ...
- **Expected**: ...
```
