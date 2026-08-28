# 领域模型 / 术语 / 错误码 — 娃娃学习 App

> 业务词汇的权威定义在 `frontend/CONTEXT.md`（设计系统语境）与 `娃娃学习App_术语表.md`。本页摘抄代理最常踩坑的部分。

## 核心实体（ADR-0004）

- **Task（出题派发容器）**：一次出题 + 草稿审阅 + 派发 + 消费的容器。`status: draft → ready → assigned → done`。学科下沉到题（`specs` 存原始生成规格，用于整卷重生成）。
- **Question（题库层）**：独立实体，可跨 Task 复用。草稿期 `TaskQuestion` 默认不预入库，家长点「加入题库」才写 `Question` 并返回 `question_id`。
- **TaskQuestion（派发快照 / 草稿载体）**：派发（`ready→assigned`）时冻结，只读；娃娃做题 / 批改 / 错题归集全读它，不读 `Question`。
- **batch-generate**：`POST /tasks/batch-generate` 接收 `specs` 数组，逐科循环调 `QuestionGenerator`，**只写 TaskQuestion 草稿项，不写 Question**，原 `specs` 存入 `Task.specs`。
- **草稿 / 锁定 / 派发**：草稿可编辑题干+答案+解析（知识点/题型/学科/年级/难度不可改，改走「重生成」）；`draft→ready` 时校验所有 `TaskQuestion.question_id` 非空，否则拒绝锁定。

## 角色

- **parent（家长）**：注册即管理员，出题 / 查进度 / 管控 AI 额度与内容范围 / 查 AI 日志。
- **child（娃娃）**：独立账号，绑 `parent_id`；进度 / 题目 / 作答按娃隔离。

## 错误码（E-Q1~Q4 统一口径）

- 分层：系统级 `10xxx`（10001 Unauthorized / 10002 Forbidden / 10003 NotFound / 10004 Validation / 10005 ServerError）；业务级 `20xxx` Tasks / `30xxx` Auth / `40xxx` Review / `50xxx` WrongQuestions / `60xxx` Tutor / `70xxx` Children。
- 错误体：`{"code":"TASK_20014"|20014, "message":"...", "status":403, "data":null}`；HTTP 状态码保持语义（401/403/404/409/422/500）。
- 前端呈现：`AppToast` / `AppError` 显示为「E-<code>：<message>」，方便定位根因。

## API 契约速查

- 基址 `/api/v1`；Bearer JWT。完整路径表见 `技术架构_后端.md` §7 与 `README.md` 的 API 速览。
- 关键端点：`POST /auth/register|login`、`POST /children`、`POST /tasks/batch-generate`、`GET /tasks/today`、`POST /tasks/{id}/answer`、`POST /tasks/{id}/checkin`、`GET /review/due`、`POST /tutor/ask`、`GET /tutor/logs|quota|usage`、`GET /questions`（题库浏览）、`POST /tasks/from-bank`、`POST /tasks/{id}/questions/from-bank`。

## 掌握度 / 安全 / 管控（口径摘要）

- 掌握度：基础分（历史 40% + 近 10 次 60% 加权）+ 活跃错题封顶 + 6 级等级；毕业解除封顶。
- 使用管控：`/tutor/ask` 前置强制——学科越界 → **403**，次数 / 时长达限 → **429**；null=不限、0=禁用；配置非法 → 422。
