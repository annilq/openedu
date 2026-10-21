# ADR-0108 同规格出题合并为一次请求（array schema）

- 状态：已采纳
- 日期：2026-10-21
- 关联：ADR-0023（唯一安全闸门）、ADR-0032（契约与解析器同源）、ADR-0097（出题降级为流式 tool）、ADR-0098（question 域并入 tasks）、ADR-0107（门控上移，本 ADR 复用的门控纪律）
- 实现：`app/ai/subagents/tasks/generation/parsers.py`（`QuestionListSchema` + `assemble_questions`）、`generation/pipeline.py`（`stream_questions` / `batch_step_label`）、`tools/generate_questions.py`（`_identity` / `_group_items` / 短差留痕）、`tests/utils/fake_provider.py`（替身跟 `output_schema` 走）

## 1. 背景

ADR-0097 之后出题是**逐题串行**的流式 tool：一道题 = 一次 `provider.stream(schema=QuestionSchema)`。
「出 5 道二元一次方程的选择题」就是 5 次完整往返，本地小模型上实测 19–36 秒——提交
`77f69134` 为此把 SSE 超时抬到 10 分钟，等于用**放宽超时**去适配一个本可以不存在的等待。

逐题串行不是没有理由，它换来两样东西：

1. **逐题流式**：题卡一张一张流出，用户边等边看第 1 题；
2. **逐题闸门**：某一道题面不过安全校验，只丢那一道，不连坐（`assemble_question` 返回 `None`）。

本 ADR 的取舍是把它们分开处理：**请求合并，闸门不合并**。

## 2. 决策

**同规格的 N 道题合成一次请求：契约是 `QuestionListSchema`（元素是同一个 `QuestionSchema`），
逐题安全闸门照旧逐元素过。**

```text
请求前：按「不可变身份」分组（subject/grade/knowledge_point/qtype/difficulty/semester/multi/judge）
        一组 = 一次 stream(schema=QuestionListSchema)
到达后：assemble_questions 逐元素过同一道闸门 → 不过的整题丢弃
        实出 < 应出 → 显式留痕（STEP status=error「少出 M 道」）+ 进回灌计数
```

四条落地约束：

1. **元素不携带身份字段**：`QuestionListSchema` 的元素是 `QuestionSchema`，而 subject / grade
   / qtype / difficulty 属于 `QuestionSpec` 的**不可变身份**，由调用方回填而非模型决定。
   让模型改写身份等于把规格决定权交出去——混装任意规格不是「顺便支持」，而是开一个口子。
   多规格请求在调用方按身份分组（`_group_items`），一组一次请求。
2. **N=1 仍走单题路径**：没有批量可言时硬套数组，只是让模型多一个「包一层」的机会。
3. **短差必须留痕**：模型少给了几道，用户侧只会静默少几张卡。故 `cards < count` 时补一条
   `STEP(status="error")` 并记进 `failures`，收尾轮才说得清「应出 N 道、实出 M 道」。
   整批失败时不重复记（`fatal` 标志）——一道题算两笔会让计数失真。
4. **契约与解析器同源**：`QuestionListSchema` 与 `assemble_questions` 同文件，改 schema 不可能
   忘记改解析（ADR-0032 的纪律延伸到批量）。

## 3. 代价（显式接受）

**逐题流式没了。** 约束解码路的 JSON 只在末帧 `StructuredDone` 整块到达，中间只有原生思维链，
因此批量出题时题卡一次性到齐，不再一张张流出。这是换「省下 N−1 次往返」的直接代价，
本 ADR 选择接受：与「让用户盯着空白等 36 秒」相比，「一次到齐」是更小的那个代价。

未采纳的替代：把数组 JSON 改成增量抽取（边到边切题卡）。那需要一套新的解析器协议
（`feed`/`finish` 状态机之外再开一条路），且要模型不守 schema 时也能兜——收益是渐进呈现，
成本是解析器重新长出一个猜测层，与 ADR-0032「解析器零猜测」直接冲突。

## 4. 为什么不这么做

- **把所有题（含多规格）并进一次请求**：元素就得携带身份字段 → 见 §2.1，那是把规格决定权
  交给模型；且多学科请求在组内无法区分，短差归不到科目上。
- **让模型自己决定出几道**：`count` 是调用方给的（结构化规格 / 用户说的数量），模型超产时
  `limit=count` 截断，缺产时留痕。让模型决定等于把「出几道」这个最直白的用户意图改成可协商。
- **短差时静默补位**：拿一道不过闸的题冒充好题，比少一道更糟（`assemble_questions` 只丢不补）。
- **替身继续给单个对象**：替身不跟 `output_schema` 走时，「契约与解析器漂移」被替身完美掩盖
  （表现：要 6 道只出 1 道且无报错）。故 `FakeLLMProvider` 在 `QuestionListSchema` 下按 prompt
  说的「出 N 道」给数组——真模型也是照这句话给的。

## 5. 后果

- 正面：3 道 → 1 次请求（此前 3 次）；多学科请求按规格分组后各一次；短差从隐性变成可断言。
- 代价：题卡不再逐题流出（§3）；`generate_questions` 多了一段分组逻辑。
- 未处理：批量下**推理**也随题卡整块到达（此前逐题推理也是整块，schema 路无变化）。

## 6. 守卫

| 测试 | 守护 |
|---|---|
| `tests/ai/test_tasks_generation_stream.py`（批量 7 项） | 同规格一次请求、`_gen_calls==1`、多规格按组分、进度标签写明题数、短差留痕、空数组报失败、逐题闸门只丢那一道（不连坐） |
| `tests/ai/test_subagents_seam.py` | 同规格共用一次 RAG 检索（检索次数 == 请求次数） |
| `tests/api/routes/test_tasks_generate.py` | 端点级：单行 count=2 出 2 张、2+1+3 出 6 张（总题数不再丢失） |
| `tests/features/tasks/test_service.py` | 结构化路径的上下文透传 |

## 7. 对替身纪律的追加要求

`tests/utils/fake_provider.py` 的 `schema` 路自此必须**跟着 `output_schema` 走**（ADR-0108 §4）。
这不是为了测试好写，而是因为替身与契约漂移时，被掩盖的正是本 ADR 要防的那类事故。
