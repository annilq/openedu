# 开发 / 部署指南

本文件回答「我怎么把它跑起来、怎么改」。产品功能说明见 [README.md](README.md)；面向编码代理的架构与规范见 [AGENTS.md](AGENTS.md) 与 `docs/agents/`。

技术栈：**Flutter 平板 App（Riverpod + Dio + Cupertino + shadcn_ui，tablet-first）+ Python/FastAPI/SQLModel 后端（单 wheel 含 `agent_core` 内核）+ SQLite（默认）/ PostgreSQL**。

---

## 架构

```
Flutter 平板 App（娃娃端 / 家长端，Riverpod + Dio + Cupertino + shadcn_ui，tablet-first）
        │  HTTP/JSON（/api/v1）+ SSE 流式（/api/v1/assistant/chat）
        ▼
FastAPI 后端（单 wheel 含两个包）
  ├─ agent_core/   框架无关 agent 内核（零 app 依赖、零三方依赖；仅 adapters/genkit.py 接 genkit）
  │     └─ ports / runtime / subagent / protocol / registry / router / tools
  └─ app/         FastAPI 集成层
        ├─ api/main.py       聚合 features/* router
        ├─ core/             config / db / security / guard(归属·可见性单一真相源) / errors / deps
        ├─ domain/           grader · review_scheduler(间隔重复 0..4) · mastery · safety · retriever
        ├─ features/         每业务含 router/service/repository/schemas
        ├─ ai/subagents/     query(查询) / question(出题) / tutor(伴学) + subject_personas
        └─ db/models/        User · Task · Question · TaskQuestion · Conversation / Message · …
        │
        ▼
SQLite（本地零依赖，默认） / PostgreSQL（Docker / 云）
```

**所有 AI 能力经单一 SSE 入口** `POST /api/v1/assistant/chat`（流式事件帧：USER_MESSAGE / THINKING / TOOL_CALL / TOOL_RESULT / DATA / ASSISTANT_MESSAGE / DONE）。出题 / 伴学 / 查询都走此入口，旧的 `/ai/tutor/ask`、`/ai/tasks/generate` 已废弃并收敛到此。

核心原则：

- **不在 LangChain 之上重复封装 provider**：`LLMProvider` 是 `agent_core/ports.py` 里的抽象端口，业务只认抽象、不绑框架；引擎解析收敛到 `resolve_engine`（读家长 `ModelConfig`），无内置目录、无本地 `LLM_PROVIDER` 等旁路 env。
- **模型必须经「模型管理」配置**：出题 / 答疑 / 批改都需真实引擎；未配置时返回「未配置模型」提示，没有离线 `mock` 兜底。
- 分层不变量（内核不反向依赖 app / fastapi、genkit 唯一落点、归属判定只经 `core.guard`）由 `tests/ai/test_layering_invariants.py` 静态扫描守住。

## 目录

```
.
├── backend/                 # Python 后端（uv 管理，Python >= 3.14，单 wheel 含 app + agent_core）
│   ├── app/
│   │   ├── main.py          # FastAPI 入口（app.main:app）
│   │   ├── api/main.py      # 聚合所有 features/* router（挂在 /api/v1）
│   │   ├── core/            # config(env) / db / security / guard / errors / deps / crypto
│   │   ├── domain/          # grader · review_scheduler · mastery · safety · retriever · prompts
│   │   ├── features/        # auth children tasks review mastery tutor questions
│   │   │                    # model_management ai assistant export health
│   │   ├── ai/              # engine.py(resolve_engine) / subagents/{query,question,tutor,guide}
│   │   └── db/models/
│   ├── agent_core/          # 框架无关 agent 内核（零 app/三方依赖）
│   ├── scripts/             # copyright_compliance_check.py（版权合规门禁）
│   └── Dockerfile
├── frontend/                # Flutter 平板 App
│   ├── lib/
│   │   ├── main/            # 入口 + AdaptiveShell（响应式壳）
│   │   ├── configs/app_config.dart   # API Base URL（--dart-define=API_BASE 注入）
│   │   ├── features/        # auth / children / home / practice / review / tutor / assistant
│   │   │                    # export / model_management / profile
│   │   ├── shared/          # data / domain / presentation / theme(设计令牌) / widgets
│   │   └── dev/             # theme_preview.dart（设计系统自检）
│   └── analysis_options.yaml # flutter_lints + 设计系统硬约束
├── .env.example             # 后端本地配置模板（复制为 .env）
├── docker-compose.yml       # PostgreSQL + backend 一键起
└── docs/agents/             # 面向 AI 代理的架构 / 规范 / 命令文档
```

