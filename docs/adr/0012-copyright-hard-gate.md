# 版权硬门槛（retriever 不解决教材授权）

知识库检索能力本身只负责「按学科/年级/知识点检索内容」，不触碰教材版权授权；教材授权是独立于检索能力的硬门槛，与 ADR-0019（版权合规决策）/ ADR-0020（CI 门禁）协同，对外分发前必须另行解决。

- **检索职责边界**：`retriever.py` 仅实现检索能力，明确标注「不解决教材授权」，对外分发前须另行解决版权（`backend/app/domain/retriever.py:3`）。
- **当前数据源自编、零版权风险**：内置 `_BUILTIN_KNOWLEDGE` 为纯自编知识点（加法/减法/拼音等），不涉及任何教材版权原文，故检索层当前无版权负担（`backend/app/domain/retriever.py:41`）。
- **外部源视为不可信输入**：接入联网/向量检索后，外部内容须先经 `check_input` 再注入，检索层不替业务层做授权判定（`backend/app/domain/tutor.py:65`）。
- **切换不破坏业务层**：检索实现经 `build_retriever` 工厂切换（与 `build_provider` 同模式），`TutorService` 仅依赖 `KnowledgeRetriever` 抽象，授权问题不影响检索抽象（`backend/app/domain/retriever.py:124`）。

**Considered Options**：① 在 retriever 内嵌授权校验（职责越界、与合规门禁重复，拒绝）；② retriever 只做检索、授权作为独立硬门槛（采用）。

**Consequences**：检索层保持轻量、可平滑切换数据源；版权授权从检索职责中剥离，由 ADR-0019 的合规检测与 ADR-0020 的 CI 门禁统一把守。当前内置自编库无合规风险，接入外部语料时须先过 `copyright_compliance_check.py` 门禁。
