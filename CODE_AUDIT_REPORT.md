# openedu 业务功能与代码审计报告

审计日期：2026-10-13
范围：后端 `backend/app`（21,547 行 Python）+ 前端 `frontend/lib`（354 个 dart 文件）
方法：对照 `CONTEXT.md` 领域术语与 `docs/adr/`，对 `features/`、`app/ai/`、`shared/`、`core/` 做逐文件功能映射、死代码扫描、已移除概念残留检索、跨特性耦合核查。
配套交付：`feature_relationship_tree.html`（可交互功能关系树）。

---

## 1. 业务功能全景

### 1.1 后端业务特性（16 个，每个按 router/service/schema/repository 分层）

| 特性 | 职责 | 规模 | 健康 |
|---|---|---|---|
| `auth` | 注册 / 登录 / token / 当前用户 | 小 | 干净 |
| `students` | 教师管理学生账号 | 中 | 干净 |
| `classes` | 班级管理 + 导入导出（ADR-0068），年级权威在 `Class.grade` | 中 | 干净 |
| `tasks` | 任务生命周期、题卡快照、作答、打卡、进度（中心枢纽） | 大 | 干净 |
| `review` | 间隔重复复习（阶段 0..4，末位答对毕业） | 中 | 干净 |
| `mastery` | 知识点掌握度面板 | router 23 行 | 干净 |
| `questions` | 题库浏览 / 删除 / 引用反查（owner_id 归属） | 中 | 干净 |
| `materials` | 资料库：上传 / 抽取 / 向量化 / 知识点目录 / 场景图库 | 大 | 干净 |
| `courseware` | 知识点驱动讲解环节（备课 + 讲课） | 中 | 干净 |
| `tutor` | 教师端 AI 伴学日志与治理 | 中 | 耦合告警 |
| `analytics` | 学情统计聚合（scope × 维度） | 中 | 干净 |
| `export` | 服务端 Typst 排版学生卷 PDF | 小 | 干净 |
| `model_management` | 教师自定义 LLM 模型（Fernet 加密） | 小 | 干净 |
| `ai` | AI 运行轨迹回放（ADR-0088，管理员跨教师） | 小 | 干净 |
| `assistant` | 唯一 AI 入口 `POST /assistant/chat`（SSE 编排） | 大 | 干净 |
| `health` | 健康检查 | router 8 行 | 干净 |
| `agent_core`（内核） | runtime / router / subagent / protocol / tools / registry / genkit adapter，零 app 依赖 | 大 | 干净 |

### 1.2 前端业务特性（14 个，每个按 data/domain/presentation 分层）

| 特性 | 职责 | 规模 | 健康 |
|---|---|---|---|
| `home` | 教师工作台 + 学生首页 + 导航壳（sealed TeacherPage），组合根 | 13,324 行 / 62 文件 | 耦合告警 |
| `assistant` | AI 答疑助手（对话 / 卡片 / 运行轨迹） | 5,266 行 | 干净 |
| `courseware` | 课件中心 / 编辑器 / 讲课页 | 4,799 行 | 耦合告警 |
| `students` | 学生管理 / 表单 / 导入 | 1,827 行 | 干净 |
| `model_management` | AI 模型管理 | 1,189 行 | 干净 |
| `practice` | 练习作答 | 989 行 | 干净 |
| `review` | 复习 / 错题本 | 1,052 行 | 干净 |
| `analytics` | 学情图表（fl_chart 适配器） | 572 行 | 干净 |
| `materials` | 资料库（仅 domain 层，被 home 复用） | 631 行 | 干净 |
| `classes` | 班级管理容器 + 下钻 | 682 行 | 干净 |
| `export` | 导出 PDF / 打印预览 | 455 行 | 干净 |
| `tutor` | 伴学日志查看（F-305） | 106 行 | 偏薄 |
| `authentication` | 登录 / 鉴权 | 419 行 | 干净 |
| `profile` | 「我的」页 | 346 行 / 1 文件 | 缺标准分层 |

### 1.3 共享内核（不随业务变）

- `agent_core`：框架无关 AI 内核，除 `adapters/` 外零 app 依赖、零三方依赖（CI AST 扫描强制）。
- `app/core`：`config` / `db` / `security` / `guard` / `crypto` / `deps`。`guard.py` 是归属与可见性的唯一真相源。
- `app/domain`：纯业务逻辑 `grader` / `review_scheduler` / `mastery` / `safety` / `retriever` / `provider` / `subjects`。

---

## 2. 功能关系树与依赖

### 2.1 学习闭环（核心价值链）

```
教师出题(tasks) → 学生答题产生错题(review/WrongQuestion)
  → 间隔重复复习(review) → 毕业(mastery)
  → 掌握度(mastery) → 学情(analytics) → 薄弱点反向出题(tasks)
```

