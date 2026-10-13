# Spec：AI 运行轨迹可观测 UI 与管理员（admin）

> 决策依据：[ADR-0088 AI 运行轨迹可观测与管理员](../adr/0088-ai-run-trace-observability-and-admin.md)。
> 上游基础：账户角色枚举化与 admin 落地（本轮回合已 done，见 ticket 00）。
> 术语以 `CONTEXT.md` 为准（运行轨迹 / 会话 / 气泡 / 历史会话 / 管理员 / 破窗访问 / 双消费者 / 归属校验）。
> 本文件是 GitHub issue 的正文源；落库后以 issue 为准。范围：ADR-0088 全文 + 角色枚举化的收口衔接。
> 关键背景：openedu 在「会话存储=业务标准」「内核 agent_core 不持有会话」上已领先于多数用框架自带 memory 的项目；
> 真正的债在**可观测层**——`Message` 的可观测字段是空的、没有 AI 运行维度的 trace/成本/延迟视图。

## Problem Statement

后台已经有 AI 运行的原始数据，但「看得见、读得懂、管得住」这三件事都没完成。从使用者视角拆：

1. **运行轨迹没有客户端入口。** 后端早就有 `/ai/debug/conversations` 端点，返回一次 AI 运行的全部步骤（路由决策、工具调用与参数、工具结果、输出、安全标记）原始载荷。但前端零路由、零 provider、零页面调用它——教师与运维在 App 里看不到任何 AI 运行日志，只能去翻数据库或后端日志。
2. **可观测字段是空的。** `Message` 表虽然声明了 `latency_ms` / `usage`（token）/ `model` / `input_safe` / `output_safe` / `blocked` 等列，但落库路径从未填充它们。即便明天把端点接到前端，token、成本、延迟、模型名这些列也全是 `null`。
3. **运行轨迹和历史会话不能直接合并。** 现有历史会话（`/assistant/conversations`）只投影「气泡」（user/assistant 的 `text`/`cards`），刻意剥离路由/工具/安全步骤，注释明写轨迹「不进气泡」。如果把运行轨迹塞进历史页，会把「孩子看到什么」和「系统做了什么」混在一起——对一款中小学/儿童合规产品是反模式。
4. **没有能跨教师看全局的角色。** 账户角色长期是自由字符串 `"teacher"/"student"/"parent"/"child"`，既没有 `admin`，也没有「跨教师读取」能力（`core.guard` 只有 `require_owned` 单教师归属）。任何「排障时看全部教师/学生的 AI 运行」诉求，都缺一个独立身份。
5. **可观测性维度缺失。** 当前只有 HTTP 访问日志中间件 + 零散 `logging`，没有任何「某次运行走了哪条路由、调了哪些工具、花了多少 token、延迟多久、是否被安全拦截」的视图。

## Solution

分两层，一层已经做完（角色系统），一层待落地（可观测 UI）：

**A. 账户角色枚举化 + 管理员（已落地，本轮）。**

- 账户角色从自由字符串改为有类型的 `Role(student / teacher / admin)`；数据库列保持 `VARCHAR(16)`，历史字符串 `teacher/student` 自动互转、`admin` 是新值，**无需迁移**。
- 新增 `require_admin` 与 `require_owned_or_admin`（admin 越教师边界只读审计）；debug 端点接通 admin：admin 看全部、教师只看自家。
- 启动期环境变量驱动 seed 一个默认管理员（`ADMIN_SEED_USERNAME` + `ADMIN_SEED_PASSWORD` 两者皆配才创建，**绝不写死口令**）。
- **admin = 超级教师**：复用 teacher 调用面，经 `_surface_of(role)` 折算后再传入 `agent_core`，**绝不污染 `agent_core` 的业务无关性**（它的 `role` 仍是 `teacher/student` 两种 surface 字符串，零 `app.*` 依赖）。

**B. AI 运行轨迹可观测 UI（待落地，ADR-0088）。**

