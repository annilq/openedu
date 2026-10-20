# 11: 本地 Ollaya 决策服务接入 + 候选模型中文本地评测

> 标签：`done`
> 来源对话：2026-10-20 用户「本地安装了 ollaya，请根据教程来配置 https://ollaya.dev/」
> 关联：ADR-0104（规则路由移除，决策/LLM 分类为主原语）、ADR-0105（不命中落能力引导）、ticket 08（引入决策模型）、ticket 09/10（路由语义）；`docs/adr/` 无新增 ADR——本票是**工程接入 + 实测否决候选**，不含架构决策变更

**What to build:** 把本机 ollaya 决策服务（`ollaya serve`，`127.0.0.1:11435`，TypeSafe 兼容 `POST /v1/systemone`）接成决策模型端口的真实服务端：①拉起服务与权重（`laya:multilingual` 683 MB / `largha` 328 MB）；②用**项目真实的请求形状**（`_build_routing_state` 的 state + `_capability_text` 投影的选项）做中文影子评测；③把 `LayaDecisionModel` 的传输形状从臆想的 laya-serve 改成实测过的 ollaya 契约，并以本地评测结论决定留任哪个权重。

**Blocked by:** 无（08/09/10 已合入 main；本机已装 ollaya 0.15.0）

**Status:** `done`（2026-10-20 实现；GitHub 未登录，待 `gh auth login` 后建 issue 打 `ready-for-agent`）

## Problem Statement

1. **决策模型从未真正上线**：`laya:multilingual` 是被硬编码的 HF 仓库名，传输形状（`{"state", "questions": [{"question", "options"}]}`）从未对真实服务端验证过。实测直连 ollaya 返回 **422 `INVALID_REQUEST`**："`model`: Field required；`questions`: Input should be a valid dictionary"——旧实现是纸面契约。
2. **候选选择此前只有纸上分析**：上一轮按 ollaya.dev 的公开基准推断 `largha` 为首选升级、**没有任何本项目数据**。公开基准是英文业务工单，页面自述「标注一致性低、仅可横向比较」，不能直接外推中文教育场景。
3. **上下文边界未知**：预判 512 上下文装不下 12 轮中文历史（`ROUTING_HISTORY_LIMIT=12`），但从未测。

## Solution

### 1. 本地服务（按 ollaya.dev 教程）

- `ollaya` 0.15.0 已在 `/usr/local/bin`，服务在跑（pid 文件 `~/.ollaya/server.11435.pid`），监听 `127.0.0.1:11435`；模型缓存 `~/.ollaya/models`；与本机 Ollama(11434) 是两个进程。
- 权重：`ollaya pull laya:multilingual`（683 MB）+ `ollaya pull largha`（328 MB，需 Ollaya ≥ 0.15.0）。
- 配置写入 `backend/.env`（gitignore 内，本地生效）：`OLLAYA_URL=http://127.0.0.1:11435`、`OLLAYA_MODEL=laya:multilingual`。
- **代理实测**：本机设了 `HTTP_PROXY=127.0.0.1:62790` 且无 `no_proxy`，但 urllib 在本机对 localhost 自动绕过，直连成功（第一次端到端 `decide` 即返回 `tasks @0.823`）。故**不加** ProxyHandler 旁路代码；若将来 `OLLAYA_URL` 指向非本机地址，需另行验证代理行为。

### 2. 中文影子评测（evidence，`eval/decision_model_eval.py` + `results-2026-10-20.json`）

13 条中文用例（教师/学生、首轮/续接、含 trace `73000ee0` 的失败形状「历史出题 + 当前『数学』」）+ 1 条 12 轮长历史，2 条模糊句不计分：

| 模型 | top-1 准确率 | p50 | 平均置信（confidence） | 长历史(719 字符) |
|---|---|---|---|---|
| `laya:multilingual` | **8/13 = 62%** | 23 ms | 0.617 | 不截断，`tasks` @0.254 |
| `largha` | 5/13 = 38% | 13 ms | 0.270 | **422 STATE_TRUNCATED** |

**结论：`largha` 不采用**（推翻上一轮的分析推荐）。三条实测理由：

