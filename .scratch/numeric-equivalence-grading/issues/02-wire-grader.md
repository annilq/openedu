# 02: 接入 Grader.grade（数学 fill/calc 数值等价 + 零回归）

**What to build:** 在 `Grader.grade` 的客观题分支内，对「**学科 = 数学** 且 **qtype ∈ {fill, calc}**」的题，先尝试数值等价判定；任一端解析失败则回退现有严格相等。其余路径完全不动（应用题 `open` 仍走 LLM、多选题 `multi` 仍走集合比对、非数学仍走严格相等）。前端零改动——只改变返回的 `correct` 布尔的算出方式。

- 多答案：标准答案含 `|` 或「或」→ 拆候选集，学生作答与任一候选数值等价即判对。
- 回退纪律：解析任一侧返回 `None` → 整题走原 `_normalize` 严格相等（零回归安全绳）。

**Blocked by:** 01 (parse_numeric / numeric_equal 原语必须先就绪)

**Status:** done

- [ ] 数学 fill/calc：`12` 与 `12厘米`、`0.5` 与 `1/2`/`2/4`、`3又1/2` 与 `3.5`、`1/3` 与 `0.333`、`5` 与 `5个` 均判对。
- [ ] 数学 fill/calc：`5cm` vs `5kg`、数值不同者判错。
- [ ] 数学 fill/calc：含字母/等式（如 `x=5`）或格式乱的答案 → 回退严格相等（行为与改造前一致）。
- [ ] 多答案标准答案（如 `12或15`）任一命中即判对。
- [ ] **不变量断言**：非数学学科题、`open` 题、`multi` 题的 `correct` 结果与改造前完全一致（扩展 `backend/tests/domain/test_grader.py`，保留原严格相等用例作回归）。
- [x] 改造后 `pytest` 全量（沙盒 `--basetemp=/tmp/<新目录>`）通过，无回归。

**Done note (2026-10-07):** 已随 commit `b52ef3f` 提交——`backend/app/domain/grader.py` 客观题分支抽 `_grade_objective`，数学 fill/calc 走 `numeric_equal`，解析失败回退严格相等；`tests/domain/test_grader.py` 扩 8 例 + 不变量断言（choice·multi 判定结果与改造前一致）。全量 pytest 732 passed / 2 skipped / 0 failed，零回归。
