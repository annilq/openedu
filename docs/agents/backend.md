# 后端约定 — 娃娃学习 App

适用目录：`backend/`。基线为 `fastapi/full-stack-fastapi-template` 二次裁剪（ADR-013）。

## 技术栈与运行

- **FastAPI + uvicorn**，Python ≥ 3.14，依赖用 **uv**（`uv sync`）。
- **SQLModel**（SQLAlchemy + Pydantic 合一）。**数据库会话是同步的**（`create_engine` + `Session`）。
- **LangChain（可选）**：仅当 `LLM_PROVIDER=langchain|deepseek` 时延迟导入；`mock` 模式零 langchain 依赖。
- PostgreSQL 生产 / SQLite 本地回退（`DATABASE_URL` 切换）。

## 分层与关键隔离

```
api/routes/ + api/deps   →  domain/ (抽象+工厂+纯函数)  →  models.py(SQLModel) + core/db + crud
```

- 业务（`api/`、`domain/`）**从不直接 import langchain**；厂商适配只在 `LangChainProvider` 内。
- 换模型 = 改 `LLM_PROVIDER` / `LLM_BASE_URL` / `LLM_MODEL` / `DEEPSEEK_*`，业务零改动。
- **LLMProvider 方法均为 `async`**（`generate_question` / `grade_open` / `tutor` 声明 `async def`，内部 `await model.ainvoke(...)`）。web 层是同步路由，业务层用 `asyncio.run()` 在独立线程调用 provider，避免事件循环冲突。（已与代码核对；`../architecture/技术架构_后端.md` §5.1 的旧「同步」描述已修正。）

## 数据建模约定

- **「模型即 schema」**：`UserBase` 派生 `UserCreate` / `User`(表) / `UserPublic`(响应)，不另建 pydantic schemas 文件。
- 主键一律 **UUID**（`uuid.uuid4`），无自增。
- JSON 字段用 `Field(default=None, sa_type=JSON)`（Postgres）并兼容 SQLite `TEXT`。
- 答案安全：`Question.answer` 仅家长端 `generate` 接口返回；娃娃端 `/tasks/today` 恒为 `None`（防作弊）。

## 配置与安全

- 全部走 `pydantic-settings` + 环境变量 / `.env`；密钥不入库。
- 密码：`pwdlib[argon2,bcrypt]` 哈希；鉴权：`pyjwt`（HS256）。
- 角色守卫：`require_parent` / `require_child`；归属校验越权返回 403 / 400。
- `SECRET_KEY` 生产必须改；`CORS_ORIGINS` 生产收紧为平板 App 域名 / IP。

## 错误码

- `core/errors.py` 的 `ErrCode`：系统级 `10xxx`，业务级分段 `20xxx` Tasks / `30xxx` Auth / `40xxx` Review / `50xxx` WrongQuestions / `60xxx` Tutor / `70xxx` Children。
- 错误体统一 `{"code":"TASK_20014"|20014, "message":"...", "status":403, "data":null}`；HTTP 状态码保持语义（401/403/404/409/422/500）。详见 [domain-model.md](domain-model.md)。

## 迁移（无 Alembic，一期）

- `init_db()` 直接 `create_all`；新增列需在 `core/db.py` 的 `run_migrations()` 里做 **ALTER + 回填**，并做列存在性检查保证幂等（同时兼容 sqlite `TEXT` 与 postgres `JSON`）。

## 测试

- `pytest`；`tests/conftest.py` 用独立临时 DB 覆盖（`TestClient`）。
- 真实模型 smoke 用 `-m smoke` + `RUN_LLM_SMOKE=1`（需 key）。
- 门禁：`uv run ruff check .` 与 `uv run pytest` 通过后再算完成。

## 相关资源（架构文档导航）

- 后端架构（**事实源**） → [../architecture/技术架构_后端.md](../architecture/技术架构_后端.md)（已修正 §5.1 async / §6 Task 状态两处过期描述）。
- 业务功能与架构分析（与上文重叠，互补阅读） → [../architecture/项目分析_架构规范与业务功能.md](../architecture/项目分析_架构规范与业务功能.md)。
- 设计评审 skill：`/impeccable` 偏前端设计；后端暂无专用编码 skill，本文件即事实源。