- **① 补 `Message` 步级 usage/latency/model/safety 落库**——`Message` 表已有这些列，只差落库时赋值，**零 schema 改动**，且能 `GROUP BY conversation_id` 推出会话级总成本（步级原语可上推，会话级不能下推）。
- **④ 前端独立「运行轨迹」页**——镜像后端「双消费者」结构：历史会话投影「气泡」、运行轨迹投影「全部步骤 + 元数据」，两者互不混入，受众不同。
- **⑤ 内容默认脱敏 + 破窗访问留痕**——admin 看全部时，步级/模型/token/延迟/安全标记可见，但 tool 参数与结果里的学生 PII 模糊化；要看对话原文走「破窗」流程并留访问日志（儿童合规红线，呼应主流产品的「审计 + 脱敏 + 破窗」原则）。
- **⑥ 文档收口**——ADR-0088 已立，待关闭 §7 三个开放问题（admin 是否跨教师看 tutor_logs、破窗留痕落库位置、前端入口形态）。

## User Stories

1. 作为教师，我想在排障时看到一次 AI 运行到底走了哪条路由、调了哪些工具、工具返回了什么，以便定位「为什么答非所问 / 为什么没出题」。
2. 作为教师，我想在我的运行轨迹里看到每次模型调用的 token 用量与延迟，以便评估成本与性能。
3. 作为教师，我想在我的运行轨迹里看到某一步是否被安全策略拦截（input/output 是否 safe、blocked/block_reason），以便确认儿童合规是否生效。
4. 作为教师，我希望运行轨迹和历史会话是两个不同入口，以便我回顾「和孩子说了什么」时不会看到一堆系统内部步骤。
5. 作为运维/管理员，我想跨所有教师查看 AI 运行列表（按 kind 过滤），以便在出问题时全局排查，而不必逐个教师账号登录。
6. 作为管理员，我想看每步的 token/成本/延迟/安全标记，以便做成本归因与异常发现。
7. 作为管理员，我想在需要看某个孩子的对话原文时，走一次破窗访问，且该次访问被记录，以便合规审计「谁在何时看了什么」。
8. 作为管理员，我希望默认看不到学生 PII 原文（tool 参数/结果脱敏），以便降低合规风险，只有破窗才解密。
9. 作为开发者，我希望部署时能通过环境变量创建一个初始管理员，且密码强制从环境变量读取、不写死，以便既可用又不留后门。
10. 作为开发者，我希望账户角色是有类型的枚举而非自由字符串，以便比较角色时不会拼错、`admin` 是显式的一等公民。
11. 作为开发者，我希望 `agent_core` 永远不感知 `Role` 枚举（只认 teacher/student 两种 surface），以便分层不变量（零 `app.*` 依赖）不被破坏。
12. 作为开发者，我希望运行轨迹的新增 UI 复用既有的「双消费者」读取口径，而不是再写一套「步骤转气泡」逻辑，以便避免「喂模型的上下文」和「回放给用户的气泡」分叉。
13. 作为开发者，我希望 usage/latency 落在既有的 `Message` 列上，而不是新建一张 trace 表，以便零迁移、且能复用同一张业务表做用户面与运维面两种投影。
14. 作为开发者，我希望 step 级 usage 落库后，前端轨迹页能按步显示成本与延迟，且会话级总成本可由步级聚合得出，以便不需要额外维护汇总字段。
15. 作为开发者，我希望运行轨迹页的导航状态只有单一来源（扩展既有的导航密封类），以便不会出现两个并行导航状态、且 `flutter analyze` 查不出的崩溃。
16. 作为开发者，我希望新增的运行轨迹页在不套 Material 的树里真构建一次，以便不出现 `analyze` 查不出的「No Material widget found」崩溃。
17. 作为合规审核员，我希望任何跨账户的对话内容访问（含 admin 破窗）都被留痕，以便满足《儿童个人信息网络保护规定》的事后审计要求。
18. 作为测试者，我希望角色枚举与 admin 落地的回归用例覆盖「admin 能看全部 / 教师只看自家 / 学生被拒」，以便归属隔离在引入 admin 后依旧成立。
19. 作为测试者，我希望 usage/latency 落库的用例断言「每步都写了 model/usage/latency」，以便这些列不再悄悄为空。
20. 作为产品决策者，我希望运行轨迹页与历史会话页在信息架构上明确分离，以便后续迭代不会把内部排障信息泄漏到面向学生/家长的视图。

## Implementation Decisions

### 角色枚举与调用面严格分离（已落地，编码此决策的类型形状）

账户角色（`Role`）与 `agent_core` 的调用面（`surface`）是两件不同的事，绝不在 `agent_core` 里出现 `Role`：

