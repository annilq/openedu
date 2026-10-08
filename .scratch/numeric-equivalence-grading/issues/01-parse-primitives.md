# 01: 数值解析原语 parse_numeric / numeric_equal

**What to build:** 判分所需的纯函数层——把学生/标准答案中的「数值 + 单位」文本解析为可比较的数值，并做量纲兼容下的容差比较。这是后续接入 `Grader` 的前置积木，自身可独立用单测验证。

- 用标准库 `re` / `fractions` / `decimal`，**不引入 sympy / pint / numpy**。
- `parse_numeric(text)`：支持整数、小数、真/假分数 `a/b`、带分数 `a又b/c`、负号；抽取「数值 + 可能单位」。
  - 内置轻量单位表，覆盖长度（米/分米/厘米/毫米）、重量（千克/克）、时间（时/分/秒）、角度（度）、货币（元/角/分），转基准单位。
  - 含字母变量、等式、`π`/`√` 等符号、纯中文 → 返回 `None`（标记非数值）。
- `numeric_equal(ans, sub, eps)`：双侧均解析成功且**量纲兼容**时，按容差判等（相对 `1e-6` 与绝对 `1e-9` 双判）；量纲不兼容 → `False`。

**Blocked by:** None (can start immediately).

**Status:** done

- [x] `parse_numeric("12厘米")` 返回基准单位下的数值与量纲，可被 `numeric_equal` 与 `12` 判等。
- [ ] `parse_numeric("1/2")` / `("2/4")` / `("0.5")` 解析为同一数值（Fraction 约分）。
- [ ] `parse_numeric("3又1/2")` 与 `("3.5")` 等价。
- [ ] `parse_numeric("1/3")` 与 `("0.333")` 在容差内等价。
- [ ] `parse_numeric("5个")` 与 `("5")` 数值等价（无单位数值一致）。
- [ ] `parse_numeric("x=5")` / `("π")` / `("√2")` 返回 `None`（非数值，触发回退）。
- [ ] `numeric_equal` 对量纲不兼容（如 `5cm` vs `5kg`）返回 `False`。
- [x] 单测覆盖上述等价 / 判错 / 非数值回退三类，运行全绿。

**Done note (2026-10-07):** 已随 commit `39273ea` 提交——`backend/app/domain/numeric.py`（`parse_numeric`/`numeric_equal`）+ `backend/tests/domain/test_numeric.py`（17 passed，覆盖单位换算 / 分数约分 / 带分数 / 量纲不兼容 / 非数值回退）。纯函数层已就绪，零回归。
