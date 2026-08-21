# T11 · 教材知识库 RAG 检索（故事 24/25 / F-301 / AC-305 检索能力）

> 范围来源：ticket `.scratch/wawa-learning/issues/11-knowledge-rag.md`。
> 边界：**仅实现检索能力，不解决教材授权**——🔴 ADR-012 版权为对外分发硬门槛，
> 本期内容源为内置**自编**知识点库（无版权风险），上线前须换用已授权/公版内容。

## 目标
AI 答疑优先基于知识库命中结果作答（对齐教材口径），且检索实现可平滑演进（后期切向量库）。

## 验收（来自 ticket）
- [x] `KnowledgeRetriever` 接口与工厂就位，前期走内置自编库、后期可切向量库（故事 24/25）→ `domain/retriever.py`：`KnowledgeChunk` / `KnowledgeRetriever` ABC / `MockKnowledgeRetriever` / `build_retriever()`（按 `RETRIEVER_PROVIDER`，`vector` 预留）
- [x] AI 出题/讲解优先使用知识库命中结果，对齐教材 → `TutorService.explain` 在输入校验后检索，命中则把「【知识库】」段落拼入 context 传给 provider（未命中上下文原样）
- [x] 检索有单测（mock 检索返回结构化知识点）→ `tests/domain/test_retriever.py`（7 例）+ `tests/domain/test_tutor.py` 检索注入 3 例
- [x] 🔴 版权门槛仅声明不解决 → 内容源为自编知识点；ADR-012 已注明

## 实现要点
- **数据源**：内置自编知识点库（数学/语文/英语 × 2/4 年级，共 8 条），纯自编、无教材版权内容。
- **匹配**：学科精确 + 知识点/查询关键词子串匹配（`kp in text or text in kp`），宽松命中。
- **注入**：检索在输入安全校验**之后**执行，检索内容不参与 `check_input`（校验对象仅为娃娃可输入字段）。
- **配置**：`RETRIEVER_PROVIDER=mock`（默认）；未知值回退 mock + 告警（同 `build_provider` 模式）。
- **路由**：`/tutor/ask` 装配 `TutorService(build_provider(), build_retriever())`。

## 代码审查修复（general-purpose agent）
1. **grade 未参与检索（高）**：`retrieve` 只按 subject 过滤，低年级会命中高年级条目 → 改为 **学科 + 年级双精确**匹配（适龄优先），补 grade 过滤测试。
2. 空检索词全命中：`knowledge_point=""` 且 `query=""` 时 `"" in kp` 恒真 → text 为空直接返回 `[]`。
3. 测试缺口：补「输入被安全拦截时 retriever 不被调用」（顺序安全回归保护）。
4. 低：接入外部检索源（vector/web）后外部内容视为不可信输入——已加注释，须先经 `check_input` 再注入。

## 测试
- `tests/domain/test_retriever.py`：命中返回结构化 chunk / 跨学科不串库 / 未命中空 / 子串匹配 / 工厂默认与未知回退。
- `tests/domain/test_tutor.py` 新增：命中注入 context（含「知识库」标记与内容、检索参数正确）、追加到已有上下文、未命中保持原样。
- 全量 **101 passed + 1 skipped**，ruff 全过。（修复：query 为空时拼接尾随空格导致子串匹配失败，改按非空部分 join。）

## 提交
见 `git log`（feat(backend): T11 教材知识库检索能力 ...）。
