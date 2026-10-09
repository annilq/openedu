# 课件模块一等化（courseware-round-3）· Tickets 索引

> 来源：ADR-0078（课件模块一等化：独立新增入口 + 课件信息编辑 + 手动添加环节 + AI 作辅助）。
> Umbrella spec：`docs/specs/courseware-first-class-module.md`（已发布，triage: ready-for-agent）。
> 本地 `.scratch` 文件（未建 GitHub issue）。每张 ticket 含 `What to build` / `Blocked by` / `Status` / 验收清单。
> 决策由 grill-with-docs 流程先追问后落地（已与用户对齐 4 个岔路 + 2 个核实结论）。

## 背景（一句话）
课件当前是「知识点行进入 → AI 代写」的副作用，不是一等模块。round-3 把它扶正：独立新增入口、课件信息可编辑、手动添加环节、AI 降为显式触发的辅助。

## Tickets 状态（共 7 票，依赖序 blockers first；均为 ready-for-agent）

依赖链（T03 是 wide refactor，按 to-tickets 技能拆 expand–contract）：

```
01 课件中心「新增课件」主入口 + 新建表单（空壳） ── None
02 课件信息编辑（标题/状态） ─────────────────── None
03 环节去 kind · expand（内容块渲染，旧 kind 仍可用） ── None
04 手动添加环节 ─────────────────────────────── 03
05 AI 补充讲解（知识点+用户信息的三项数据回填） ── 01, 03
06 课堂练习在演示页可见（kind-free 练习内容块） ── 03
07 环节去 kind · contract（删 kind 字段与枚举） ── 03, 04, 05, 06
```

- **01 课件中心「新增课件」主入口 + 新建表单** ⬜ todo——`CoursewareCenterScreen` 加主按钮 → `courseware_create_sheet`（选知识点+标题+教学目标）；后端 `create_courseware` 支持 `draft` 不自动起草建空壳。
- **02 课件信息编辑（标题/状态）** ⬜ todo——编辑器顶部「课件信息」卡片 + 编辑弹窗 → 复用 `PATCH /{id}`（无需新端点）。
- **03 去 kind · expand** ⬜ todo——`kind` 可选 + 放宽校验 + diff 匹配键去 kind；引入内容块渲染、旧 kind 仍读；枚举 `@deprecated` 但**不删**。最大改动面，分两票。
- **04 手动添加环节** ⬜ todo——`editor_section_list` 加「添加环节」→ 开空白 `CoursewareSectionEditDialog` → append + `PUT /sections`。Blocked by 03。
- **05 AI 补充讲解：知识点+用户信息的三项数据回填** ⬜ todo——新建改空壳；「AI 补充讲解」按钮复用 `redraft_diff`；后端起草查素材+场景候选让 LLM 引用真实 id。Blocked by 01 + 03。
- **06 课堂练习在演示页可见（kind-free 下的练习内容块）** ⬜ todo——决定练习是第四内容块还是暂不支持；若内容块则 `PresentStage` 显式渲染 `SectionPractice`。Blocked by 03。
- **07 去 kind · contract** ⬜ todo——等 03/04/05/06 全落地后删 `kind` 字段 + `CoursewareSectionKind` 枚举 + 残留引用；旧带 kind 课件读取时忽略该键。Blocked by 03, 04, 05, 06。

## 验证纪律（各票共同）
- `flutter analyze lib/features/courseware` 0 issue；编辑器/中心/演示测试全绿；
- 后端 courseware + 分层守卫通过；不引入 Material；单文件 ≤400 行；
- 去 kind 后补回归：旧带 kind 课件仍能演示、新无 kind 课件能与 AI 补充互写。