1. 准确率反而比现任低 24 个百分点；
2. 平均置信 0.270——在 `threshold=0.5` 门控下近乎恒不决策，等于把路由整体推给 LLM 分类/能力引导；
3. 512 上下文在真实的 12 轮中文历史上直接 `422 STATE_TRUNCATED`（**预判被证实**），而 laya 的 1024 装得下。

**现任 `laya:multilingual` 的失败面**（均为实测，均为后续作业的输入）：

| 用例 | 期望 | 实得 | 置信 |
|---|---|---|---|
| T04 查学情「我班有哪些学生」 | tasks | tutor | 0.397 |
| T05 查错题「我的错题有哪些」 | tasks | capability | 0.148 |
| T07 纯讲解「这道题为什么选 B」 | tutor | tasks | 0.512 |
| T10 续接转讲解（历史出题 →「第一题怎么算的？」） | tutor | tasks | 0.315 |
| **S01 学生「23 + 45 怎么算」** | tutor | **capability** | **0.913** |

最后一列最危险：**高置信的错误**（学生问解题却被自信地判成「能力自述」）。THRESHOLD 抬高到 0.9 之上会把大量正确路由一并挡掉，不是解法——该失分属于 tasks/tutor/capability 三者的描述可分性问题。

### 3. 适配器迁移到实测契约

`agent_core/adapters/laya.py`：

- 传输层 `_OllayaEngine.predict(model, state, questions)` 走 `POST /v1/systemone`，payload = `{model, state, questions:{<id>:{type:"choice", instructions, criteria:{business_key: capability_text}}}}`。
- 响应按 TypeSafe 形状解析：`answers[<id>]` 的 `choice` + `probabilities`。
- **门控概率取 `probabilities` 的 top 值，而非 TypeSafe 的 `confidence`**：`confidence = (K·pmax − 1)/(K − 1)` 归一化后同一个 pmax 在教师端(K=3)与学生端(K=2)是两个数字，固定阈值跨可见集不可比。实测印证：`pmax=0.823 → confidence=0.7345`，正是 `(3×0.823−1)/2`。
- 模型参数从 HF 仓库名改为 **ollaya 标签**，多语言白名单保留（`laya:multilingual` / `largha`；`laya:en`、`laya:typed-decisions`、`von`、`nli`、`gliclass` 一律 ValueError）；新增标签前须跑本票的 eval 脚本。
- 环境变量改名：`LAYA_SERVE_URL` → `OLLAYA_URL`（+ 可选 `OLLAYA_MODEL`）。旧量无处配置，无迁移负担。
- 失败面统一收口：未配置 / 非 2xx（含 `422 STATE_TRUNCATED`）/ 超时 / 非 JSON / 引擎抛错 → `predict` 返回 `None` → `decide` 返回 `None` → 路由回落 LLM 分类，再不中落能力引导（ADR-0105）。超时从 2.0 s 提到 3.0 s（实测冷启动首请求 1.1 s，之后 10–30 ms）。

## User Stories

1. 作为开发者，我希望决策模型在本地真跑起来而不是纸面可用——要有端到端证据。
2. 作为维护者，我希望候选模型的取舍由**本项目中文数据**决定，而不是第三方英文基准。
3. 作为维护者，我希望英文权重误配在**构造期**就被拒（ValueError），而不是在中文上悄悄答错。
4. 作为维护者，我希望阈值门控跨教师端/学生端可比（同一置信水平是同一个数字）。
5. 作为维护者，我希望 state 超长时明确回落（`422` → `None`），而不是拿半截上下文硬答。
6. 作为学生，我希望「23+45 怎么算」不会被自信地判成能力自述（**当前仍未解决，见 Follow-ups**）。

## Implementation Decisions

- **拒绝在公开基准上换权重**：这次实测证明纸面推断会翻车；此后任何候选（含 `decima:*`、`pplx-decider:flash`）必须先跑 eval 脚本。
- **不引入 `ProxyHandler({})` 旁路**：实测本机 localhost 不被代理，加代码属于没有证据的防御。若未来指向远端再议。
- **不用 `confidence` 做阈值**：跨 K 可比性是硬理由，且 ollaya 返回的 `probabilities` 就是作者重标定后的分布。
- **保留 `_resolve_key` 的三种映射**（key / label / index）：criteria 用业务键，正常路径是 key；另两条是服务端实现漂移时的兜底。
- **env 改名不保留兼容**：生产从未配置过 `LAYA_SERVE_URL`，留 shim 只会制造歧义。

