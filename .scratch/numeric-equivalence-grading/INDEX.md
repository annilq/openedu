# 数值等价判分 (numeric-equivalence-grading) · Tickets 索引

> 目标：数学 fill / calc 题型支持「数值 + 单位」容差等价判分，替代严格字符串相等。
> 纯后端改动（标准库 `re` / `fractions` / `decimal`，**不引入 sympy / pint / numpy**）；前端零改动。
> 决策记录见 `docs/adr/0071-numeric-equivalence-grading.md`。

## Tickets 状态（全 done）

- **01 数值解析原语 parse_numeric / numeric_equal** ✅ done（`backend/app/domain/numeric.py`）——纯函数层：把「数值 + 单位」文本解析为基准单位数值 + 量纲，做量纲兼容下的容差比较（相对 `1e-6` / 绝对 `1e-9` 双判）；含字母/等式/`π`/`√`/纯中文 → `None`。
- **02 接入 Grader.grade 数值等价分支** ✅ done——仅「学科=数学 且 qtype∈{fill,calc}」走数值等价，多答案（`|` / 「或」）拆候选集；解析任一侧 `None` → 回退原 `_normalize` 严格相等（零回归安全绳）；其余路径完全不动。
- **03 ADR-0071 决策记录 + 出题侧答案格式约束** ✅ done——新建 ADR-0071（为何加数值层 / 为何仅限数学 fill/calc / 为何用标准库）；数学出题 prompt 与 `QuestionSchema` 加答案格式约束（纯数值 / 数值+标准单位 / 分数用 `a/b`），不守约束不破坏现有链路。

## 关键约束
- 不变量：非数学学科题、`open` 题、`multi` 题的 `correct` 结果与改造前**完全一致**（`backend/tests/domain/test_grader.py` 保留原严格相等用例作回归）。
- 量纲不兼容 → `numeric_equal` 返回 `False`（判错），不误判为等价。
