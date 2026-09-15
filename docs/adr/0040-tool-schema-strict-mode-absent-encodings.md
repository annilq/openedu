# ADR-0040：工具 schema 必须在 OpenAI strict 模式下自洽——缺席编码与 `NO_FILTER`

工具声明的参数 schema 不再按 JSON-Schema 的「可选」语义（`"required": []`）当作模型所见；**每个可省略参数都必须有一个类型合法的「缺席编码」**，且 handler 必须把它归一为「未提供」。字符串用 `""`，整数用 `0`，枚举**必须**把 `NO_FILTER`（`"all"`）列进 `enum`。

## 背景：我们的 `"required": []` 在 wire 上不存在

`genkit_openai/models/model.py#_get_tools_definition`（第 88–120 行）对**每一个**工具无条件执行：

```python
parameters = _ensure_strict_json_schema(parameters, path=(), root=parameters)   # 第 108 行
function_call = {..., 'function': {..., 'parameters': parameters, 'strict': True}}  # 第 116 行
```

而 `openai/lib/_pydantic.py#_ensure_strict_json_schema` 第 55–57 行是：

```python
properties = json_schema.get("properties")
if is_dict(properties):
    json_schema["required"] = [prop for prop in properties.keys()]   # ← 全部 property 变必填
```

于是 `list_parent_tasks` 实际下发给模型的 schema 是：

```json
{ "type": "object",
  "properties": { "child_id": {...}, "child_name": {...}, "status": {...} },
  "required": ["child_id", "child_name", "status"],
  "additionalProperties": false }
```

我们写在源码里的 `"required": []` 被整体覆盖。**参数越不是必填，模型越要为它编一个值。**

### 真机事故（本 ADR 的触发场景）

家长问「我有哪些任务？」，模型陷入死循环并把工具调用叙述成文本，最终泄漏到用户面前：

1. strict 模式强迫模型填 `status`。`enum` 只有 `["draft","assigned","done"]`，**没有「不过滤」这个合法取值**。
2. 实测（`deepseek-v4-flash`，真接口）模型填的是 `{"child_id": "", "child_name": "", "status": ""}`。
3. handler 严格校验：`status=""` 既非 `None` 也不在枚举内 → 回灌
   `status 只能是 ['draft','assigned','done'] 之一，收到：''`。
4. 模型收到硬错误后反复试探——省略（仍被要求必填）→ 空串（还是错）→ `null`（还是错）——
   最终撞上 SOP「不重复调用同一个工具凑结果」，**空转并把调用写进正文/思维链**。
5. 该文本被当作最终答案回流（另一条已修的路径，见 ADR-0033 补充），用户看到原始协议。

同类陷阱：`list_wrong_questions.limit` / `list_due_reviews.limit`（`integer`，strict 下必填）。
模型只能自行编一个数 → **静默截断结果**（用户有 200 道错题却被告知 20 道），或填 `0` → 撞
「limit 必须大于 0」→ 同一条重试循环。

### 第二例（同日）：文本化的缺席值

同一机制还有第二种形态——模型对「没有目标娃娃」的表达是**字符串** `"null"`：

```json
{"child_id": "null", "child_name": "", "status": "draft"}
```

旧 handler 的 `str(child_id).strip()` 对 `"null"` 为真 → 送去解析 uuid →
`ToolArgumentError: child_id 不是合法的 uuid：'null'` → 模型再试一轮。
（JSON 的 `null` 本就是 Python `None`，走的是另一条归一；出问题的是**文本化**的缺席。）

因此 `UNSET_TOKENS` 覆盖各语言口径的文本化缺席：
`"" / all / any / * / none / null / nil / undefined / unset / n/a / na`。
`_as_uuid` 同时支持 `hint` 参数——回灌给模型的消息要带**可执行出路**
（「按昵称定位请改用 child_name；不指定目标请留空」），否则模型只能换个猜法重试。

## 决策

1. **引入缺席编码**（`app/ai/subagents/query/tools/_shared.py`）：
   - `UNSET_TOKENS = {"", "all", "any", "*", "none", "null", "nil", "undefined", "unset", "n/a", "na"}`（覆盖各语言口径的文本化缺席）；
   - `optional_str(raw)`：`None` / 空白 / 上述 token → `None`（未提供）；
   - `optional_int(raw, name=...)`：`None` / 空串 / `0` → `None`（=不设限），负数报错；
   - `NO_FILTER = "all"`：枚举型可选参数的显式「全部」取值。
2. **归一收口在 `resolve_children`**：它是全部定位工具的公用入口（ADR-0033 决策 8），
   `child_id` / `child_name` 在此归一，杜绝「`all` 被当作 uuid 去解析」这类次级陷阱——
   7 个工具一次性受益，不需要逐工具打补丁。
3. **enum 必须含 `NO_FILTER`**：`list_parent_tasks.status` 的 `enum` 改为
   `["all","draft","assigned","done"]`，描述写明「不过滤时传 all 或空字符串」。
