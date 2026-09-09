# 术语表 / Glossary · 娃娃学习 App

> 领域术语与架构词汇统一出处。后端为 **feature-first 模块化单体**（ADR-0027），前端见 `frontend/.impeccable.md`。

## 架构结构（ADR-0027）

| 术语 | 含义 |
|---|---|
| **Feature-First / 模块化单体** | 每个业务能力自包含于 `app/features/<name>/`（router + schemas + repository + service）。非微服务，仍单进程、共享 DB。 |
| **Shared Kernel（共享内核）** | 跨 feature 复用的代码，不拆进任一 feature：`app/db/models`（ORM）、`app/domain`（provider/safety/retriever/quota 等 AI 基础设施）、`app/core`（config/security/errors/db/deps）。 |
| **Feature 包** | `app/features/<name>/`：某业务能力的全部代码。现有 11 个：health / auth / children / questions / model_management / tasks / review / mastery / tutor / ai / assistant。 |
| **Repository 层** | `app/features/<name>/repository.py`：SQLModel 表的 CRUD，替代旧 `app/crud.py`（已删）。 |
| **Schema 层** | `app/features/<name>/schemas.py`：该 feature 的请求/响应 Pydantic 模型（旧 `app/models.py` 的 Pydantic 部分已按 feature 拆分）。 |
| **ORM 表** | `app/db/models/` 下的 `SQLModel(table=True)` 类（User/Task/Question/...）。与 Pydantic schema 分离。 |
| **依赖收敛** | 所有 feature router 从 `app.core.deps` 取 `CurrentUser/CurrentParent/CurrentChild/CallerDep/SessionDep`；无 `app.api.deps`。 |

## 领域模型

| 术语 | 含义 |
|---|---|
| **User** | 账号主体。`role` 区分 `parent` / `child`。**children 是 `role="child"` 的 User 行**，无独立 Child 表。 |
| **Child（娃娃）** | 家长账号下的 `role="child"` User；`parent_id` 指向其家长。 |
| **Task（题卡/任务）** | 家长出题 → 娃娃作答的单位。状态机：draft → ready → assigned → ...（详见技术架构后端 §6）。 |
| **TaskQuestion** | Task 与 Question 的关联行（含题序、是否提升为题库题）。 |
| **Question（题库题）** | 家长题库中的题；`parent_id` 做 owner 隔离（ADR 隐私/版权）。 |
| **Draft / Ready / Assigned** | Task 生命周期状态（出题未定稿 / 已定稿待派发 / 已派发娃娃）。 |
| **TutorLog** | 娃娃伴学答疑交互日志（F-305，家长可见）；`count_tutor_today` 据此计每日上限。 |
| **TutorQuota** | 家长按娃配置的 AI 管控（每日提问/时长上限、学科白名单）。 |
| **TutorUsage** | 当日答疑累计耗时（秒），用于时长上限；次数口径沿用 TutorLog 计数。 |
| **Mastery（掌握度）** | 按知识点聚合的掌握情况（WrongQuestion / 作答记录推导）。 |
| **WrongQuestion（错题）** | 娃娃答错的题，用于复习/诊断。 |
| **Review（复习）** | 基于遗忘曲线的复习调度；`next_interval_days` 由 `app/domain/review_scheduler` 计算。 |
| **Checkin（打卡）** | 学习打卡记录（进度可视化）。 |

## AI / 编排（ADR-0003/0015/0021/0024）

| 术语 | 含义 |
|---|---|
| **LLMProvider** | 业务层统一 LLM 抽象（ABC）；厂商适配只在 adapter 内，业务代码不直连厂商 SDK。 |
| **resolve_engine** | 解析真实引擎：`家长 ModelConfig 表 → 内置 BUILTIN_MODELS → 全局 LLM_PROVIDER`；解析不到走 flow 内 mock 分支（零 key 闭环）。 |
| **Genkit** | AI 编排底座（Python `genkit` + `genkit-fastapi`）；仅在 `app/ai/` 边界 `import genkit`。 |
| **Flow（tutor_ask / tasks_generate）** | `app/ai/flows.py` 中的 Genkit 流式 flow；含 check_input/check_output 安全层。 |
| **SubAgent** | `app/ai/subagents/<business>/` 下的业务智能体（question/tutor/tasks...），统一契约 `handle(intent, ctx)` / `run(message, ctx)`（ADR-0021）。 |
| **AgentRuntime** | 统一发现/加载 SubAgent 并做混合意图路由（规则优先 + LLM 兜底）的运行时（ADR-0024）。 |
| **manifest** | 每个 SubAgent 文件夹下的声明（business 键、roles 可见性、描述），供 AgentRuntime 发现。 |
| **AG-UI 事件信封** | 助手交互统一协议：`USER_MESSAGE`/`THINKING`/`TOOL_CALL`/`TOOL_RESULT`/`DATA`/`ASSISTANT_MESSAGE`/`DONE`/`ERROR`（ADR-0025）。 |
| **Caller** | `app.core.deps.Caller`：双端通用调用者（`role` + `user`）；`CallerDep` 注入。 |

## 安全 / 合规（ADR-008/0012）

| 术语 | 含义 |
|---|---|
| **儿童内容安全双层防护** | 输入校验（check_input）+ 输出校验（check_output）；娃娃端永远拿不到违规/标准答案兜底。 |
| **角色感知派发** | 娃娃端仅可见 `tutor` SubAgent；家长端可见全部（ADR-0026）。 |
| **教材版权硬门槛** | 对外分发/上线前必须解决内容来源（公版优先 + 授权路径），ADR-0012。 |
