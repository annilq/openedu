# 娃娃学习 App — Flutter 前端

> Clean Architecture + Riverpod + Dio，平板优先

## 快速开始

```bash
# 1. 安装依赖
cd frontend
flutter pub get

# 2. 启动后端（另开终端）
cd ../backend
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
cp ../.env.example ../.env
uvicorn app.main:app --host 0.0.0.0 --port 8000

# 3. 运行 App（改 lib/configs/app_config.dart 中的 apiBase 为电脑局域网 IP）
flutter run
```

## 架构分层

```
lib/
├── configs/          # 环境配置 (API Base URL)
├── main/             # App 入口 + ProviderScope
├── shared/           # 跨 feature 复用
│   ├── data/         # local(StorageService) + remote(Dio+拦截器)
│   ├── domain/       # models + core_providers
│   ├── exceptions/   # AppException / HttpException
│   ├── theme/        # 护眼暖色主题 (≥20sp, 大圆角)
│   └── widgets/      # AppLoading / AppError
├── services/
│   └── auth_session/ # 全局登录态 (token + UserModel)
├── features/         # 按业务模块隔离
│   ├── authentication/  # 登录/注册 (→ /auth/me 获取用户)
│   ├── home/            # 家长端(娃娃列表+生成任务+进度) / 娃娃端(今日任务)
│   ├── practice/        # 做题闭环 (出题→作答→即时批改→解析→下一题)
│   ├── children/        # 娃娃账号管理
│   └── profile/        # 个人设置/退出
```

每个 feature 内部三层：
- `data/` — DataSource (调 NetworkService) + Repository 实现
- `domain/` — Repository 抽象 + Provider (接线)
- `presentation/` — Notifier(状态机) + Screen(UI)

## 状态管理

Riverpod `StateNotifierProvider` + sealed class 状态机：

```
Idle → Loading → Success(data) / Error(message)
```

各 feature 的 Notifier 独立管理状态，UI 通过 `ref.watch` 监听、`ref.read(notifierProvider.notifier).method()` 触发。

## 网络层

Dio + 双拦截器：
1. **Token 拦截器**：从 StorageService 取 JWT，注入 Authorization header
2. **错误拦截器**：非 2xx 转 HttpException，401 转 UnauthorizedException

## 后端 API 契约

| 端点 | 方法 | 角色 | 说明 |
|---|---|---|---|
| `/api/v1/auth/register` | POST | 公开 | 注册家长账号，返回 Token |
| `/api/v1/auth/login` | POST | 公开 | 登录，返回 Token |
| `/api/v1/auth/me` | GET | 已登录 | 获取当前用户信息 (role/grade) |
| `/api/v1/children` | POST | 家长 | 创建娃娃账号 |
| `/api/v1/children` | GET | 家长 | 列出娃娃 |
| `/api/v1/tasks` | POST | 家长 | 生成任务 (含答案，家长可见) |
| `/api/v1/tasks/today` | GET | 娃娃 | 今日任务 (不含答案，防作弊) |
| `/api/v1/tasks/{id}/answer` | POST | 娃娃 | 提交答案，返回批改结果 |
| `/api/v1/tasks/{id}/checkin` | POST | 娃娃 | 打卡 |
| `/api/v1/tasks/children/{id}/progress` | GET | 家长 | 正确率+连续打卡 |

## 平板适配

- 正文 ≥ 20sp，选项 ≥ 22sp
- 护眼暖色主题（低饱和、大圆角）
- 大点击区（按钮高度 ≥ 52）
- 横屏友好布局