---

## 快速开始

### 方式 A：本地直接跑（无需 Docker，推荐先验证）

后端用 `uv` 管理依赖（Python ≥ 3.14，`uv.lock` 已锁定）。本地默认 SQLite，零额外依赖；但 AI 出题 / 答疑 / 批改需先在「模型管理」配置模型（见下方），否则相关接口返回「未配置模型」提示。

```bash
# 1) 复制配置模板到仓库根目录（后端会优先读取根目录的 .env）
cp .env.example .env

# 2) 安装依赖并启动（首次 uv sync 会自动创建虚拟环境）
cd backend
uv sync
uv run fastapi dev            # 开发模式，热重载，地址 http://localhost:8000
# 或：uv run uvicorn app.main:app --reload
```

> 不装 uv 也可：`python3.14 -m venv .venv && source .venv/bin/activate && pip install -e . && fastapi dev`。

健康检查：`curl http://localhost:8000/api/v1/health`

#### 平板 / 真机联调（重要）

本地 `fastapi dev` / `uvicorn --reload` **默认只绑定 `127.0.0.1`**。当 App 跑在真机、平板或模拟器上时，`127.0.0.1` 指向的是**设备自身**而非你的电脑，会导致登录 / 请求报「请求失败 (-1)」且服务端无任何日志（请求根本没进来）。

联调时后端必须放开监听地址，并用电脑**局域网 IP**（不是 `127.0.0.1` / `localhost`）：

```bash
cd backend
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# 前端（另开终端），API_BASE 填电脑局域网 IP：
cd frontend
flutter run --dart-define=API_BASE=http://<电脑局域网IP>:8000
```

> 查电脑局域网 IP：`ifconfig | grep "inet "`（忽略 127.0.0.1）。Docker 方式已默认 `--host 0.0.0.0`，无需此步。
> 若仍连不上：先 `curl http://<电脑局域网IP>:8000/api/v1/health` 确认后端可达；检查防火墙是否放行 8000。

### 方式 B：Docker 一键（PostgreSQL）

```bash
cp .env.example backend/.env    # 按需改 SECRET_KEY / MODEL_APIKEY_SECRET
docker compose up --build       # 启动 PostgreSQL + backend，后端暴露 8000
```

---

## 命令速查

### 后端（目录 `backend/`）

| 动作 | 命令 |
|------|------|
| 安装依赖 | `uv sync` |
| 本地起服（仅本机） | `uv run fastapi dev` 或 `uv run uvicorn app.main:app --reload` |
| 局域网联调（真机 / 平板必用） | `uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload` |
| Lint（零 error 门禁） | `uv run ruff check .` |
| 测试 | `uv run pytest -q` |
| 真实模型 smoke | `RUN_LLM_SMOKE=1 SMOKE_MODEL_NAME=llama3 SMOKE_MODEL_API_KEY=ollama uv run pytest tests/domain/test_llm_smoke.py -m smoke -v` |
| 版权合规自检 | `python scripts/copyright_compliance_check.py --self-test` |

### 前端（目录 `frontend/`，Flutter ≥ 3.5）

| 动作 | 命令 |
|------|------|
| 安装依赖 | `flutter pub get` |
| 起服（联调） | `flutter run --dart-define=API_BASE=http://<电脑局域网IP>:8000` |
| 静态分析（零 issue 门禁） | `flutter analyze` |
| 测试 | `flutter test` |
| 设计系统自检 | 运行 `lib/dev/theme_preview.dart` 页面核对令牌一致性 |
| 重新生成图形几何 | `python3 frontend/scripts/gen_figures.py`（改了 `backend/.../scene_figures.py` 顶点后必跑） |

