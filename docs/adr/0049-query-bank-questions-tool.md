# 新增「查询题库题目」工具（list_bank_questions）

AI 学习助手已实现查任务、查错题本、查待复习题三类只读查询（query SubAgent）。
本 ADR 把**第四类查询「查题库里的题目」**补进去，实现方式直接参考既有的
`list_parent_tasks`：同一套工具骨架、`ToolSpec` 形态、统一出参信封、卡片协议。

## 背景

`Question` 表是家长私有的出题素材池（`parent_id` 做 owner 隔离，**没有** `child_id`
外键，不与任何儿童账户关联）。在此之前的查询工具都围绕「娃娃」组织（按娃娃分组、
`project_for_role` 剥答案），但题库天然**没有娃娃维度**——它只是家长的素材库。

用户诉求很直接：「我题库里有哪些一元二次方程的题」「三年级语文题库有几道」。
这类问题在 query SubAgent 路由上属于「查询」意图（与查任务 / 错题同档），
但缺少对应工具，模型只能退回纯文本或误用 `list_wrong_questions`。

## 决策

### 1. 仅家长可用，不接 child 维度

题库是家长私有池，与娃娃无关。工具在 `handler` 入口判定 `caller_role(ctx) == "child"`
即抛 `ToolArgumentError("题库查询仅家长可用…")`，绝不接 `child_id` / `child_name`
定位参数，也不按娃娃分组。

- 配合 ADR-008 最小暴露：娃娃端不暴露家长私有池；
- 娃娃要查题继续走已有的错题本 / 待复习 / 任务（那三种才是与娃娃绑定的数据）；
- 因为没有 child 维度，越权门禁（传别家娃娃 id）在此不构成命题——`child_id`
  不是本工具的入参，传了也被忽略。

### 2. 复用统一信封，单块承载

`Question` 非按娃娃分组的资源，故不用 `child_block`，而是合成一个块
`{id:"bank", name:"题库", grade:None, items:[...], meta:{parent_id}}` 喂进既有
`envelope()`。契约测试断言每个块含 `id/name/grade/items/meta`，合成块满足。

卡片种类登记为 `question_bank_list`（后端 `render.py#_KIND` 与前端
`AssistantCardKind.questionBankList` 逐字对齐）。空结果落到专属空文案
`"题库还没有题目。"`（区分「查过但没题」与「没查」）。

### 3. 过滤参数全量镜像仓库能力

仓库 `list_bank_questions` 已支持 `subject / grade / knowledge_point / qtype /
keyword + 分页`。工具对外暴露全部六个**可选**参数：`subject / grade /
knowledge_point / qtype / keyword / limit`，对话场景用 `limit` 取前 N 条
（仓库分页在此收口为「截断」，上限 200），按 `created_at` 倒序。

缺席归一严格遵循 ADR-0040：strict 模式下模型被迫为每个参数编值，故每个参数都有
类型合法的缺席编码——字符串 `""`/`all`/`none`…→ `None`、整数 `0` 或负 → 报错，
`limit=0` 视作「不设限」。枚举型参数本工具没有，故无需 `NO_FILTER`。

### 4. 经 service 取数，满足分层不变量

query 工具不得直连 `repository` / `router`（分层不变量 7）。新增
`app.features/questions/service.py#list_bank_questions` 作薄封装：调 repository、
把 ORM 行投影为 dump 友好的字典（UUID / datetime → str）、合并每题被任务引用的
复用度 `usage_count`（来自 `TaskQuestion` 反查），并裁剪对话场景不需要的写路径。
handler 在 SSE 请求内**同步直调** service（不经 ASGI，不变量 6）。

### 5. 复用次数（usage_count）进卡片

卡片明细行展示 `复用 N 次`（`_Tone.success`），直观回答「这道题我用过几次」——
它是家长整理题库时唯一关心的复用信号，且数据已在 service 层聚合好，零额外成本。

## 后果

- query SubAgent 工具集由 7 → 8 个；清单 docstring、契约测试 `EXPECTED_TOOL_NAMES`、
  `test_query_subagent.py` 的「全部 N 个工具」断言同步更新。
- 契约测试对「娃娃端不可见答案」与「越权不可达」两道护栏做了**显式豁免**
  （`PARENT_ONLY_TOOLS = {"list_bank_questions"}`）：因为本工具 child 调用在入口即
  被拒，不存在「娃娃视角泄漏」的入口；越权门禁无 child 维度可言。豁免均带注释，
  不是悄悄删断言。
- 前端新增 `question_bank_list` 种类与明细行（`assistant_card.dart` 常量 +
  `assistant_cards.dart#_rowOf` 分支 + `LucideIcons.library` 图标），未登记种类的
  降级卡路径仍兜得住（不丢内容）。
- manifest 增加「题库 / 题库里 / 查题库 / 题库里数学 …」等 triggers 与 `题库` hint，
  确保「查我题库」类问句路由到 query 而非误走 question（出题）。

## 风险与未决

- 题库可能很大，对话场景用 `limit` 截断（默认上限 200）。家长若要「全量导出」属另一
  条需求，不在本工具范围（不引入分页游标，保持对话工具简单）。
- 题目 `answer` / `explanation` 在家长视角原样返回（本就属家长私有数据）；
  因工具不接 child，ADR-008 的剥答案逻辑对此天然不触发，但 `ANSWER_FIELDS` 守卫仍覆盖
  全工具集、对照组保留，符合机制化兜底设计。
