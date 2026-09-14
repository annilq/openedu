# Feature-first 后端架构：按业务分包 + 共享内核

后端按业务 feature 分包，每个 feature 自带 router / service / repository / schemas；跨 feature 共享逻辑（AI runtime、领域规则）收口到 `app/ai` 与 `app.domain` 共享内核；ORM 表集中到 `app.db.models`（dao 层），避免 feature 间相互 import 引发循环依赖。

- **集中 ORM 层**：所有 `table=True` 实体集中在 `app.db.models`，因外键相互引用，集中放置可避免 feature 包间循环依赖（`backend/app/db/models/__init__.py:1`、`:15`）。
- **Feature 分包**：`app/features/*` 每个子包拥有自身 router+schemas+repository+service（`backend/app/features/__init__.py:1`、`:3-5`）；health/children/questions/auth 均标注 feature-first（`backend/app/features/health/__init__.py:1`、`children/__init__.py:1`、`questions/__init__.py:1`、`auth/__init__.py:1`）。
- **AI 共享内核**：`app/ai` 是跨 feature 的 AI runtime（ADR-0027 共享内核），编排 subagents 并桥接 Genkit 引擎，不归属任何单一 feature（`backend/app/ai/__init__.py:3`）。
- **service 承载业务逻辑**：tasks 业务逻辑（读/写路径）全部下沉到 service 层，router 只做「鉴权 → 调 service → 翻译响应」，避免 router 膨胀 700+ 行（`backend/app/features/tasks/service.py:1`、`:5-7`）。
- **router 仅 HTTP 翻译**：mastery 的越权校验与看板聚合下沉到 service，REST 与查询工具共用，router 只接参数（`backend/app/features/mastery/router.py:11`）；children 的孩子列表读口径由 service 收口（`backend/app/features/children/service.py:1`、`:17`）。

**Considered Options**：① 按技术层（routers/services/models 平铺）组织（易循环依赖、跨 feature 耦合，拒绝）；② feature-first 分包 + 共享内核 + 集中 ORM（采用）。

**Consequences**：新增业务线只需新增 feature 子包；共享逻辑集中在 `app/ai`、`app/domain`；ORM 改动只动 `app.db.models`；router 保持薄，分层不变量（service 不 import fastapi）由测试守护。
