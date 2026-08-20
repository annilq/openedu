# 11 — 教材知识库 RAG 检索

**What to build:** 新增 `domain/retriever.py`（`KnowledgeRetriever`）：前期联网检索教材知识点、后期向量库 RAG；AI 优先命中知识库对齐教材。

**Blocked by:** 08 — IntentRouter + Tutor 领域服务

**Status:** ready-for-agent

- [ ] `KnowledgeRetriever` 接口与工厂就位，前期走联网检索、后期可切向量库（故事 24/25）
- [ ] AI 出题/讲解优先使用知识库命中结果，对齐教材
- [ ] 检索有单测（mock 检索返回结构化知识点）
- [ ] 🔴 教材版权为硬门槛（ADR-012）：对外分发前须解决，本 ticket 仅实现检索能力、不解决授权