4. **参数描述对模型显式化缺席写法**：定位参数描述改为「不指定时传空字符串」，
   `limit` 描述写「0 或空＝不限」。模型不必靠猜。
5. **回灌消息要带可执行出路**：`_as_uuid` 增加 `hint` 参数，`child_id` 的报错追加
   「按昵称定位请改用 child_name；不指定目标请留空」——模型拿到错误后要靠自纠继续，
   光说「不是 uuid」它只会换个猜法重试。
6. **机制化守卫**（`backend/tests/ai/test_query_tools_contract.py`，跑在 `pytest`）：
   - `test_wire_schema_forces_every_property_required`：复刻 `_ensure_strict_json_schema`，
     断言「必填陷阱」依然存在——**证据锚点**，SDK 行为变了要重新评估而非删补丁；
   - `test_enum_args_expose_an_explicit_no_filter_value`：枚举型参数必须含 `NO_FILTER`；
   - `test_absent_encodings_are_equivalent_to_not_passing`：**行为级**——用缺席编码填满
     全部参数必须与「不传」出参逐字节相同（新增工具忘改会被此条拦下）；
   - `test_textual_absence_in_child_id/child_name_is_treated_as_unspecified`：
     `TEXTUAL_ABSENCE_VALUES` 九个文本化缺席值逐个断言等价于「不指定」，且草稿仍进
     `unassigned_items`（未被误读成「精确指定了娃娃」）；
   - `test_absent_normalization_does_not_weaken_real_validation`：真实非法值
     （`status="archived"`、`limit=-1`、`limit="abc"`、`child_id="abc"`）仍须抛错，
     归一只针对缺席。

## Considered Options

- **① 让 status 变成「非必填」**（最初的直觉）：**无效**。源码里它本来就是 `"required": []`，
  真正决定必填的是 strict 改写。改注释、改 `required` 数组都不产生任何 wire 变化。
- **② 关掉 strict 模式**：genkit 无条件套用，未暴露开关；`openai_config` 由插件内部构造，
  调用方无法覆盖（`request.config` 只接受 genkit 已知的类型化字段）。
- **③ 把过滤参数从 schema 里删掉**（工具不收参数、恒定查全部）：消除陷阱但**丢掉能力**，
  「查已完成任务」「只查数学错题」「最近 5 道」全部失效。
- **④ 预先把 schema 自己 strict 化**（补 `additionalProperties: false`、填好 `required`）：
  函数是幂等的，改写照旧发生，等于没做。
- **⑤ 给可选参数补 `default`**：strict 校验的是「键必须出现」，默认值不改变这一点。
- **⑥ 采纳**：缺席编码 + 单一收口归一 + 机制化守卫。最小改动，同时把「模型被迫编值」这个
  结构性前提显式化到 schema 描述里。

## Consequences

- **新增工具多了一条硬约束**：任何可省略参数都要有缺席编码并在 handler 归一；枚举型参数必须
  含 `NO_FILTER`。忘了会被契约测试拦下，不靠 review 纪律（与 ADR-0033 决策 8/9 同一风格）。
- **`0` 的语义被占用**：`limit=0` 表示「不设限」而非「返回 0 条」；负数报错。这是 strict 模式下
  唯一能表达缺席的整型编码，写进描述以免模型误解。
- **`"all"` 成为保留词**：被归一为缺席，因此不能作为真实的学科名/状态值使用（现状无冲突）。
- **依赖外部行为**：本约定的前提是 genkit_openai 继续用 `_ensure_strict_json_schema` 强制 strict。
  该函数是 openai SDK 的**私有 API**（`openai.lib._pydantic`），升级 genkit / openai 时需要关注；
  证据锚点测试会先失败。
- **不修的部分**：`strict: True` + `additionalProperties: false` 仍然使模型无法传未知字段；
  `tool_choice='none'` 仍是「出现 tool 消息后强制文本收尾」（`model.py:265-267`），未动。

## 明确不做：前端预填「当前浏览的娃娃」

事故提出的对策之一是「把客户端当前切换的 `child_id` 传进来」。**不采纳**：

- **不必要**：故障由 strict 强制填值引起，不是缺上下文；归一即可解决。
- **娃娃端本就恒查自己**：`extra["child_id"]` 由端点从 JWT 写入（`assistant/service.py:85-90`，
  child → `caller.user.id`，parent → `None`），客户端无法伪造；`resolve_children` 在孩子分支
  **直接返回本人、忽略入参**。这已是现状，无需改动。
- **新攻击面**：多一个客户端可控的定位字段，工具层就得再校验一遍归属；而当前
  「定位参数只来自模型 + 归属校验只经 `require_owned_child`」的口径更窄、更安全。
- **真要做请单独立 ADR**：若确实要「家长正在看哪个娃，AI 默认就查哪个娃」，正确形态是
  `AssistantChatReq.focusChildId`（与既有 `focusInterest` 同族）→ 服务端校验归属后写入
  `extra["focus_child_id"]` → 工具层仅在**家长未显式指定**时采用，且允许用户话里的明确指定
  覆盖它。这是带新语义的 API 变更，不该混在缺陷修复里做。

