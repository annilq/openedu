# ADR-0101 正则触发词：表达「出 N 道题」这一族，而非逐个旁举

- 状态：已采纳
- 日期：2026-10-20
- 关联：ADR-0098（二执行体收敛，出题 schema 在 `intent_schemas.generate`）、ADR-0100（缺槽追问只做文本引导）

## 1. 背景

教师端实机报障：说「请为「图形的运动（轴对称）」出一道选择题」，助手**没有出题卡**，
而是当作文本问答答了一道题。DB 实证（`app.db`，`conversation b36ee61b…`）：

```
0 user   请为「图形的运动（轴对称）」出一道选择题
1 system routing  伴学答疑        ← 路由到了 tutor
2 tool   tool_call  伴学答疑
3 tool   tool_result tutor_explain
4 assistant 下面是一道关于「轴对称」的选择题…   ← 纯文本，无 DATA 题卡
```

根因在规则路由的**匹配方式**，不在词表少了一两个词：

`agent_core/router.py::_rule_match` 是**子串包含**（`if _norm(trig) in low`）。
`tasks` 的 triggers 里有 `出几道` / `出道` / `出题` / `出题目` / `来几道`，于是：

- 「出一道选择题」→ `出道` 不是 `出一道选择题` 的子串（差一个「一」），`出题` 也不在；
- 「出2道数学题」→ `出几道` 的数字是字面的「几」，`2` 不匹配；
- 「出一题」「出个题」「出五道数学题」→ 同理全落空。

实测（修复前，`classify` 逐句）**整族全部 `fallback` 给 tutor**：

```
'出2道数学题'        -> tutor fallback
'出一道选择题'        -> tutor fallback
'来一道题'           -> tutor fallback
'出一题'             -> tutor fallback
'出个题'             -> tutor fallback
'出五道数学题'        -> tutor fallback
'请出3道三年级数学选择题' -> tutor fallback
```

只有**恰好含字面词**的说法能过（「出几道…」「出一道判断题」靠「判断题」救回）。这不是
漏一个词：用户写「出 2 道」远比写「出几道」自然，量词与数词的组合是**一族**。

## 2. 决策

**manifest 新增 `trigger_patterns`：正则触发的词族；命中后回传一个规范的**字面**触发词。**

```python
# tasks/manifest.py
"trigger_patterns": [
    {"pattern": r"(?:再?给我?|帮我)?(?:再)?(?:出|来|生成|布置)"
                r"[0-9一二三四五六七八九十两几]+\s*(?:道|题|个题|道题)",
     "trigger": "出道"},
    {"pattern": r"(?:再)?(?:出|来)(?:一|个|些)\s*题", "trigger": "出题"},
],
```

- **注册表**（`agent_core/registry.py`）编译并挂到 `SubAgentManifest.trigger_patterns`；
  非法正则 / 缺字段 → 打印告警并跳过该条（静默跳过会让「新加的正则没生效」查不出来）。
- **路由**（`router.py::_rule_match`）两级：先字面触发词，再正则；**两级都按 business
  优先级排序**，所以正则既不会抢在自家高优字面词前面，也不会跨业务抢先。
- **回传的必须是字面触发词，不是正则串**。下游子意图分组
  （`intent_schemas[*].triggers`）按词**等值**判定；回正则串会让「路由得到、却选不到
  出题 schema」——必填槽预检静默失效，而只断言 `business` 的既有测试照样全绿。

## 3. 后果

修复后同一批句子（含用户原句）全部 `tasks / rule / trigger=出道`，且落在
`intent_schemas.generate` 组 → 缺 subject/grade/qtype 时正常进入澄清。

- 收益：整族表达一次覆盖，不必为每个数词 × 量词补词。
- 代价：**引入正则到路由层**。代价是可控的——正则只在字面词全落空后才跑，且词条来自
  manifest 声明（不是散在代码里）；两条守卫测试专盯「别抢走查询 / 写意图」。
- 代价：词表纪律多一条。写宽（如只认「出」）会把「我有哪些题目」「今天有什么作业」
  「帮我创建一个任务」拽进出题并触发科目/年级澄清，**比原来更糟**。故
  `test_trigger_patterns_do_not_steal_query_or_write_intents` 钉住这四句的命中词不变。

## 4. 备选（否决）

- **把数词 × 量词全枚举进 `triggers`**：`出一/出2/出三/…/来一/给我出…` × `道/题/个题`
  是笛卡尔积，且下次出现「出十二道」又要补。词表会变成一台状态机。
- **路由层统一改成正则匹配**：破坏「词表即优先级」的既有语义（ADR-0098 的词序即子意图），
  且每条 manifest 都要把词翻译成正则，风险远大于收益。
- **加一个 LLM 意图分类兜底**：非确定性，儿童产品明确否决（ADR-0033 立场）；且本例是
  确定性缺口，用确定性手段修即可。
- **只在 service 层做「不含出题词但含数字+道」的二次猜测**：等于把路由规则复制到第二处，
  两份口径迟早漂移。

## 5. 守卫

| 测试 | 锁什么 |
|---|---|
| `test_trigger_patterns_canonical_trigger_is_routable_and_grouped` | 回传词必须是字面触发词，且在 `intent_schemas.generate.triggers` 里 |
| `test_take_n_question_family_routes_to_tasks_generate` | 「出 N 道」九种写法（含用户原句）全部 `tasks/rule` 并落 generate 组 |
| `test_trigger_patterns_do_not_steal_query_or_write_intents` | 正则不得抢走题库管理 / 学情查询 / 写意图的命中词 |
