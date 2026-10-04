# ADR-0055：资料库与 RAG 出题——家长资料入库、双路检索与学科收敛

家长上传资料（教材 / 卷子 / 笔记），系统解析并提取元数据，出题时按学科 + 年级自动检索资料内容注入 prompt（RAG）。同时把「知识点」从自由文本升级为受控目录、题型改为按学科白名单、学科收敛到 3 科。本 ADR 是 2026-09-20 至 10-04 三轮 grill 设计的定案记录。

## 背景：三条现状缺陷的确切落点

1. **题型全学科共用**：`qtype` 是字符串约定 `choice|fill|calc|open`（`app/domain/provider.py:42`、`features/tasks/schemas.py:15`），前端下拉全学科同一份且默认 `calc`（`parent_task_form_view.dart`）——英语默认出计算题。
2. **知识点是自由文本**：`Question.knowledge_point: str`，无表、无归一化，而掌握度按原字符串精确分组（`features/mastery/repository.py`）——「两位数加减法」与「两位数加法」是两条互不相通的掌握度记录。
3. **学科 / 年级前后端不一致**：后端 `domain/subjects.py` 只认 3 科、persona 4 科、前端下拉 15 科，出题接口不校验学科；年级任务表单 1–9、娃娃资料 1–6。

RAG 接缝已存在：`app/domain/retriever.py` 的 `KnowledgeRetriever` ABC + `RETRIEVER_PROVIDER`（默认 mock，`vector` 为预留值）+ 出题管线 `rag_context` 注入点（`question/pipeline.py`）。本 ADR 只**填充**这条接缝，不改调用方。

## 决策

### 1. 资料模型：四张表，全部带 `parent_id`

`MaterialFolder`（目录：name / subject / grade / parent_folder_id）、`Material`（文件：folder_id / storage_key / mime / 抽取文本 / **index_state** / embed_model / chunker_ver）、`MaterialChunk`（片段：material_id / seq / content / **embedding** / subject / grade）、`KnowledgePoint`（目录：subject / grade / name / **status** / 唯一约束 `(parent_id, subject, grade, name)`）。

归属沿用 `core.guard`：全部带 `parent_id`，越权 = 403，无新鉴权路径。迁移走启动期幂等 DDL，不引入 alembic（沿 ADR-0053 纪律）。

### 2. 目录继承元数据，不承担授权

目录可设学科 + 年级，其下子目录与资料**继承**，单份资料可覆盖。**不绑 child**（家长多娃共用一份资料库）。目录只负责组织与提供元数据；检索范围永远按家长归属隔离，不按目录。

### 3. 元数据整篇提取；未命中进「待审」

AI 读**整篇**提取学科 / 年级 / 知识点（不做逐 chunk 提取：成本低、不自相矛盾），知识点对齐到目录；目录中没有的**新建待审知识点**（见 §4）。

### 4. 知识点目录：涌现优先 + 骨架兜底

目录来源二合一：家长资料解析涌现的优先，无资料时落回**自编骨架**（每科每年级仅 5–10 个大颗粒知识点，如「分数」「时态」——骨架只为冷启动不空窗，不充当权威课标）。**待审知识点可以用于出题与检索，但不计入掌握度分组**，家长确认转正后才开始参与统计——否则同一概念多种写法会把掌握度打成碎片。

### 5. 向量化手动触发，带状态机与版本戳

上传**不**自动向量化；家长手动点「向量化」（可重新向量化）。`Material.index_state` ∈ `pending / ready / failed / stale`。每个 chunk 记录 `embed_model` 与 `chunker_ver`；换 embedding 模型或改切分策略后存量标记 `stale`，由家长触发重算——向量绑定模型，这是物理约束不是实现选择。

### 6. 不引入向量数据库：BLOB 存储 + 服务内暴力扫

向量存 `MaterialChunk.embedding`（二进制），检索在服务内直接算余弦。理由：单家长规模是几十份资料 × 数百片段，总向量数千条，暴力扫是毫秒级；引入 pgvector 需要更换 compose 镜像、破坏 SQLite 默认零依赖路径。**量级真的上来之前，向量数据库是负资产**；PG 路径已存在，将来迁移有出口。

### 7. 检索：dense + sparse 双路 + RRF；ColBERT 与 rerank 缓行

