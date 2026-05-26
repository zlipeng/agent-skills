---
name: plan-execution-gate
description: |
  Plan 生成、落地执行与 Phase-by-Phase Review 的完整工作流。
  TRIGGER when: (1) 用户要求生成方案/计划/plan 并保存到 plans/ 目录；(2) 用户要求执行 plans/ 下的多阶段计划；(3) 对话中出现"生成方案并落地"、"写个 plan"、"执行 plan"等意图；(4) 需要对已完成的 Phase 进行 review 或补充 Test Cases。
  DO NOT TRIGGER when: 用户只是讨论方案思路、不需要落地保存、或任务仅涉及单步操作。
---

# Plan Execution Gate

方案生成 → 落地保存 → Phase-by-Phase 执行 → Review → Test Cases 的完整闭环。

## 1. Plan 生成与保存

当用户要求生成方案并落地时：

1. 探索相关代码，理解现状
2. 与用户对齐需求和边界
3. 按 [Plan 模板](references/plan-template.md) 生成完整 Plan 文档
4. 扫描 `plans/` 目录，取最大编号 +1（如最大 `016-xxx.md`，新文件为 `017-xxx.md`）
5. 文件命名：`{编号}-{kebab-case-标题}.md`
6. 使用 Write 工具保存到 `plans/` 目录
7. 向用户确认保存路径

Plan 文档必须包含：背景与现状分析、Goals / Non-Goals、关键决策（含理由）、按 Phase 划分的实施步骤（每个 Phase 包含 checklist `[ ]`）、每个 Phase 的 Acceptance Criteria、依赖关系。

## 2. Branch Gate（开始执行前先建分支）

**开始执行任何 Plan 前（Phase 1 第一个 commit 之前），必须先基于主分支创建专用 feature 分支**。禁止把 Phase commits 直接推到 `dev` / `main`。

### 强制流程

1. **确认当前分支**：执行任何 Phase 改动前先 `git branch --show-current` 与 `git status`。
2. **基于主分支建分支**：
   - 命名约定：先 `git branch -a | head -20` 观察当前仓库的 feature 分支命名习惯（前缀如 `feat/` / `feature/` / `plan-` 等，是否带编号），沿用该习惯；若仓库无明显约定，默认 `feat/plan-<NNN>-<short-kebab>`。
   - 命令：`git checkout <base-branch> && git pull --ff-only && git checkout -b <new-branch>`，其中 `<base-branch>` 以仓库实际主开发分支为准（常见 `main` / `master` / `dev` / `develop`）。
3. **首个 Phase commit 必须落在该分支上**。后续所有 Phase commit、Test Cases 文档补充、commit hash 回填都在该分支。
4. **不要主动 push 或开 PR**：分支推送与 PR 由用户决定时机，除非用户明确指示。
5. **不要切回 dev/main 做 plan 相关改动**。

### 误提交主分支的恢复流程

若 Phase commit 已经误落到主分支（`main` / `master` / `dev` 等）：

1. **不要**在主分支上直接 `git reset --hard`（破坏性且容易丢失现场）。
2. 在当前 HEAD 处建新分支保住所有 commit：`git checkout -b <new-feature-branch>`。
3. 把主分支指针回退到 origin：`git branch -f <base-branch> origin/<base-branch>`（此时已在 feature 分支，安全；不影响工作树）。
4. 验证：`git log --oneline <base-branch> -1` 应等于 `origin/<base-branch>`，`git log --oneline <new-feature-branch> -1` 仍指向最后一个 Phase commit。

### 豁免条件

- Plan 明确声明仅为文档调整（无代码变更）且只有一个 Phase 时，可直接在主分支上提交一个 commit。
- 用户在对话中显式要求"直接提交到主分支"。

## 3. Plan Execution Gate（Phase-by-Phase Review）

执行 `plans/` 下多阶段计划时，**每完成一个 Phase 必须启动 subagent 执行独立 review，review 通过后方可进入下一个 Phase**。

### 强制流程

