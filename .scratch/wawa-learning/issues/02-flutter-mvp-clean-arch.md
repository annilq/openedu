# 02 — Flutter MVP 全量：Clean Arch + Riverpod 落地

**What to build:** 在平板 App 中建立 Clean Architecture 三层（presentation/domain/data）+ Riverpod 状态管理 + Dio 网络层，并实现一期全部页面：家长登录注册、加娃娃、出题、娃娃做题即时批改、打卡、进度看板。家长与娃娃各自在平板上完成闭环。

**Blocked by:** 01 — 测试基座：闭环 pytest 套件

**Status:** ✅ done

- [x] App 采用 presentation/domain/data 三层，依赖指向 domain；状态用 Riverpod（`StateNotifierProvider` + sealed class 状态机）；DI 用 provider 组合；Dio 拦截器注入 JWT 并统一错误为 `HttpException`
- [x] 家长可注册、登录、创建并查看娃娃账号（对应故事 1/2/27）
- [x] 家长按学科/年级/知识点/题型/难度/题量生成任务，且家长端可见答案（故事 3/4）
- [x] 娃娃只见今日任务、点选作答、即时看到对错与解析、且永不看到答案（故事 5/6/7/8）
- [x] 娃娃可打卡；家长可见正确率与连续打卡天数（故事 9/10）
- [x] 平板适配：≥20sp 文字、护眼暖色主题、大点击区、横屏友好（故事 28）
- [ ] 各 notifier 状态机（Idle/Loading/Success/Error）有 mocktail 单测 — 待补

## 实现说明

### 交付物（32 个 Dart 文件）

```
lib/
├── configs/app_config.dart
├── main.dart
├── main/app.dart
├── shared/
│   ├── data/local/storage_service.dart
│   ├── data/remote/network_service.dart
│   ├── data/remote/dio_network_service.dart
│   ├── domain/models/models.dart
│   ├── domain/providers/core_providers.dart
│   ├── exceptions/app_exception.dart
│   ├── theme/app_theme.dart
│   └── widgets/app_loading.dart, app_error.dart
├── services/auth_session/ (3 files)
└── features/
    ├── authentication/ (5 files: datasource, repo, impl, provider, notifier, screen)
    ├── children/ (5 files)
    ├── home/ (4 files: notifier, screen, parent_dashboard, child_home)
    ├── practice/ (2 files: notifier, screen)
    └── profile/ (1 file: profile_screen)
```

### 后端增量

- 新增 `GET /api/v1/auth/me` — 前端登录后获取当前用户信息（role/grade），含测试
- `tests/api/routes/test_loop.py::test_auth_me` 验证通过

### 关键设计决策

1. **无代码生成**：使用 sealed class 代替 freezed、Navigator 代替 auto_route，避免 build_runner 依赖
2. **Token 获取流程**：register/login → 返回 Token → saveToken → 调 /auth/me → 获取用户信息 → saveUserJson
3. **防作弊**：娃娃端 `/today` 接口恒不返回 answer，家长端 `generate` 返回 answer
4. **状态机统一**：所有 Notifier 用 `sealed class XxxState` + `Idle/Loading/Success/Error` 模式
