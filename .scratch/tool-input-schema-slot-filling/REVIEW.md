# Review: ADR-0095 缺槽追问（tickets 00–03）

基准点 `main`（merge-base `a3e64f4`），diff `git diff main...HEAD`，34 文件 +2371/-12。

## Standards

### (a) 文档化标准

**合规（已核对）**
- `conversation.py:30` `slots: dict | None = Field(default=None, sa_type=JSON(none_as_null=True))` → ADR-0061 §N ✓
- `db.py:534` `add_conversation_slots_column` 先 `PRAGMA table_info` 探列再 `ALTER`，Postgres 走 `IF NOT EXISTS`，只加列不加约束 → ADR-0053 / ADR-0061 §R ✓；`except OperationalError`（非裸 `Exception`）✓
- `assistant_clarify_card.dart` 246 行 ≤400，3 个私有 widget、单一公开物 → ADR-0058 ✓；可点区全走 `AppFocusableAction`、零 Material → frontend.md §2 + `.impeccable.md` ✓
- 预检复用已有 `conversation`（归属在 `service.py:408-415` 已判），未新增内联归属判断 → development.md §3.5 ✓

**违规**
1. **ADR-0095 §2.2 步 3「出题复用 `parse_specs_from_text`」未遵守。** `slot_filling.py:20-47,143-169` 复制了 `_QTYPE_KEYWORDS`/`_SUBJECT_ALIASES`/`_CN_NUM` 与 grade/count 正则，与 `question/agent.py:171-236` 的 `_QTYPE_MAP`/`_SUBJECT_ALIASES`/`_CN_NUM` 逐字重复，注释只写「同源」。改自己的 ADR 也得改它。
2. **frontend.md §4「枚举→文案只在 `labels.dart` 写一次」** — `assistant_clarify_card.dart:144-157` 的 `_kEnumLabels`（qtype/difficulty/semester → 中文）写进 widget，同类收口在 `shared/utils/question_labels.dart`。判断项。
3. **frontend.md §2「尺寸一律走令牌、禁止裸数字」** — `:131` `final hi = slot.max ?? 9`、`:189` `height: 36`、`:227/233` `BorderRadius.circular(999)`。判断项。
4. `service.py:75-82` `_load_input_schema` 用 `importlib.import_module(f"app.ai.subagents.{business}.manifest")` 运行期动态反向依赖 ai 层，`tests/ai/test_layering_invariants.py` 的静态扫描扫不到这条边。判断项。

### (b) 基线味道（均判断项）

- **Divergent Change** `slot_filling.py:276-287` `summarize_slots` 把 question 专属字段硬编码进自称通用的纯引擎，而 `fill_slots` 完全 schema 驱动 → 该文案应搬去 question 侧。
- **Repeated Switches** 同一 `name` 判别散在 `_extract_enum_from_text:106-127`、`_extract_int_from_text:151/160`、`_BOOL_KEYWORDS.get(name):180`，`_extract_from_text:175-185` 又对 `type_` 开一次 cascade → 一张 name/type → extractor 表。
- **Duplicated Code** 见 (a)1；另 `_intPayload:140-141` 把后端正则「N年级」写进展示层，与 `slot_filling.py:152` `r"(\d)\s*年级"` 形成跨端隐式契约。
- **Speculative Generality** `_FreeInput:163-180` 收 `slot` 却从不使用（`build` 只用 `widget.onSubmit`）。
- **Primitive Obsession** `_MISSING = object()` + 全裸 `slot: dict`：schema/missing 形状固定却无类型。
- **Middle Man** `_effective_enum:67-75` 仅 enum/enum_ref 分派，可内联。

## Spec

### (a) 缺失 / 部分实现

1. Ticket 02 要「汇总帧展示已填 + 默认填充项清单，提供**「修改」入口**」— 未实现。汇总只是纯文本 `summarize_slots`（`slot_filling.py:284`），前端无任何汇总渲染分支，SPEC US5「我在生成前有机会修正」无落点。
2. SPEC:62「按 business + intent 累积槽位字典」— 实现是扁平 dict（`service.py:577/598`），未按 business 分组。
3. Ticket 01「结构化 `POST /tasks/generate` 路径行为不变（回归）」— 只有 `if not ctx.extra.get("specs")` 短路（`service.py:561`），无测试覆盖该短路（既有测试只被改输入）。

### (b) 未被要求的改动

- 澄清帧落库时额外写入机器清单 `payload={"clarify": _result["missing"]}`（`service.py:593`），形状是 **list**，与契约 `extra.clarify={"missing_slots":[…]}` 的 **map** 不一致（SPEC:65 只要求「普通消息落库」）。
- `slot_filling.py:32-47` 自造 `difficulty`/`semester`/学科别名抽取表，SPEC:48 只定义 enum/int/bool/string + min/max。

### (c) 已实现但疑似错误

- **跨业务覆盖（已复核属实）**：`conversation.slots = _result["merged"]`（`service.py:598`）对**所有**业务执行；而 `fill_slots` 第 1 步只搬 schema 内的键（`slot_filling.py:227-230`）。tutor/query 轮的 merged 不含 `grade/qtype` → 会冲掉 question 已收集的槽，违反 SPEC:20「半成形意图跨轮保存…下一轮只需补说缺失项」。
- **第二轮「只回三年级」不成立（已复核属实）**：`qtype` 同为 required（`question/manifest.py:47`），只补 grade 仍二次澄清，与 US2「只回「三年级」就能继续」冲突；集成测试用 `"三年级出选择题"`（`test_slot_filling_integration.py:129`）绕开，未验 ticket 01 原验收。
- `slot_filling.py:106-109` 别名「道法→政治」不校验是否在 `SUBJECTS` 内，可写入非法枚举值。
- `summarize_slots` 硬编码 question 字段并输出英文码「题型=choice」（`slot_filling.py:284`，测试断言同），与 US5 可读汇总有差距。
- 前端 bool chip 回传「是/否」（`assistant_clarify_card.dart` bool 分支），后端 `_BOOL_KEYWORDS`（`slot_filling.py:38`）无该关键词；string 输入后端不抽（`slot_filling.py:184`）。当前无必填故未暴露，但变成必填即死循环。

### 测试覆盖

三档齐全（单元 `test_slot_filling.py` 含 merge 覆盖 `:61`/enum_ref/多业务；集成含 query/tutor/guide 不澄清、tutor 不发汇总；前端两测试）。缺口：前端未覆盖 string/bool/汇总帧。

### Out of Scope

未建 `draft_intent`、未做历史回放还原卡（ticket 02 明示延后），守住了。

## 建议修序（按风险）

1. 跨业务槽位覆盖 → 槽位按 business 分组存储（Spec a2 + c1 同一根因）。
2. US2 只补一槽即继续 → 明确 required 边界或让澄清一次问全缺槽、测试改用「三年级」单槽。
3. 汇总帧「修改」入口 + 前端汇总渲染（ticket 02 验收缺口）。
4. `payload.clarify` 形状与契约对齐（list → map）。
5. 去重：抽取表与 `question/agent.py` 同源（Standards a1）。