```
Role(str, Enum):        # 账户角色，落 User.role（VARCHAR(16)）
    STUDENT = "student"
    TEACHER  = "teacher"
    ADMIN   = "admin"

# agent_core 只认这两种 surface（业务无关，零 app.* 依赖）：
Surface = "teacher" | "student"

# 账户角色 → 调用面 的折算点（在 assistant 编排边界，绝不进 agent_core）：
_surface_of(role: Role) -> Surface:
    return "student" if role is STUDENT else "teacher"   # admin 复用 teacher 面
```

- DB 列保持 `String(16)`（`sa_column=Column(String(16))`），不生成原生枚举迁移；历史字符串与枚举双向 coerce。
- `require_teacher` 放行 `(TEACHER, ADMIN)`；新增 `require_admin`；`require_owned_or_admin` 让 admin 越教师边界只读审计。
- admin 种子仅当 `ADMIN_SEED_USERNAME` 与 `ADMIN_SEED_PASSWORD` **两者皆配**才创建，启动期幂等。

### 运行轨迹读取口径（双消费者，已有，待前端化）

`Conversation` / `Message` 同一张业务表，两个消费者、两种口径：

- **历史会话消费者**（`/assistant/conversations`）：只取 `role in (user, assistant)` 且 `step in (input, output)` 的「可见气泡」，投影成 `role/text/cards`。
- **运行轨迹消费者**（`/ai/debug/conversations`）：取全部步骤（`routing` / `tool_call` / `tool_result` / `generation` / `error` 等），并附 `model / usage / latency_ms / input_safe / output_safe / blocked / block_reason`。
- 两者读同一张表、同一套归属校验（`require_owned` / `require_owned_or_admin`），**不得再派生第三套步骤→气泡逻辑**。

### usage 步级填充（零 schema 改动）

- 在落库路径把每步的 `model`（已有列）、`usage`（token 字典：prompt/completion/total）、`latency_ms`（本步耗时）、`input_safe` / `output_safe` / `blocked` / `block_reason` 写入 `Message`。
- 选步级原语而非会话级汇总：步级能 `GROUP BY conversation_id` 推出会话总成本；会话级汇总（给 `Conversation` 加 `total_usage` 列）反而要改模型 + 迁移，且推不出「哪一步最费 token」。

### 脱敏 + 破窗访问（儿童合规红线）

- 运行轨迹页默认展示：步级结构、路由、模型、token、延迟、安全标记——但 tool 参数与结果中的学生 PII（姓名/学号/作答内容）做脱敏展示。
- 「查看对话原文」走破窗：触发一次显式访问，后台记录访问者、目标 conversation、时间、理由，留痕落库（落库位置见 ADR-0088 §7 开放问题，待定）。
- 默认管理员对全文内容不可见，只有破窗解密——避免「站着就能读所有孩子对话」的合规灾难。

### 前端独立运行轨迹页（镜像双消费者，守导航单源）

- 新增独立入口/页面，只读运行轨迹口径（全步骤 + 元数据），**不**进历史会话页、也**不**进气泡。
- 扩展既有导航密封类增加一个 case，所有入口只经单一 `_go(page)`；不另开并行导航状态。
- 复用既有不套 Material 的控件树；新增页面/浮层真构建一次。
- 文件规模棘轮：按 `test/file_size_guard_test.dart` 基线登记（只许下调）。

### 边界与红线

- `agent_core` 零 `app.*` 依赖（分层不变量 9 与 `test_layering_invariants.py`）——`Role` 绝不进 `agent_core`，折算只在 `app` 层。
- 运行轨迹与历史会话严格分离，不混入气泡视图。
- 全站禁 Material 控件；新增页面在不套 Material 的树里真构建。
- admin 口令绝不写死；默认不解密全文，破窗才留痕。
- DB 列保持 `VARCHAR(16)`，不用原生枚举迁移（避免 SQLite 迁移兼容问题）。

## Testing Decisions

### 接缝（按依赖序）

1. **后端角色边界缝（ticket 00，已 done 回归）**：`require_admin` / `require_owned_or_admin` / `_surface_of` —— 断言 admin 看全部、教师只看自家、学生被拒、admin 折算成 teacher 面后 `agent_core` 不感知 `Role`。
2. **后端 usage 落库缝（ticket 01）**：落库路径断言每步 `Message` 的 `model` / `usage` / `latency_ms` / `safety` 非空（至少 generation 与 tool 步）。
3. **后端 debug 端点 admin 口径缝（ticket 00/03）**：`GET /ai/debug/conversations` 对 admin 返回全部教师、对教师只返回自家；详情走 `require_owned_or_admin`，越权 403。
4. **前端运行轨迹页缝（ticket 02，最高位输出侧）**：喂一个含多步（routing/tool_call/tool_result）的会话，断言轨迹页渲染全步骤 + token/延迟（依赖 ticket 01）、不渲染进历史气泡、入口与历史页分离、导航单源。
5. **破窗留痕缝（ticket 03）**：断言默认脱敏（PII 不可见）、走破窗后原文可见且访问被记录、未授权全文访问被拒。