### 跨语言生成物（目录 `frontend/scripts/`）

有一类文件**前端要用、但事实源在后端**：顶点几何、场景定义这类数据，若前后端各
手写一份，漂移只是时间问题（而且漂移会让「是否轴对称」判定变错，学生拖轴永远对
不上）。对策是**后端单一手写源 + 构建期生成前端常量**，而不是运行时拉取——整库
画廊必须离线可用（tablet-first / 离线教室）。

| 脚本 | 生成什么 | 源 | 什么时候必须跑 |
|------|----------|-----|----------------|
| `gen_figures.py` | `frontend/lib/shared/domain/figures.dart` | `backend/app/features/materials/scene_figures.py` 的 `FIGURES` | **改了任何顶点 / 轴角度 / 名称之后** |

```bash
python3 frontend/scripts/gen_figures.py           # 生成（幂等，重复跑无 diff）
python3 frontend/scripts/gen_figures.py --check    # 只校验是否过期，过期退出码 1
```

忘了跑不会有任何报错提示——前端照旧渲染旧几何，直到某道题判定出错才被发现。所以
`--check` 已接进后端测试（`test_scene_figures.py::test_frontend_figures_are_not_stale`），
过期即红灯。

### 平台目录补丁（目录 `frontend/scripts/`）

⚠️ `frontend/.gitignore` 第 20–25 行忽略 `android / linux / macos / web / windows / ios`，
**平台目录全是本机生成物、不在版本控制里**。凡是必须写进原生层的改动（窗口尺寸、
Info.plist、entitlements、AndroidManifest），只在改的那台机器上生效——
`flutter create` 重新生成或换机器构建都会**静默回退**。已定的对策是**打补丁脚本**
（而非把平台目录纳入版本控制），脚本可反复运行（幂等）。

| 脚本 | 补齐什么 | 什么时候必须跑 |
|------|----------|----------------|
| `patch_macos_network.py` | macOS entitlements 的 `network.client` 与 Info.plist 的 `NSAllowsLocalNetworking` | 重新生成 macOS 平台后；App 发不出 HTTP 且后端零日志时先跑它 |
| `patch_voice_permissions.py` | iOS/macOS 的 `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription`、macOS 的 `com.apple.security.device.audio-input`、Android 的 `RECORD_AUDIO` | 重新生成平台目录或换机器后；助手语音输入（ADR-0063）生效前 |
| `patch_spm_cwl_mirror.py` | SwiftPM 对 `CwlCatchException` 的 mirror 映射 + 本机 bare 镜像 + gitconfig 清障（`speech_to_text` 的远程依赖，ADR-0063） | 换机器 / 清过 SwiftPM 缓存后；`flutter run -d macos` 报 `Couldn't get the list of tags` 时 |

```bash
python3 frontend/scripts/patch_voice_permissions.py           # 补齐
python3 frontend/scripts/patch_voice_permissions.py --check    # 只检查不写入，缺则退出码 1

python3 frontend/scripts/patch_spm_cwl_mirror.py              # 补齐
python3 frontend/scripts/patch_spm_cwl_mirror.py --check       # 只检查不写入，缺则退出码 1
```

> 这两个脚本改的是**机器级 / 平台目录**的东西（`~/.swiftpm`、`~/.openedu-deps`、
> gitconfig、`macos/**`），都不在版本控制里，所以只能靠脚本复现；换机器后重跑即可。

`--check` 是给 CI / 构建前自检用的。原生权限缺失的失效方式是**静默**的——
界面上看不出任何异常（语音能力门禁会判定 `unsupported`、麦按钮根本不渲染），
只有 `--check` 能把它变成一条会失败的检查。

### Apple 构建：`CwlCatchException` 解析到本机镜像（不需要访问 github）

ADR-0063 引入的 `speech_to_text`（7.5.0）在 `darwin/speech_to_text/Package.swift` 里
**硬依赖** `https://github.com/mattgallagher/CwlCatchException.git`（`from: "2.0.0"`）。
Flutter 默认开启 Swift Package Manager，于是 iOS/macOS 构建必须先解析这个包；解析不通
时报 `Could not resolve package dependencies: Couldn't get the list of tags`。

