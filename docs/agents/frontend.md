# 前端约定 — 娃娃学习 App

适用目录：`frontend/`（Flutter + Riverpod + cupertino_ui，Clean Architecture）。

## 包管理器与命令

- **Flutter / Dart**（`flutter pub get`），不是 npm。Dart ≥ 3.5。
- Lint 门禁：**`flutter analyze` 零警告**（`analysis_options.yaml` 继承 `flutter_lints`）。每个阶段都必须保持绿色。
- 测试：`flutter test`；状态机用 `mocktail`。

## 单文件行数门禁（强约束）

- 屏幕 / 组件文件 **≤ 300 行**（含 import / 空行）；屏幕骨架尽量 < 200 行。
- 按「视觉区块」拆，而非机械切行；跨特性复用 → `lib/shared/widgets/`（`App*` 前缀语义组件）；特性内私有 → `lib/features/<f>/presentation/widgets/`。
- 自查：`find lib \( -name "*_screen.dart" -o -name "*_view.dart" -o -path "*/widgets/*.dart" \) -exec wc -l {} + | sort -rn`
- 完整规则见 [frontend/CODE_CONVENTIONS.md](../../frontend/CODE_CONVENTIONS.md)。

## 架构

- Clean Architecture + Riverpod；依赖方向 UI → domain Provider → Repository → DataSource → 后端 REST（外层依赖内层，不反向）。
- 状态用 `StateNotifierProvider` + sealed 状态机 `Idle→Loading→Success/Error`（tutor 为 `Idle→Loading→Loaded`，错误保留气泡）。
- 网络层：Dio + 双拦截器（Token 注入 `Authorization`、错误统一转 `HttpException`）；抽象为 `NetworkService`。
- `lib/configs/app_config.dart` 的 `kApiBase` 切换后端地址（真机联调用 `--dart-define=API_BASE=http://<局域网IP>:8000`）。

## UI 组件与令牌

- 一律使用 `lib/shared/theme/app_theme.dart` 导出的 **`App*` 语义组件**（`AppCard` / `AppPrimaryButton` / `AppTextField` / `AppPickerField` / `AppToast` / `AppSidebar` / `AppProgressBar` 等）。
- **禁止 `Colors.*` 硬编码**；间距 / 圆角 / 字号走 `AppSpacing` / `AppRadius` / `AppText` 令牌。
- 表现层已全面迁移至 **`cupertino_ui`**（`flutter/material.dart` 仅剩 `app_theme.dart` 的窄 `show ThemeMode` 导入，因 `ThemeMode` 无 Cupertino 等价物）；迁移契约见 `frontend/.migration_guide.md`，**不要引入新的 Material widget**。

## 导航

- `DesktopShell` + `AppSidebar`（左侧菜单 + 右侧内容），家长 / 娃娃双角色均采用；底部 Tab 已删除（ADR-0002 / ADR-0003）。侧栏可收缩态持久化。

## 设计系统（唯一事实源）

- 当前规范 = **中性 + 靛蓝、15sp 密排、无阴影、家长专业体验优先**（ADR-0003）。完整令牌 / 字号阶梯 / 动效分级见 [frontend/.impeccable.md](../../frontend/.impeccable.md) 与 [frontend/CONTEXT.md](../../frontend/CONTEXT.md)，本文件不重复。
- ⚠️ `frontend/.github/copilot-instructions.md` 的旧「暖绿 / ≥20sp / 低龄友好」设计已过期，已重写为指向上述事实源的指针。

## Skill 导航（编码代理可调用）

- `/impeccable`：设计评审 / 审计 / 打磨，基于 [../../../frontend/.impeccable.md](../../../frontend/.impeccable.md) 的设计系统令牌（中性 + 靛蓝 / 15sp / 无阴影）。
- 暂未安装 Flutter 专用编码 skill；本文件 + `CODE_CONVENTIONS.md` + `.impeccable.md` 即事实源。
