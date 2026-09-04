# 11 — 教材知识库 RAG 检索

**What to build:** 新增 `domain/retriever.py`（`KnowledgeRetriever`）：前期联网检索教材知识点、后期向量库 RAG；AI 优先命中知识库对齐教材。

**Blocked by:** 08 — IntentRouter + Tutor 领域服务

**Status:** ✅ done

- [x] `KnowledgeRetriever` 接口与工厂就位，前期走联网检索、后期可切向量库（故事 24/25）
- [x] AI 出题/讲解优先使用知识库命中结果，对齐教材
- [x] 检索有单测（mock 检索返回结构化知识点）
- [x] 🔴 教材版权为硬门槛（ADR-012）：对外分发前须解决，本 ticket 仅实现检索能力、不解决授权

> 回填说明（2026-09-04）：后端 `domain/retriever.py`（`KnowledgeRetriever`）+ git 提交 `feat(backend): T11 教材知识库检索能力` 已落地；检索作 Genkit flow 接地工具（`app/ai`）。**版权授权不属本 ticket 范围**，由 ADR-0019（版权合规落地方案）专门承接。原 `Status: ready-for-agent` 为空滞后标记，特此修正。