**解法：跑一次补丁脚本，之后全程离线**（本机级改动，不在版本控制里，所以必须脚本化）：

```bash
python3 frontend/scripts/patch_spm_cwl_mirror.py           # 补齐（幂等，可反复跑）
python3 frontend/scripts/patch_spm_cwl_mirror.py --check    # 只检查不写入，缺则退出码 1
cd frontend && flutter clean && flutter run -d macos
```

它做三件事：

1. 在 `~/.openedu-deps/CwlCatchException.git` 放一份 bare 镜像——优先从 SwiftPM 自己的
   缓存 `~/Library/Caches/org.swift.swiftpm/repositories/CwlCatchException-*` 复制（离线
   可得）；缓存没有才 `git clone --mirror`（git 命令行会读 gitconfig 的代理，能通）。
2. 写 SwiftPM mirror 映射，让 libgit2 改从 `file://` 拿 refs：全局
   `~/.swiftpm/configuration/mirrors.json` + 工程级两份
   `macos/**/xcshareddata/swiftpm/configuration/mirrors.json`（两个 workspace 都写）。
3. 清掉 gitconfig 里会挡路的 `safe.bareRepository = explicit`（见下，原值自动备份）。

实测（2026-10-06）：配好后 `swift package resolve` 输出
`Fetching file:///Users/…/CwlCatchException.git` → `resolved at 2.2.1`（revision
`07b2ba21…`，与官方 tag 一致），全程约 2 秒，零网络访问。

#### 为什么「配了 gitconfig 还是报同样的错」——两根暗桩

| 暗桩 | 真相 |
|---|---|
| `url.<x>.insteadOf` | **libgit2 不认它**。SwiftPM 拉 git 依赖用 libgit2，不是 git 命令行；`insteadOf` 是命令行的特性。所以配了它，SwiftPM 照旧直连 github。唯一生效的是 SwiftPM 自己的 mirror 配置 |
| `safe.bareRepository = explicit` | 若全局 gitconfig 里有这一项，libgit2 会拒绝打开 SwiftPM 的**裸**缓存仓库：`fatal: cannot use bare repository '…' (safe.bareRepository is 'explicit')`。症状同样是「Couldn't get the list of tags」，但根因已经在本地了 |

另外 mirrors.json 的 schema **以 `swift package config set-mirror` 的实际输出为准**：
`{"version": 1, "object": [{"mirror": …, "original": …}]}`。网上老资料里的
`{"object": {"mirrors": [...]}}` 会让 SwiftPM 直接崩
`DecodingError.typeMismatch: expected Array<Any> … Path: object`。

**不要**用 `flutter config --no-enable-swift-package-manager` 退回 CocoaPods：它是机器
全局配置（影响其他项目）、Flutter 官方声明未来版本不允许禁用，而且**对这个问题无效**——
`speech_to_text.podspec` 同样声明了 `s.ios/s.osx.dependency 'CwlCatchException'`。

#### 别试图「换掉这个依赖」——它不是我们引入的，也没有等价替代

`CwlCatchException` 写在插件自己的两个清单里，**不在本项目 `pubspec.yaml`**，改不了：

- `darwin/speech_to_text/Package.swift` → `.package(url: "…/CwlCatchException.git", from: "2.0.0")`
- `darwin/speech_to_text.podspec` → `s.ios/s.osx.dependency 'CwlCatchException'`
- 且插件源码 `SpeechToTextPlugin.swift`（981 行）里 3 处 `try catchExceptionAsError { }`
  是**真在用**——Swift 无法直接 catch Objective-C 异常，靠这个库桥接。不是误引入。

已验证的三条死路：

| 做法 | 结果 |
|---|---|
| 升级到 `7.6.0-beta.4`（最新） | ❌ `Package.swift` 与 podspec 一字未改，同样依赖 |
| 退回 CocoaPods | ❌ podspec 同样声明，见上 |
| 换 `manual_speech_to_text` | ❌ 它本身就是 `speech_to_text` 的包装，依赖里就有它 |