## Won't do

- 不追求 62% 之外的立刻提升——先工单化到 Follow-ups；没有证据地换权重只会重现这次的翻车。
- 不引入 4B+ decoder 系：本机无 NVIDIA GPU，Apple silicon 上 GGUF 走 CPU 是秒级，与「每轮同步路由」的量级不匹配。
- 不把评测写进 pytest：真实推断依赖本机服务，测试必须可在无网无权重环境跑（纪律：替身不猜路由）。
- 不改 `ROUTING_HISTORY_LIMIT`：长历史实测不截断，改短会削弱续接语义（如需更长上下文应换模型或做历史压缩，见 Follow-ups）。

## Further Notes

- **验证**：`tests/ai` + `tests/features/assistant` + `tests/api/routes/test_assistant.py` = **467 passed**（`.env` 就位）；全量 `1015 passed / 2 skipped / 1 failed`（`materials test_empty_text_422` 已知环境性红，同 main 基线）；新增 22 项适配器契约测试（原 12 项）。
- **端到端实测**：真实 ollaya 上 `state="user: 帮我出2道四年级数学题"` → `DecisionResult(choice='tasks', prob=0.823, raw={...confidence: 0.7345, probabilities: {tasks: 0.823, capability: 0.0647, tutor: 0.1123}})`。
- **主机信息**：Apple silicon，laya/largha 走 MLX Apple GPU（故 10–30 ms 而非秒级）。

## 验收（由 User Stories 派生）

- [x] 本机 ollaya 服务可用，`ollaya list` 显示两个已拉权重。
- [x] 中文影子评测脚本可复跑（`.scratch/ai-intent-routing/eval/decision_model_eval.py`），结果落 `results-2026-10-20.json`。
- [x] 适配器对真实 ollaya 端到端返回正确业务键（非桩）。
- [x] 请求形状符合 TypeSafe 契约（含 `model`、`questions` 字典、`criteria` 键=业务键）——有测试守护。
- [x] 门控用 `probabilities` top 值，非 `confidence`——有回归测试锁（confidence=0.99 / pmax=0.6 时不达 0.7 阈值）。
- [x] `422 STATE_TRUNCATED` / 未配置 / 引擎抛错 → `None`（有测试）。
- [x] 多语言守护按 ollaya 标签拒绝英文权重。
- [x] 全量测试绿（唯一失败为已知环境性红）。

## Follow-ups（未做，等决策）

1. **tasks ↔ tutor ↔ capability 的描述可分性**（占 5 条失分中的 4 条）：优先改 manifest 的 `name`/`description` 文案（`criteria` 的值）而非换权重，用同一套 eval 脚本量化收益；这是成本最低的一条路。
2. **学生端 S01「23+45 怎么算 → capability @0.913」**：高置信错误的最坏用例。候选解法——a) 学生端单独阈值；b) 决策模型与 LLM 分类器交叉校验（不一致时取 LLM）；c) 给学生端能力清单加负例描述。需先量机。
3. **长历史余量**：719 字符已穿过 laya 1024 的大半；更长会话会 `422` 静默回落。可选：历史摘要压缩、或评 `decima:agent`（8192 ctx，多语言，但 ECE 0.181 且 CPU 约 1.2 s）再权衡。
4. ** Modelfile `CALIBRATION` 重标定**：laya 官方明言 multilingual 不随附重标定温度，原始概率偏过自信；攒够中文标注后可工时此举同时改善门控可靠性。

## 纪律

- **候选模型取舍必须有本项目数据**：任何低于当前62%（`laya:multilingual`）的权重不得进白名单。
- **英文权重零容忍**：Kernel 在构造期拒绝（`_assert_multilingual`），不以「配置多了个选择」为由放行。
- **评测不在 pytest 内**：网络/权重依赖只在 eval 脚本里，测试保持确定性。
- ** state 超长必须显式回落**（`422` → `None`），禁止读半截上下文出答案。
