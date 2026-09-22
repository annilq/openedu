# 娃娃学习 App — Flutter 前端

> Feature-first 架构 + Riverpod + Dio + shadcn_ui，平板优先（家长端 / 娃娃端双模式）

设计语言为 **新粗野（Neo-Brutalism，ADR-0044）**：高饱和撞色 + 2px 墨黑描边 + 无模糊硬阴影 + 弹性动效；
全站颜色 / 间距 / 字号 / 转场时长只走设计令牌（`.impeccable.md`），禁止硬编码。视觉与交互细节见
`docs/agents/frontend.md` 与 `.impeccable.md`，不要在此重复。

## 快速开始

```bash
# 1. 安装依赖
cd frontend
flutter pub get

# 2. 启动后端（另开终端，需放开监听 + 局域网 IP）
cd ../backend
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# 3. 运行 App（API_BASE 填电脑局域网 IP，不要用 127.0.0.1）
flutter run --dart-define=API_BASE=http://<电脑局域网IP>:8000
```

> 后端依赖用 `uv` 管理（见根 `CONTRIBUTING.md`）；`AppConfig.apiBase` 经 `--dart-define=API_BASE` 注入，默认 `127.0.0.1:8000`。

## 架构分层

```
lib/
├── main/             # 入口 + AdaptiveShell（响应式壳，家长/儿童双模式作用域）
├── configs/          # AppConfig：apiBase 经 --dart-define=API_BASE 注入
├── features/         # 按业务模块隔离（assistant / auth / children / home / practice /
│                    #   review / tutor / export / model_management / profile）
├── services/         # auth_session（token 持久化）
├── shared/           # data / domain / exceptions / presentation / theme(设计令牌) / widgets
└── dev/              # theme_preview.dart（设计系统自检，CI 外本地跑）
```

分层与依赖方向（ADR-0037）：`main/ → features/* → shared/*` 单向；`shared/` 不得 import `features/`，
feature 之间不得横向互引（唯一豁免 `features/home/presentation/` 组合根）。feature 与后端 `app/features/*` 一一对应。
`App*` 前缀只给 `shared/widgets/` 通用组件——组件一旦订阅某 feature 的 provider 就落回该 feature。

## 状态与网络

- **状态管理**：Riverpod（`Notifier` / `AsyncNotifier` + sealed class 状态机）。各 feature 的 Notifier 独立管理状态，
  UI 通过 `ref.watch` 监听、`ref.read(notifierProvider.notifier).method()` 触发。
- **网络层**：Dio + 双拦截器——Token 拦截器（注入 `Authorization`）+ 错误拦截器（非 2xx 转 `HttpException`，401 转 `UnauthorizedException`）。

## 后端 API 契约

所有路径带 `/api/v1` 前缀；交互式文档 `http://localhost:8000/docs`。完整端点见根 `CONTRIBUTING.md` 的
「API 速览」。要点：

- 出题 / 伴学 / 查询统一走 **`POST /api/v1/assistant/chat`**（SSE 流式），按角色 + 触发词路由；
  旧的 `/ai/tutor/ask`、`/ai/tasks/generate` 已收敛到此。
- 其余 REST：`/auth/*`、`/children`、`/tasks/*`、`/review/*`、`/export/sheet`、`/assistant/conversations` 等。