采用 **BGE-M3**（一个模型同时输出 dense / sparse / ColBERT，MIT，中文强）：dense 抓同义改写（「进位加法」≈「满十进一」），sparse 抓精确词（数学题里「37+48」这类数字 dense 区分度差，sparse 必须保留）。两路用 RRF 融合（只看排名不看分数尺度）。

**ColBERT 不启用**（存储大一个量级，单家长规模换不来收益）；**reranker 二期再说**（收益最大但多一个模型依赖，先让 hybrid 跑起来量基线）。

### 8. embedding 是服务端基础设施——显式豁免 ADR-0039

embedding 走独立服务端配置（`EMBEDDING_PROVIDER / EMBEDDING_MODEL` 等 env），**不进家长 `ModelConfig`**。这不违反 ADR-0039 的立法目的（消灭免鉴权的引擎解析路径）：embedding 不经过 LLM 生成路径、不涉密钥托管；而「向量绑定模型」决定了它不能跟着家长换聊天模型而失效——否则家长换一次默认模型，全部存量向量跨空间作废。**后续实现者不要把它「纠正」回 ModelConfig**。

### 9. 首版格式与版权闸门

首版解析：**PDF（pypdf）+ txt/md + docx（python-docx）**。图片 OCR 二期（依赖重、中文手写识别差，不与首版捆绑）。

资料内容进 prompt 前过 **ADR-0012 `check_input`**；出题 prompt 沿用既有措辞「参考教材口径（仅作对齐参考，不照搬）」。家长删除资料时**片段与向量一并删除**（见 §10，不破坏题目）。

### 10. 题目溯源只存快照，不建外键

生成的题目不存 `source_chunk_ids` 外键，只存**资料快照**（资料名 + 片段摘要）。家长删资料后题目不失去依据，也无删除级联。

### 11. 学科收敛到 3 科，存量冻结

权威学科枚举 = **数学 / 语文 / 英语**（科学也不要，`subject_personas` 同步删科学）。前端下拉收敛到 3 科、后端开始校验。**存量其他学科的题目 / 任务冻结处理**：照常展示与复习，不能再新建。年级统一 1–9（娃娃资料的 1–6 是「孩子当前年级」，另一字段，不受影响）。

### 12. 题型白名单

`SUBJECT_QTYPES: dict[subject] -> list[qtype]`（+ 默认题型）：数学 `[calc, choice, fill, open]` 默认 `calc`；语文 `[choice, fill, open]` 默认 `fill`；英语 `[choice, fill, open]` 默认 `choice`。**`open` 不拆**——数学应用题与语文阅读理解是同一形式，内容由学科 persona 分化。前端下拉只列白名单项，默认取列表首项；后端校验。

### 13. 检索接线：填现有接缝，不改调用方

实现 `VectorKnowledgeRetriever` 填进 `build_retriever()` 的 `vector` 分支；出题时按请求里的学科 + 年级**自动过滤**片段（家长不勾选），出题结果展示「参考了 N 份资料」；有 `pending / failed / stale` 资料时提示「有 N 份资料未参与本次出题」（不阻断）。

### 14. 评测先行：检索层 Recall@5，再上生成层

先建 30–50 条黄金集（真实资料 + 人工标注「应召回哪些片段」），做成**纯 pytest 检索评测**（不联网、可进 CI），指标 `Recall@5`。检索指标稳定后才引入 RAGAS 类 LLM-as-judge 测生成层。**禁止**用「题目好不好」评测分片——LLM 方差会盖过分片差异。

## Consequences

- **依赖新增**：`pypdf`、`python-docx`（解析）；embedding 走外部服务（Ollama `/api/embed` 或 openai_compat），**不把 torch / sentence-transformers 塞进 FastAPI 镜像**。
- **前端新增**：资料库页（目录树 + 文件列表 + 状态徽标 + 向量化按钮）；任务表单知识点从自由输入改为选择器（学科×年级联动目录）；题型下拉按白名单。
- **破坏性变更**：学科枚举收敛 + 后端开始校验学科与题型——前端必须同版发布（无外部消费者）。
- **不在本 ADR 内**（后续议题）：英语题目语言分层（题干选项英文 / 解析中文 + 年级分层，提示词类，单开）；图片 OCR；reranker；pgvector 迁移。
- **命名红线**：资料不叫 Resource（前端 `Resource<T>` 是加载态包装）也不叫素材（题库已是「出题素材池」）；术语以 `CONTEXT.md` §资料库与检索为准。