### 什么样的测试算好

- 只断言**外部行为**：端点响应与随后的 `GET` 结果；widget 可见结果（步骤数、token 列有无、脱敏是否生效、返回落点）。
- 不测实现细节：不断言内部私有方法、不靠 widget key 数内部结构、不单测私有状态。
- 每条用例能被一句产品语言描述（「admin 能看全部教师的运行轨迹」「轨迹页显示每步 token 与延迟」）。

### 覆盖的模块

- 角色：`Role` 枚举、`require_admin` / `require_owned_or_admin`、admin 种子、debug 端点 admin 接线。
- 落库：`Message` 步级 usage/latency/safety 填充。
- 前端：运行轨迹页（独立入口、全步骤渲染、token/延迟、脱敏、导航单源）。
- 破窗：全文访问留痕。

### 既有先例（照抄手法）

- 后端端点测试缝：`backend/tests/api/routes/*` 与 `tests/utils/user.py`（临时 SQLite + 身份助手）。
- 前端导航单源：`teacher_nav_single_source_test.dart`（扩展 case 时同步更新）。
- 全仓禁 Material 祖先：新增控件必须在不套 Material 的树里真构建。
- `test/file_size_guard_test.dart`：单文件 ≤400 行基线。
- `tests/ai/test_layering_invariants.py`：`app` 层不得 import `agent_core` 的业务无关边界（守住 `Role` 不进 `agent_core`）。

### 回归要求

- 后端 `ruff check` + `pytest`（沙盒 `--basetemp` 指向新目录），0 回归（角色枚举已在 791 passed 基线内）。
- 前端 `flutter analyze`（认 `No issues found!`）+ `flutter test`（先关代理），0 回归。
- 归属隔离回归：引入 admin 后，教师仍只能看自家、学生仍被拒；admin 越界只读不写。
- usage 回归：落库后抽样 `Message` 行，`usage`/`latency_ms`/`model` 非空（至少 generation/tool 步）。

## Out of Scope

- 独立的 OTel / Langfuse 后端 trace 体系——首版用 DB 行 + 页面承载，规模化后再叠（见首轮分析：pi-durable 证明「watch/events 流」可作为自建可观测的最小形态）。
- durable execution（Temporal / Restate / Inngest）——当前短轮 SSE、`max_turns=3` 无崩溃恢复需求，过度设计。
- 向家长开放运行轨迹。
- admin 跨教师看 `tutor_logs` 伴学安全审计（ADR-0088 §7 待定，可能单列）。
- `Message` 原生枚举迁移（保持 `VARCHAR(16)`，不用 `native_enum`）。
- 会话级 usage 汇总列（步级可上推，不额外建列）。

## Further Notes

- **为什么不动 `agent_core` 的 role**：`agent_core` 是框架无关内核，零 `app.*` 依赖，`test_layering_invariants.py` 守住。账户角色枚举是 `app` 层概念，跨进去会破坏分层；正确做法是 `app` 层在编排边界折算成 surface 再传——这正是 ticket 00 已落地的 `_surface_of`。
- **为什么 usage 走步级而非会话级**：步级是正确原语，零 schema 改动（列已存在），且能推出会话级总成本；会话级汇总要改 `Conversation` 模型 + 迁移，且丢失「哪一步最费 token」的排障粒度。
- **与班级管理「双消费者」的类比**：历史会话=气泡消费者、运行轨迹=步骤消费者，和「班级管理」容器+下钻复用同一份后端数据、两种前端投影，是同一套「同一数据、两种口径」方法论的再应用。
- **合规红线优先**：儿童/中小学产品，任何跨账户内容访问都默认脱敏 + 破窗留痕，不提供「站着就能读全文」的默认角色——对齐 ChatGPT Enterprise / Claude for Work 的 admin console 审计 + break-glass 模式。
- **文档归属**：决策在 ADR-0088，本 spec 只做可执行展开；两者冲突时改 ADR，不在本文件里偷偷改口径。