其他候选也不成立：`speech_recognition` 只支持 iOS/Android（我们要 macOS 主力）；
`whisper_ggml` / `vosk_flutter_2` / `sherpa_onnx` 属端侧模型方案，要额外下载几十 MB～
GB 级模型文件，与 ADR-0063 §2「音频不出设备 + 零模型配置即可用」的定案冲突。

⇒ 结论：**保留 `speech_to_text`**，它是「系统自带听写 + 零配置」这条定位上唯一的选择。

#### 排查「别的 SwiftPM 依赖连不上」时：先分清是哪条通道坏了

> 这一节只在排查**镜像之外**的远程依赖时才用得上；`CwlCatchException` 走上面的脚本，
> 已不需要联网解析。

`speech_to_text` 的这个依赖是**硬需求**——插件源码 `SpeechToTextPlugin.swift` 里
真的 `import CwlCatchException`（2.2.1），绕不开。

关键在于 **Xcode / SwiftPM 只认「系统代理」，不认 `http_proxy` 环境变量**。所以
`curl https://github.com/...` 返回 200 **不能**证明 Xcode 也通，反之亦然——两条路
根本不是同一条。

```bash
scutil --proxy                                     # 取系统代理的 host:port（Xcode 走这条）
curl -m 15 -x http://127.0.0.1:<port> -o /dev/null -w '代理→%{http_code}\n' \
  'https://github.com/mattgallagher/CwlCatchException.git/info/refs?service=git-upload-pack'
curl -m 15 --noproxy '*' -o /dev/null -w '直连→%{http_code}\n' \
  'https://github.com/mattgallagher/CwlCatchException.git/info/refs?service=git-upload-pack'
```

**单次 curl 的结果会骗人**：github 在本机是间歇性可达的，务必**连测 3～5 次**再下结论。

⚠️ 最危险的误判是照着某一次的「直连通」去**关代理**或**把 github 加进绕过列表**：本机
直连 github 实测多为 000，代理才是稳定通路。那样改会把本来能通的路堵死。

⇒ 连测确认可达后重试即可；`flutter config --no-enable-swift-package-manager` 退回
CocoaPods **没用**（podspec 同样声明了这个依赖）。真正一劳永逸的做法还是照上面的
脚本把依赖解析到本机镜像。

⚠️ 另有一条独立的坑：新增原生插件后 **Hot Restart 不补原生注册**，
`flutter run` 必须完整重跑（彻底退出 App 再跑），否则插件 channel 调不通、
语音能力门禁判 `unsupported`，麦按钮按设计不渲染——控制台同样什么都不说。

### CI（`.github/workflows/`）

- `ci.yml`：frontend（`flutter analyze` + `flutter test`）→ backend（`ruff check` + `pytest`）。
- `compliance.yml`：后端 `pytest` + 版权合规门禁（ADR-0019 / ADR-0020）。

---

## 配置模型

AI 出题 / 伴学 / 批改都需真实引擎，且**无内置模型、无本地 `mock` 兜底**。只有一条路径：

**家长在「模型管理」中添加**（ADR-0039）——登录后点「添加模型」，选服务商（DeepSeek / OpenAI / Ollama / …）自动带出 base_url 与模型名建议，**填写 API Key（必填）**，保存后可「设为默认」。api_key 经 Fernet 加密落 `ModelConfig` 表；未显式指定模型时回落该默认模型。

> `provider ∈ {ollama, openai_compat}`；`base_url` 留空时 ollama 走 `OLLAMA_BASE_URL`（默认 `http://localhost:11434`）。
> **先固定 `MODEL_APIKEY_SECRET` 再加模型**：该值决定加密密钥，改它会让已存 API Key 全部解不开（事故见 `docs/adr/0038`）。加错顺序时，回到「模型管理」重填一次 Key 即可恢复。

### 资料库 / RAG 出题（ADR-0055）

出题要引用家长上传的资料，需在 `backend/.env` 配 4 项 —— **与「模型管理」无关**：embedding 是服务端基础设施（显式豁免 ADR-0039），因为向量与模型绑定是物理约束，若跟着家长的聊天模型走，家长换一次默认模型就全部存量向量作废。