1. **完成 Phase 内所有任务** — 该 Phase 下的 `[ ]` 复选框全部勾选，项目的类型检查 / lint / 编译等静态门禁命令（如有）全部通过
2. **跑受影响范围的测试套件（如存在）** — 识别 Phase 触及的代码所属测试（单测、集成测试、组件测试均可），用项目自身的测试命令执行；存在 monorepo 过滤、tag 过滤、路径过滤等机制时，**只跑相关子集即可，不强求全量**。这一步抓"代码改完类型也对，但运行时/渲染/单测假设被打破"的回归（典型例子：文案迁移导致测试断言里的硬编码失配、组件新增 Provider 依赖未被测试 wrapper 覆盖）。如果项目没有测试框架或当前 Phase 涉及的范围没有任何已有测试，可直接跳过本步。测试失败 → 修复后再启动 review，禁止跳过。
3. **启动 review subagent** — 使用 `Agent` 工具（`subagent_type: "code-reviewer"`）传入：
   - 当前 Phase 编号与覆盖范围（文件路径清单）
   - 对应计划文档路径（e.g. `plans/xxx-plan.md`）
   - 该 Phase 的完成标准（Acceptance Criteria）
   - 明确要求：**逐条核对 checklist 是否真实落地**，而不是仅看接口存在
   - 明确要求：**核对受影响范围的测试是否仍然通过**，并把执行的测试命令/结果写进 review 输出
4. **处理 review 结论**：
   - 全部通过 → 在计划文档中把该 Phase 所有任务标记为 `[x]`，并追加一行 `**Reviewed**: <日期> by code-reviewer`
   - 有未落实项 → 留在当前 Phase 继续修复，**禁止**进入下一个 Phase
5. **Phase Commit Gate（强制提交）** — review 通过、计划文档勾选已更新后，**必须先创建一个独立的 git commit，再开始下一个 Phase**：
   - 范围：仅包含该 Phase 实际改动的文件（含 plan 文档的勾选更新）；如有遗漏的无关脏文件，先与用户确认而不是混入提交
   - 项目的静态门禁命令（类型检查 / lint / 编译）必须通过；禁止跳过 commit hook（如 `--no-verify`、`--no-gpg-sign` 等）
   - Commit message 必须能定位到 Plan 与 Phase，推荐格式：
     - 标题：`<type>(plan-<编号>): phase <n> - <Phase 名称>`（type 用 `feat` / `refactor` / `fix` 等，单行 ≤ 72 字符）
     - Body：列出本 Phase 完成的 checklist 要点 + `Reviewed by code-reviewer on <日期>`
   - 创建 commit 后再读取 `git status` / `git log -1` 确认成功，然后进入下一个 Phase
   - **禁止**：把多个 Phase 合并到一个 commit；review 未通过就提交；提交后再补改 Phase 内容（如需修补，新建后续 commit 并在 plan 文档说明）
6. **跨 Phase 禁止并行** — 除非两 Phase 在计划中明确标注无依赖，否则严格串行

### Review subagent prompt 模板

```
审查 {plan_path} 的 Phase {n} 实现。

覆盖文件：{file_list}

要求：
- 不要信任任务描述，只看代码实现
- 核对每一项 checklist：被删的是否真删了，被新增的是否真接入了默认路径
- 发现文档/类型/骨架类"完成"但运行路径未接通 → 必须标记未通过
- 逐条核对 Acceptance Criteria 是否真实落地
- 跑受影响范围的测试：先查清项目用的测试运行器与过滤方式（package.json scripts / Makefile / pyproject.toml / Cargo.toml / go test 等），用项目原生命令只跑覆盖文件相关的测试子集，并把结果写进报告；测试失败一律 FAIL。若该范围确无任何已有测试，明示"无受影响测试"即可。

输出格式：
- PASS / FAIL
- 每条 checklist 的验证结果（✅/❌ + 依据）
- 实际执行的测试命令 + 通过/失败摘要（或"无受影响测试"）
- 如有 FAIL，列出具体问题和修复建议
```

### 豁免条件

仅文档调整或单任务的 Plan（只有一个 Phase）不强制走此流程。

## 4. Plan Completion Test Cases

当 Plan 全部 Phase 完成且 review 通过后，**必须在 Plan 文档末尾追加 `## Test Cases` 章节**。

### 强制要求

1. **位置**：追加在 Plan 文档最底部，紧跟最后一个 Phase 的 `**Reviewed**` 标记之后
2. **覆盖范围**：Plan 中声明的每一条 Acceptance Criteria 至少对应一条用例；关键交互/边界场景单独列出
3. **每条用例必须包含**：
   - **用例标题**（简短描述验证点）
   - **前置条件**（环境、数据、入口状态）
   - **操作步骤**（编号 1/2/3...，每步具体到点击/输入/命令）
   - **涉及路径**（相关源文件路径 + 行号，格式 `path/to/file.ts:42`；UI 用例标注页面路由 / 组件路径）
   - **预期结果**（可观测的 UI、日志、DB 状态、事件）
4. **用例模板**见 [Plan 模板 - Test Cases 章节](references/plan-template.md)
5. **禁止**：笼统描述如"验证功能正常"；没有路径引用；没有可执行操作步骤

### 豁免条件

仅文档类 Plan（不产生代码变更）不需要补充测试用例。
