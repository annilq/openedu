# Domain Docs

探索代码前先读领域文档。本仓是**单 context**仓库，没有 `CONTEXT-MAP.md`。

## 先读这些

- **`CONTEXT.md`**（仓库根）—— 唯一术语事实源（glossary）。
- **`docs/adr/`** —— 已落地决策。动手前读与你所涉领域相关的 ADR；新决策先补 ADR 再交叉链接。

缺失时 proceed silently，不主动建议预建。

## 用 glossary 的词汇

输出（issue 标题、重构提案、测试名）涉及领域概念时，用 `CONTEXT.md` 定义的术语，不要漂移到其明确 avoid 的同义词
（如「题目」≠「试题」；「错题」≠「错题库」；「儿童账户」≠「学生」）。术语缺失通常是信号：要么你在发明项目不用的语言，
要么有真实缺口（记到 `/domain-modeling`）。

## ADR 冲突要显式提出

输出与某条 ADR 矛盾时，显式提出而非静默覆盖：

> _Contradicts ADR-XXXX —— 但值得重开，因为…_
