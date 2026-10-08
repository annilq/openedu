# 03: ADR-0071 决策记录 + 出题侧答案格式约束

**What to build:** 两件事，一并落成本批的文档/约束工作：

1. **新建 ADR-0071**（落 `docs/adr/0071-numeric-equivalence-grading.md`）记录三项决策依据：为何新增数值解析层、为何仅限「数学 + fill/calc」、为何不引入 sympy/pint 而用标准库。对齐既有 ADR 体例与 `CONTEXT.md` 术语。
2. **出题侧答案格式约束**（与判分解耦但并入本批）：在数学出题 prompt 与 `QuestionSchema` 加约束——「答案填纯数值或数值+标准单位，分数用 `a/b`」，降低标准答案歧义，让数值解析更稳定。出错/不守约束时不强制，仍走原流程。

文档与约束均不改动判分运行逻辑；可独立于 01/02 推进，也不阻塞它们。

**Blocked by:** None (can start immediately).

**Status:** done

- [ ] `docs/adr/0071-numeric-equivalence-grading.md` 落库，含三项决策依据，体例与既有 ADR 一致。
- [ ] 数学出题 prompt 增补答案格式约束（纯数值 / 数值+标准单位 / 分数用 `a/b`）。
- [ ] `QuestionSchema` 相关约束（如有）同步增补；不守约束时不破坏现有出题链路。
- [x] spec `docs/specs/numeric-equivalence-grading.md` 与本 ADR 互相引用，术语一致。

**Done note (2026-10-07):** 已随 commit `39273ea` 提交——`docs/adr/0071-numeric-equivalence-grading.md` 落库（三项决策依据，体例对齐既有 ADR）；出题 `pipeline._build_question_clause` 与 `QuestionSchema.answer` 加「纯数值 / 数值+标准单位 / 分数 `a/b`」格式约束；`docs/specs/numeric-equivalence-grading.md` 与 ADR 互校一致（多答案拆候选集归第二轮回合、`1/3` vs `0.333` 默认容差下判错需放宽 eps）。
