# 架构决策记录（ADR）· 娃娃学习应用

> 记录关键架构决策：背景、决策、备选、后果。状态统一为「已采纳」。

---

## ADR-001 前端技术选型：Flutter 原生 App
- **背景**：目标用户为低龄娃娃，主力设备是平板；需跨 iOS/Android。
- **决策**：采用 Flutter 开发原生 App，平板优先。
- **备选**：PWA 网页（跨设备、免上架）、微信小程序（国内管控友好但 AI 受限）。
- **后果**：一套代码出双端；UI 表现力足；需自行上架/分发；AI 调用必须经后端（前端不藏 key）。

## ADR-002 后端语言：Python
- **背景**：AI 编排需成熟生态；LangChain 主力为 Python。
- **决策**：后端用 Python。
- **备选**：TypeScript/Node（与 Eve/Pi 同生态）、Python+TS 混合。
- **后果**：与 LangChain 深度契合；Pi/Eve（TS）不作为运行时，留作开发助手。

## ADR-003 AI 编排框架：LangChain + 自封领域接口
- **背景**：希望"适配大部分大模型厂商的 provider"，且未来可换框架。
- **决策**：运行时用 LangChain 做 agent 编排；**不在 LangChain 的 LLM provider 抽象之上重复封装**，改为在"agent 框架层"之上自封一层**领域服务接口**（QuestionGenerator / Grader / KnowledgeRetriever / IntentRouter）+ 框架 adapter。
- **备选**：直接用 Eve（TS，Vercel AI SDK）、Pi（TS coding agent）、自写 BaseProvider。
- **后果**：厂商适配交给框架（已支持 100+ 厂商），框架切换由 adapter 隔离；业务代码不绑定具体框架。避免重复造 provider 轮子，同时实现可插拔。

## ADR-004 LLM 模型：暂不定，provider 抽象可插拔
- **背景**：国内平板直连、儿童内容合规、长期成本均需评估。
- **决策**：模型先不绑定；通过 LangChain provider 抽象接入，国产模型走 OpenAI 兼容端点即可。
- **备选**：固定腾讯混元 / 智谱 GLM（国内稳定便宜合规）。
- **后果**：一期可用免费/低成本模型验证；后期按质量与成本选型，无迁移成本。

## ADR-005 数据库：PostgreSQL
- **背景**：多账号、任务、题目、作答记录需持久化与查询。
- **决策**：PostgreSQL。
- **备选**：SQLite（起步更轻）、BaaS（Supabase 等）。
- **后果**：关系模型清晰、易扩展；本地 Docker 起步，架构预留云；SQLite 可作一期最简替代。

## ADR-006 部署：本地 Docker 起步，架构按云设计
- **背景**：家庭自用，不想立即承担云成本与运维。
- **决策**：本地 Docker 容器跑 Python 后端 + PostgreSQL；架构（无状态服务 + 外部数据库）按云部署设计，未来可搬轻量云。
- **备选**：直接上云、纯本地无容器。
- **后果**：零月费起步；外网访问需后续内网穿透或上云；容器化保证可搬运。

## ADR-007 账号模型：家长管理员 + 娃娃独立账号
- **背景**：需家长布置任务、查看进度，且两个娃娃进度隔离。
- **决策**：家长管理员账号 + 每个娃娃独立账号（二年级、四年级各一）；进度与数据按娃娃隔离。
- **备选**：无账号单机、仅娃娃端。
- **后果**：支持"班主任"式管控与跨设备；需实现多角色鉴权。

## ADR-008 内容安全：双层防护 + 家长可见
- **背景**：三期娃娃可自由向 AI 提问，须防不当内容与越狱。
- **决策**：①系统层 prompt 约束（仅适合 X 岁、纯学习）；②输出后校验（敏感词/越狱检测，异常拦截转家长）；③家长可查全部 AI 交互日志；④家长设每日时长上限与内容范围。
- **备选**：仅 prompt 约束、家长全审核。
- **后果**：一期风险低但框架先搭；三期直接启用；保护娃娃且家长可控。