| 变量 | 取值 | 说明 |
|---|---|---|
| `EMBEDDING_PROVIDER` | `none`（默认）/ `ollama` / `openai_compat` | `none` 时向量化端点显式报错，不静默假装成功 |
| `EMBEDDING_MODEL` | `bge-m3`（推荐，中文强、dense 优） | **同时是向量版本戳**，定下后不要改 |
| `EMBEDDING_BASE_URL` | ollama 填根地址；openai_compat 填带 `/v1` 的根 | 留空时 ollama 回落 `OLLAMA_BASE_URL`；内部各拼 `/api/embed`、`/embeddings` |
| `RETRIEVER_PROVIDER` | `mock`（默认）/ `vector` | `vector` 才检索家长私有资料库；未知值告警并回退 `mock` |

本地 Ollama 走一遍：

```bash
ollama pull bge-m3                      # 约 1.2GB
cd backend && uv run uvicorn app.main:app --reload
```

```dotenv
# backend/.env（改完必须重启进程——settings 在 import 期读取）
EMBEDDING_PROVIDER=ollama
EMBEDDING_MODEL=bge-m3
EMBEDDING_BASE_URL=http://localhost:11434
RETRIEVER_PROVIDER=vector
```

**生效链路**：重启后端 → 「资料库」上传 → 点向量化 → 状态徽标转「已就绪」（未向量化 = `未向量化` / 失败 = `失败`）→ 出题时上下文才带 `【资料名】` 前缀，题目随之带 `source_refs` 溯源。改了 `EMBEDDING_MODEL`（含改名，如 `bge-m3` ↔ `bge-m3:latest`）：存量资料惰性标 `已过期`，检索侧按模型名过滤，需重新向量化。

> 首片资料向量化会等 Ollama 把权重换入内存（数秒到十几秒，`EMBEDDING_TIMEOUT_S=120` 已覆盖）；同模型紧接着再调很快。embedding 调用失败**不会**阻塞出题——检索降级为词法通道，只是没有向量召回。


---

## API 速览

所有路径带 `/api/v1` 前缀。交互式文档：http://localhost:8000/docs

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/register` | 家长注册（返回 token） |
| POST | `/auth/login` | 登录 |
| GET  | `/auth/me` | 当前用户 |
| POST | `/children` | 家长添加娃娃账号 |
| GET  | `/children` | 家长列出娃娃 |
| POST | `/tasks/generate` | 家长生成题目（SSE 流式，调 LLM） |
| GET  | `/tasks/today` | 娃娃查看今日任务 |
| POST | `/tasks/{task_id}/answer` | 娃娃提交单题 → 自动批改 |
| POST | `/tasks/{task_id}/checkin` | 完成任务打卡 |
| GET  | `/tasks/wrong-questions` | 娃娃错题列表 |
| GET  | `/tasks/children/{child_id}/progress` | 家长看进度（正确率 / 连续打卡） |
| GET  | `/tasks/children/{child_id}/mastery` | 掌握度看板 |
| GET  | `/review/due` | 到期待复习题（遗忘曲线） |
| POST | `/review/answer` | 复习作答 |
| POST | `/export/sheet` | 打印导出（返回 PDF，source=bank\|task\|wrong_book） |
| POST | `/assistant/chat` | **AI 统一入口（SSE）**：出题 / 伴学 / 查询，按角色 + 触发词路由 |
| GET  | `/assistant/conversations` | 家长的会话历史（仅家长） |
| GET  | `/health` | 健康检查 |

> 伴学答疑、出题、查询统一走 `POST /assistant/chat`（流式）。`tutor` router 仅保留 `GET /logs`（伴学记录）；**每日配额管控已移除**，不存在 `/tutor/quota`。

---

## 改动前必读

- **领域术语**以仓库根 `CONTEXT.md` 为唯一事实源，已落地决策见 `docs/adr/`。
- **设计系统**：颜色 / 间距 / 字号只走设计令牌，禁止硬编码（见 `.impeccable.md` 与 ADR-0044 ~ 0048）。
- **跨层硬规则**：归属与可见性判定只经 `core.guard`；query 工具只经 service 取数。
- **提交**：按逻辑批次拆，正文写「为什么」；记忆类更新单独用 `chore(memory):` 前缀。