`tasks` 是中枢：`review`、`mastery`、`analytics`、`export` 都从它取数，`classes`、`students` 为它提供分组与身份。

### 2.2 AI 收敛

所有 AI 能力经 `assistant` 的单一 SSE 入口，由 `service.py` 编排 `agent_core` 的 SubAgent（出题 `question` / 伴学 `tutor` / 查询 `query`）。SubAgent 经 `materials`（RAG 检索）、`questions`（题库）、`tasks`（出题/讲题）取数，`model_management` 经 `resolve_engine` 供模型。

### 2.3 资料库中枢

`materials` 同时喂给三个下游：课件场景（`courseware`，ADR-0061/0073）、题库（`questions`，ADR-0082）、助手检索（`assistant` RAG）。它是内容生产的单一入口。

### 2.4 前端组合根

`home` 是前端组合根，装配 8 个特性的页面，并直接穿透到 `assistant` 的 domain 仓储层。详见第 5 节告警。

---

## 3. 死代码

### 3.1 已删除（本报告执行）

| 项目 | 位置 | 说明 |
|---|---|---|
| 死包 | `backend/app/api/routes/` | 旧路由聚合包。源 `.py` 已全部删除，仅剩 `__pycache__`，无任何代码引用，未 git 跟踪。已删除残留字节码。 |
| 死特性 | `backend/app/features/children/` | 家长/儿童双模式时代的旧特性。源 `.py` 已删，仅剩 `__pycache__`，未注册、未引用、未跟踪。已删除。 |

### 3.2 偏薄特性（非死，但需关注）

- 前端 `tutor` 仅 106 行（一个领域模型 + 列表视图），功能真实但接近桩级。
- 前端 `profile` 只有 1 个文件，缺 data/domain/providers 标准子层，仅靠覆盖层进入。

### 3.3 已移除概念的残留引用（运行代码基本干净，仅注释/迁移逻辑）

后端逐串检索结果：

| 概念（应已删） | 命中 | 性质 |
|---|---|---|
| `owner_role` | 0 | 干净 |
| `User.grade` / `user.grade` | 1 | 仅注释（`db.py:848`，说明已移除） |
| `extract_option_group` / `extract_scene_inputs` | 1 | 仅 docstring（`scene_intent.py:19`，说明被取代） |
| `pending_quiz` | 8 | 全为「已移除」注释 + 一次性迁移 `DROP COLUMN`（`db.py:489-496`，合法） |
| `optionGroup` / `SceneOptionItem` | 7 / 0 | 全为旧形拒绝逻辑与注释（`scene_spec.py:27` 拒绝集、`scripts/migrate_scene_specs.py`）；`SceneOptionItem` 彻底删除 |
| `regenerate` / `换一题` / `整卷重生成` | 1 | 仅注释（`tasks/schemas.py:30`） |
| `ai_draft` / `draft_courseware` / `generate_courseware` | 0 | 干净 |

前端逐串检索结果：

| 概念 | 命中 | 性质 |
|---|---|---|
| `user.grade` / `owner_role` / `pending_quiz` / `aiDraft` | 0 | 干净 |
| `optionGroup` / `SceneOptionItem` | 注释残留 | 注意：新建类 `SceneOptionGroup`（`scene_interpreter.dart:121`）是 ADR-0091 的图形画廊容器，不是被删的旧 `OptionGroup`，勿误删 |
| `regenerate` | 注释残留 | 解释「为何没有这些按钮」 |

结论：运行代码对已移除概念清理得相当干净，残留集中在注释、一次性迁移脚本、以及 ADR 迁移的「旧形拒绝」防御代码（后者应保留）。

---

## 4. 业务关系清晰度（架构债务）

### 4.1 严重：`home` ↔ `courseware` 循环依赖

- `home` 引入 `courseware` 的 `knowledge_point_scene_editor.dart`、`courseware_recent_bar.dart`（`home_screen.dart:38-39`）。
- `courseware` 反向引入 `home` 的 `knowledge_point_scene_editor.dart`（`courseware_section_edit_dialog.dart:8`）、`courseware_recent_bar.dart`（`courseware_center_screen.dart:18`）。
- 这是跨特性循环依赖，违反 `shared/ → features/ → main/` 单向依赖（ADR-0037）。

### 4.2 告警：`home` 穿透到 `assistant.domain`

`home_notifier.dart:6-8` 直接 import `assistant` 的 domain 仓储/请求，绕过 `assistant` 暴露的 provider 层。组合根只应依赖 provider，不应直接吃 domain 内部件。

### 4.3 后端跨特性 service→repository 直连

以下调用越过了「共享逻辑经 core.guard 或 domain」的精神（部分为显式允许的 service→service，但 repository 直连应评估收口）：

