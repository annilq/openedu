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

## Riverpod 反模式清单（门禁级）

状态机为 `StateNotifierProvider` + sealed 状态（`Idle→Loading→Success/Error`）。下列反模式**直接违反架构约束，提交前必须清零**：

### ❌ 反模式 #1：在 `build` 期间同步修改被 `watch` 的 provider（卡死 Loading）

- **现象**：页面 / 区块永远转圈；多个页面共用同一 provider 时一起卡死。
- **根因**：在 `build` 内直接 `ref.read(provider.notifier).load()` 会同步改写被本组件 `watch` 的 provider，触发重入重建循环 `Idle → load → Loading → rebuild → Idle …`，使共享 provider 永远停在 `Loading`。
- **✗ 错误写法**：
  ```dart
  final s = ref.watch(parentTasksNotifierProvider);
  if (s is ParentTasksIdle) {
    ref.read(parentTasksNotifierProvider.notifier).load(); // build 内同步改状态
  }
  ```
- **✓ 正确写法**（任选其一，均不在 build 内改状态）：
  - 屏幕级首次加载：`initState` / `addPostFrameCallback` 内触发；
  - 区块级「空闲时触发一次」：用 `ref.loadWhenIdle(provider, isIdle, load)`（`lib/shared/utils/load_once.dart` 一行封装，已内置「本帧绘制后 + 再判空闲」双重保护）；
  - 用户操作 / 重试：按钮回调、`ref.listen` 副作用中触发。
  ```dart
  ref.loadWhenIdle(
    parentTasksNotifierProvider,
    (s) => s is ParentTasksIdle,
    () => ref.read(parentTasksNotifierProvider.notifier).load(),
  );
  ```

### ❌ 反模式 #2：把 `ref.read(provider.notifier)` 的副作用放进 `build` 主体

任何会触发网络请求 / 改状态 / 注册监听的调用，都必须在 `initState`、生命周期回调或事件回调内，禁止出现在 `build` 直接执行路径中（原因同上）。

> 自查：grep 每个 `*_view.dart` / `*_screen.dart` 的 `build` 方法体，确认没有 `load()` / `refresh()` / `notifier).xxxx()` 这类副作用调用。

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