## ADR-009 内容来源：AI 生成 + 对齐教材（前期检索 / 后期 RAG）
- **背景**：需持续产出对齐学校进度的练习。
- **决策**：一期 AI 出题；前期 agent 联网检索教材知识点，后期建教材知识库（向量库）+ 意图识别路由（RAG）。
- **备选**：纯现成题库人工录入、纯 AI 无教材对齐。
- **后果**：贴合课标且灵活；依赖检索/知识库质量；需内容校验流程。

## ADR-010 激励：轻量激励
- **背景**：低龄学习需维持日常使用习惯。
- **决策**：每日打卡 streak、学科积分、知识徽章、家长表扬。纯前端状态，不依赖 AI。
- **备选**：强游戏化（闯关/排行榜）、无激励。
- **后果**：足够形成习惯且不喧宾夺主；排行榜等留待初中阶段。

## ADR-011 Pi / Eve 不作为运行时引擎
- **背景**：用户曾提及 Pi、Eve 等 agent 框架。
- **决策**：Pi（终端 coding agent）与 Eve（TS agent 框架）与 Python 后端割裂，不作为应用运行时；Pi 可作开发期编码助手。运行时统一 LangChain。
- **后果**：技术栈统一在一个 Python 服务内；减少异构运维。

## ADR-012 教材版权合规约束
- **背景**：人教版等教材受版权保护。
- **决策**：开发/自用阶段可使用；凡做成对外分发产品，**上线前必须取得教材版权授权或改用公版/自编内容**。
- **备选**：忽略版权（不可行）、仅用公版内容。
- **后果**：自用无碍；对外产品上线前的硬门槛，需提前规划。

## ADR-013 后端工程基线：基于 fastapi/full-stack-fastapi-template 二次开发
- **背景**：早期方案手写 FastAPI（SQLAlchemy async + bcrypt 直连 + 独立 pydantic schemas）。用户要求后端架构基于官方全栈模板做二次开发，以获得成熟的分层、认证、测试与部署基线。
- **决策**：后端以 `fastapi/full-stack-fastapi-template` 为基线，裁剪后保留其核心约定并移植我们的业务：
  - **ORM 改用 SQLModel**（原手写方案为 SQLAlchemy async + 独立 Pydantic schemas）。这是与早期 spec「async」表述的**有意偏离**——为忠实「基于模板二次开发」，跟随模板走**同步** SQLModel（`create_engine` + `Session`）。
  - **认证改用 `pwdlib[argon2,bcrypt]` + `pyjwt`**（模板默认），取代早期手写的「bcrypt 直连」。这正好规避了 `passlib` 与新版 `bcrypt` 的冲突（早期踩过的坑）。
  - **丢弃模板的 React 前端**（我们前端是独立 Flutter App）、**丢弃邮箱体系**（无 SMTP/EMAIL/FIRST_SUPERUSER）、**丢弃 Traefik**（家用不需公网 HTTPS）。
  - **保留并采用**：`core/`（config/db/security/deps）、`api/`（deps/main/routes）、`crud.py`、`models.py`、`tests/conftest` 的 db 覆盖模式、pytest、`pyproject`（ruff/hatchling）、Dockerfile、docker-compose。
  - **API 统一前缀 `/api/v1`**；路由：`auth`(register/login, JSON) / `children` / `tasks`(generate/today/answer/checkin/progress) / `health`。
  - **Python 锁定 3.14**（跟随模板；2026 年中模板已升 3.14，LangChain 等生态应已跟上）。
- **备选**：仍用手写 async SQLAlchemy 方案；或仅「文档对齐」而不实际脚手架。
- **后果**：获得生产级认证/测试/部署基线，二次开发收益大；代价是 ORM 由 async 变 sync（本期功能无影响，未来若有高并发实时需求再评估 async）；领域层（`domain/`）仍以「LLMProvider 抽象 + 工厂」保持可插拔，不破坏 ADR-003。
