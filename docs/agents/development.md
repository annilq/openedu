# 开发规范与命令（Development）

> 本文件是 `AGENTS.md`「开发规范」「命令速查」条的钻取文档。跑任何命令前先读本节对应段落。
> 命令需在指定工作目录执行：后端在 `backend/`，前端在 `frontend/`。

---

## 1. 环境前置

- **后端**：Python ≥ 3.14（CI 锁 3.14），依赖用 `uv` 管理。首次 `uv sync` 自动建虚拟环境。
- **前端**：Flutter SDK ≥ 3.5（CI 锁 **3.47.2**），Dart ≥ 3.5。`flutter pub get` 后联调。
- **配置**：`cp .env.example backend/.env`（后端加载 `../.env` → `.env`，后者覆盖；以 `backend/.env` 为准）。AI 模型一律在客户端「模型管理」里手动添加（家长 `ModelConfig`，api_key 必填且经 Fernet 加密落库，ADR-0039）并「设为默认」——**无内置模型目录、无本地 `LLM_PROVIDER` mock 兜底**，未添加模型时出题/答疑/批改不可用。加密密钥 `MODEL_APIKEY_SECRET` 请先固定再加模型（ADR-0038）。

---

## 2. 命令速查（Commands）

### 2.1 后端（工作目录 `backend/`）

| 场景 | 命令 |
|------|------|
| 安装依赖 | `uv sync` |
| 本地起服（仅本机） | `uv run fastapi dev` 或 `uv run uvicorn app.main:app --reload` |
| **局域网联调（真机/平板必用）** | `uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload` |
| Lint | `uv run ruff check .` |
| 测试 | `uv run pytest -q` |
| 真实模型 smoke | `RUN_LLM_SMOKE=1 SMOKE_MODEL_NAME=llama3 SMOKE_MODEL_API_KEY=ollama uv run pytest tests/domain/test_llm_smoke.py -m smoke -v` |
| 健康检查 | `curl http://localhost:8000/api/v1/health` |
| 版权合规自检（门禁逻辑） | `python scripts/copyright_compliance_check.py --self-test` |

> ⚠️ `fastapi dev` / `uvicorn --reload` 默认只绑 `127.0.0.1`。App 在真机/模拟器上时 `127.0.0.1` 指向设备自身，会报「请求失败 (-1)」且服务端无日志。联调必须 `--host 0.0.0.0` + 前端 `API_BASE` 填**电脑局域网 IP**（非 `127.0.0.1`）。查 IP：`ifconfig | grep "inet "`。

### 2.2 前端（工作目录 `frontend/`）

| 场景 | 命令 |
|------|------|
| 安装依赖 | `flutter pub get` |
| 起服（联调） | `flutter run --dart-define=API_BASE=http://<电脑局域网IP>:8000` |
| 静态分析（零 issue 为门禁） | `flutter analyze` |
| 测试 | `flutter test --reporter=github` |
| 设计系统自检（本地，CI 外） | `flutter run` 后打开 `lib/dev/theme_preview.dart` 页面 |

> 改 `lib/configs/app_config.dart` 的 `AppConfig.apiBase` 也可固定后端地址，但联调优先用 `--dart-define`。

### 2.3 一键容器（仓库根）

```bash
cp .env.example .env
docker compose up --build     # PostgreSQL + backend，后端已默认 --host 0.0.0.0
```

### 2.4 Issue / PR（GitHub，用 `gh`）

全部操作经 `gh` CLI，约定见 `docs/agents/issue-tracker.md`。要点：

- 建 issue：`gh issue create --title "..." --body "..."`（多行用 heredoc）
- 读 issue：`gh issue view <n> --comments`
- 列 issue：`gh issue list --state open --json number,title,labels,comments --jq '...'`
- 打/撤标签：`gh issue edit <n> --add-label "..."` / `--remove-label "..."`
- 评论/关闭：`gh issue comment <n> --body "..."` / `gh issue close <n> --comment "..."`

Tri标签字符串见 `docs/agents/triage-labels.md`：`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`。

---

## 3. 开发规范（Standards）

### 3.1 Lint / 类型

- **后端 `ruff`**：`backend/pyproject.toml` 的 `[tool.ruff.lint]` 选 `E/W/F/I`，忽略 `E501`（行宽）。CI 跑 `uv run ruff check .`，零 error 为门禁。
- **前端 `flutter analyze`**：`analysis_options.yaml` 含 `flutter_lints`，**要求零 issue**。此外声明了设计系统硬约束（禁止裸 `Text()`、禁止硬编码 `Colors.*`/魔法十六进制），静态强制待 `custom_lint` 启用。

### 3.2 测试

- **后端 `pytest`**：分层不变量（`tests/ai/test_layering_invariants.py` AST 静态扫描）、SubAgent 契约（`test_subagents_seam.py` / `test_query_tools_contract.py`）、domain 单测（scheduler/grader/mastery/safety/retriever）分层在 `tests/{ai,api,domain,features}`。
- **前端 `flutter test`**：widget/provider 单测。
- **CI 现实约束**：沙箱环境 `flutter_tester` 无法启动、部分 AI 路由触发敏感内容保护，本地沙箱跑不了 `flutter test`/`pytest`；CI 面向真实 GitHub runner（`ubuntu-latest`）。本地验证用 `uv run ruff check .` + `flutter analyze` 兜底。

### 3.3 ADR 与领域词汇

- **决策记录**：落地决策写 `docs/adr/`（编号 `0001-` 递增，当前已落地至 0060）。被代码 docstring 引用的 ADR **必须有可定位正文**，新增决策先补 ADR 再交叉链接。
- **领域词汇**：以根 `CONTEXT.md` 为唯一术语事实源。输出（issue 标题、重构提案、测试名）必须用 glossary 术语，勿漂移其明确 avoid 的同义词（如「题目」≠「试题」；「错题」≠「错题库」；「儿童账户」≠「学生」）。
- **单 context 懒创建**：`CONTEXT.md` + `docs/adr/` 按需创建，非强制预建；缺失时 proceed silently，不主动建议预建。

### 3.4 设计系统边界（前端）

- 颜色/间距/字号/转场时长**只走令牌**（`AppColors` / `AppSpacing` / `AppText._typeScale`），组件不得硬编码。
- 任何新页面必须声明对**双模式**（Parent/Child）的适配：文案第一人称切换、字号档、学科 accent 消费；否则 `theme_preview` 自检暴露脱节。
- 层边界：AI 工具按 `shared_tool` / `query` / `tasks` 分层注册；退役包随业务一并下线，复用须按助手统一端点语义重建（ADR-0003/0033）。

### 3.5 跨层硬规则（后端）

- 取数代码的**归属/可见性判定只经 `core.guard`**，不得自行判断。
- query 工具**只经 service 取数**，不直连 db 或 router。
- `service` 不反向依赖 `router` / `fastapi`。
- 以上由 `tests/ai/test_layering_invariants.py` 静态守住。

---

## 4. CI（`.github/workflows/`）

- **`ci.yml`**：`frontend`（Flutter analyze + test）→ `backend`（ruff check + pytest）。任意步失败整轮红。推 `main` 或开 PR 触发。
- **`compliance.yml`**：后端 pytest + 版权合规门禁（ADR-0019/0020）。当前跑 `--self-test` 验证门禁逻辑；真实语料比对（导出题库 → 比对 `protected_corpus/`）上线前启用。