- `ai/subagents/tutor/scene_intent.py:37` 直连 `assistant.repository`（`last_scene_figure_key`），应改走 `assistant.service` 暴露的接口。
- `review/service.py:28` import `tasks.repository`；`analytics/service.py:31` import `auth.repository`；`assistant/service.py:64` import `tutor.repository`；`students/service.py:156` import `classes.service`。

### 4.4 违反 ADR-0059：学生端导航仍是旧三元组

教师端已收敛到 `sealed TeacherPage` 单态（`teacher_pages.dart:16`），但学生端 + Profile 仍用 `home_screen.dart:58-65,413-434` 的「侧栏索引 `_childNavIndex` + 覆盖层布尔 `_showProfile`」旧式。应统一到密封单态。

---

## 5. 代码组织合理性

优点：

- 分层清晰且被 CI 强制。`features/*/service.py` 不 import router、不 import fastapi（`test_layering_invariants.py` 9 条 AST 不变量）。
- 归属与可见性唯一经 `core.guard`，杜绝各取数点自行判归属。
- `agent_core` 零依赖内核，genkit 唯一落点且延迟导入，可独立测试与发包。
- `none_as_null` 覆盖全部可空 JSON 列，无遗漏。

不足：

- `home` 的超级依赖破坏了单向依赖方向，是前端最重的耦合点。
- `shared/theme` 双令牌并存（ADR-0044 迁移残留）。
- `Resource<T>` 加载态封装半迁移，与新老两套加载写法并存。

---

## 6. 冗余逻辑 / 设计

1. 双视觉令牌（ADR-0044）：旧 Linear 角色名令牌块 `app_theme.dart:522-536` 曾与新 neo-brutalism 语义令牌并存；已移除旧块并将 42 个文件迁移到语义令牌（LCC-05/06），现仅保留语义令牌（`surfaceXxx` / `semanticXxx`）。
2. 双密钥回退：`core/crypto.py:28` `secret = settings.MODEL_APIKEY_SECRET or settings.SECRET_KEY`，两常数回退。
3. `Resource<T>` 半迁移：新统一加载态封装仅 3 处 notifier 使用，`AppLoading` 手写 spinner 被约 30 个文件直接使用。
4. parent/child 文档与注释漂移：产品已重定位 teacher/student，但 `architecture.md` 与多处注释/索引名仍写家长/child（本次已清理代码侧与 architecture.md 侧，见第 8 节）。

---

## 7. 遗留兼容性设计清理计划（未上线，可大胆删）

| 优先级 | 目标 | 位置 | 处置 |
|---|---|---|---|
| P0 | 打破 `home`↔`courseware` 循环依赖 | `home_screen.dart` / `courseware_*.dart` | 将 `knowledge_point_scene_editor`、`courseware_recent_bar` 上提至 `shared`；home 只依赖 provider 层 |
| P0 | 删除死代码 | `app/api/routes/`、`app/features/children/` | 已执行（删残留字节码） |
| P1 | 移除旧令牌块 | `app_theme.dart:522-536` + 42 文件 | 已执行（LCC-05 迁移 42 文件 + LCC-06 删旧块） |
| P1 | 统一双密钥 | `crypto.py:28` | 收敛到单一密钥源 |
| P2 | `Resource<T>` 二选一 | `resource.dart` + 30 处 `AppLoading` | 全站铺开或回退其一 |
| P2 | 学生端 / Profile 导航收敛 | `home_screen.dart:58-65,413-434` | 统一到 `sealed` 单态（ADR-0059） |
| P2 | `scene_intent` 收口 | `scene_intent.py:37` | 改走 `assistant.service` |
| P2 | 后端 parent 注释 / 索引名 | `db.py` 注释、`ix_*_teacher_created` | 已执行（注释与索引改名） |

---

## 8. 本次已执行的清理

1. 删除死包 `backend/app/api/routes/` 与死特性 `backend/app/features/children/`（仅 `__pycache__`，零源、未跟踪）。
2. 后端 `db.py`：将残留「家长」措辞改为「教师」（归属回填注释、`modelconfig` 注释、`origin` 注释），并将两个索引名 `ix_question_parent_created` / `ix_task_parent_created` 改名为 `ix_question_teacher_created` / `ix_task_teacher_created`（列早已是 `teacher_id`）。
3. 前端：将 `knowledge_point_scene_editor.dart` 与 `scene_developer_guide.dart` 中残留「家长」注释/开发者指引文案改为「教师」，前端 `lib` 内「家长」字面量现已归零。
4. `docs/agents/architecture.md`：将家长/儿童双模式、parent_id/child_id、娃娃端、children 路由等陈旧措辞对齐到实际的 `teacher/student` 角色模型与现行路由注册。

以上改动均为注释、文档、schema 索引名与残留字节码，不影响编译与运行逻辑。
