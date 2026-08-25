# UI 组件清点清单（openedu · 娃娃学习）

> 范围：`frontend/lib` 全部 `.dart` 源码。
> 目标：迁入 **Flutter Shadcn UI**（`shadcn_ui` **0.56.1**，见 <https://mariuti.com/flutter-shadcn-ui/>）。
> **已确认决策**——采用官方「**Shadcn + Cupertino**」混合模式（`ShadApp.custom` + 保留 `CupertinoApp` 根 + `ShadAppBuilder` 桥接），而非纯 `ShadApp` 全量替换：
> 保留 Cupertino chrome（`CupertinoPageScaffold` / `CupertinoNavigationBar` / `CupertinoTabBar` / `CupertinoPicker` / 下拉刷新 / `CupertinoSlidingSegmentedControl` / `CupertinoIcons`），仅把「自研共享/业务组件 + 主题令牌」替换为 `shadcn_ui` 组件与 `ShadThemeData`。
> `cupertino_ui`（独立包）最终从 `pubspec.yaml` 移除（注入依赖替换后）。

---

## 1. 组件分布总览

| 类别 | 数量 | 说明 |
| --- | --- | --- |
| 第三方 UI 包 | 1 个直接依赖 | `cupertino_ui`（Flutter 3.47 之后 Cupertino 组件的去耦合独立包） |
| 其他第三方依赖 | 4 个 | `flutter_riverpod` / `dio` / `shared_preferences`（非 UI）、`cupertino_ui` |
| 自研共享组件 | 约 20 个 | 位于 `lib/shared/widgets/` 与 `lib/shared/theme/app_theme.dart` |
| 页面级私有组件 | 约 16 个 | 各 Screen/widget 文件中的 `_Xxx` 私有组件 |
| 主题/令牌体系 | 1 套 | `AppTheme` / `AppColors` / `AppText` / `AppSpacing` / `AppRadius` |
| Flutter 框架基元 | 大量 | `Text / Icon / Container / Row / Column / Stack / ...`（框架自带，不属迁移目标） |

**主导第三方包**：`cupertino_ui`（1.0.0）。它是本项目几乎全部「iOS 原生感」chrome（导航栏、TabBar、按钮、开关、弹窗、Picker、刷新控件）的来源；业务中大量 `Cupertino*` 组件均来自该包。

**自研组件模式（主导）**：
- 语义化 Chip/Pill 体系：`AppTags`（5 态）+ `AppBadge`（3 态）
- 扁平卡片族：`AppCard`（1px 描边 + 暖色填充、无阴影）
- 表单族：`AppTextField` + `AppPickerField<T>`（CupertinoPicker 底部面板）
- 状态族：`AppLoading`（spinner / skeleton / skeletonInline + shimmer）、`AppError`
- 轻提示：`AppToast`（Overlay 实现，替代 SnackBar）
- 运动族：`PopIn`、`PressScale`、`ConfettiBurst`（CustomPainter 彩带）
- 章节/信息位：`SectionTitle`、`AvatarSquircle`（squircle 头像）
- 主题令牌：`AppColors`（亮/暗语义色）、`AppText`（排版）、`AppSpacing` / `AppRadius`

---

## 2. 第三方组件（来自外部包）

### 2.1 `cupertino_ui`（package，v1.0.0，pub.dev）
> 提供纯 Cupertino 组件，Flutter 3.47 后从 SDK 拆出的独立包。所有经它封装的「系统级」UI 组件如下：

| 组件 | 用途 / 使用场景 |
| --- | --- |
| `CupertinoApp` / `CupertinoPageScaffold` | 根容器与页面脚手架（main/app.dart 及所有业务页） |
| `CupertinoNavigationBar` | 页面顶部导航栏（home / practice / review / wrong_questions / tutor_chat / tutor_quota / add_child 等） |
| `CupertinoTabScaffold` / `CupertinoTabBar` | 底部双 Tab 主壳（首页 / 我的） |
| `CupertinoButton` / `CupertinoButton.filled` | 各种按钮（主操作、图标按钮、登录切换、返回等） |
| `CupertinoTextField` | 输入框（答题、登录注册、AI 提问、管控设置等） |
| `CupertinoActivityIndicator` | 加载指示器（按钮 loading、整页加载） |
| `CupertinoAlertDialog` / `CupertinoDialogAction` | 结果弹窗、退出确认 |
| `showCupertinoDialog` / `showCupertinoModalPopup` | 弹窗与底部面板（Picker） |
| `CupertinoPicker` / `FixedExtentScrollController` | 底部滚轮选择（题型/年级/学科） |
| `CupertinoSlidingSegmentedControl` | 主题切换分段控件（profile_screen） |
| `CupertinoSliverRefreshControl` | 下拉刷新（child_home / wrong_questions） |
| `CupertinoNavigationBarBackButton` | 返回按钮（add_child / tutor_quota） |
| `CupertinoIcons` | 全局图标集（业务中几乎全部 icon 均来自此） |
| `CupertinoTheme` / `GlobalCupertinoLocalizations` | 主题与本地化 |
| `borderRadius` / `dark` 等 `CupertinoThemeData` 令牌 | 主题派生 |

### 2.2 其他第三方依赖（非 UI）
- `flutter_riverpod`（^2.5.1）：状态管理（`ConsumerWidget` / `ConsumerStatefulWidget` / `ref.watch` / `ref.listen` / Provider）
- `dio`（^5.4.0）：网络
- `shared_preferences`（^2.2.0）：本地持久化（主题模式、登录态）
- `flutter_sdk` 内置：Typography、`Text` / `Container` / `CustomPaint` 等框架基元

---

## 3. 自研共享组件（`lib/shared/`）

### 3.1 主题 / 令牌（`lib/shared/theme/app_theme.dart`）

| 组件 | 类型 | 位置 | 关键功能 / 使用场景 |
| --- | --- | --- | --- |
| `AppTheme` | 主题引擎 | app_theme.dart | 亮/暗双主题，`colorsOf` / `textOf` / `cupertinoLight` / `cupertinoDark` |
| `AppColors` | 颜色令牌 | app_theme.dart | 语义色集合（primary/secondary/tertiary/error/surface/…），跟随亮度 |
| `AppText` | 排版令牌 | app_theme.dart | 13 级字号/行高校准（护眼 ≥20sp 正文） |
| `AppSpacing` | 间距令牌 | app_theme.dart | 8 倍网格间距常量 |
| `AppRadius` | 圆角令牌 | app_theme.dart | chip/button/input/bubble/card/banner 圆角 |
| `ResultTone` | 枚举 | app_theme.dart | 结果页情绪分级（positive/warm/alert/neutral） |
| `AppThemeMode` | 枚举 | app_theme.dart | system/light/dark |
| `ThemeProvider` | 状态 | theme_provider.dart | 主题模式持久化 + 切换 |

### 3.2 通用组件（`lib/shared/widgets/`）

| 组件 | 类型 | 位置 | 关键功能 / 使用场景 |
| --- | --- | --- | --- |
| `AppCard` | Card | app_theme.dart | 扁平卡片（1px 描边 + 暖色填充 + 无阴影），带可选 onTap |
| `AppPrimaryButton` | Button | app_theme.dart | 主操作按钮（loading、fullWidth、圆角 14） |
| `AppProgressBar` | 进度条 | app_theme.dart | 线性进度条（掌握度、做题完成率） |
| `AppTags` | Tag/Chip | app_theme.dart | 语义 Chip：normal / info / ai / success / warning（主题 + 标签） |
| `AppBadge` | Badge | app_theme.dart | 胶囊徽标：successChip / warningChip / infoChip |
| `SectionTitle` | 区块标题 | app_theme.dart | 左侧 4px 主色条 + 标题 + 可选 trailing |
| `AvatarSquircle` | 头像 | app_theme.dart | squircle 方圆形首字头像（.small/.medium/.large） |
| `AppLoading` | 加载态 | app_loading.dart | spinner / 整页 skeleton / 内联 skeleton（含 Shimmer 动画） |
| `AppError` | 错误态 | app_error.dart | 友好图标 + 文案 + 重试按钮 |
| `AppToast` | 轻提示 | app_toast.dart | Overlay 浮动 toast（show / error），替代 SnackBar |
| `AppTextField` | 输入框 | app_inputs.dart | 扁平化输入框（label/前缀图标/错误文案，Cupertino 内核） |
| `AppPickerField<T>` | 选择器 | app_inputs.dart | 泛型选择框，点击弹 `CupertinoPicker` 底部面板（附 `_PickerSheet`） |
| `PopIn` | 动画 | app_motion.dart | 弹簧入场（缩放 + 淡入，easeOutBack），成就/结果/横幅 |
| `PressScale` | 动画 | app_motion.dart | 按压微交互（按下缩小、松开回弹），可替代 GestureDetector |
| `ConfettiBurst` | 动画 | app_motion.dart | CustomPainter 彩带爆发（全部答对庆祝），IgnorePointer |
| `reducedMotionOf` | 工具 | app_motion.dart | 尊重系统减弱动态效果 |

### 3.3 根级壳（`lib/main/app.dart`）

| 组件 | 位置 | 关键功能 |
| --- | --- | --- |
| `MyApp` / `CupertinoApp` | app.dart | 主题 + 本地化 + 会话恢复 + 登录态路由 |
| `_SplashScreen` | app.dart | 启动加载页 |
| `_MainShell` | app.dart | `CupertinoTabScaffold` 底部 Tab 主壳 |

---

## 4. 页面级私有组件（`_Xxx`，随 Screen 文件）

| 组件 | 位置 | 关键功能 |
| --- | --- | --- |
| `_ReviewBanner` | child_home.dart | 复习错题横幅（Banner 24 圆角 + CTA + 错题入口） |
| `_TutorBanner` | child_home.dart | AI 老师暖橙横幅（CTA「去提问」） |
| `_TaskCard` | child_home.dart | 今日任务卡片（AppTags + AppBadge + 开始做题 CTA） |
| `_ChildSelector` | parent_dashboard.dart | 娃娃选择器（头像 + 选中 2px 主色描边，替代 ChoiceChip） |
| `_AddChildTile` | parent_dashboard.dart | 「+ 添加娃娃」虚线入口块 |
| `_StatCard` | parent_dashboard.dart | 统计卡片（总题数/答对/正确率/连续打卡，响应式 2/4 列） |
| `_MasteryBar` | parent_dashboard.dart | 掌握度进度条 + 状态映射（植物绿/暖橙/珊瑚分级） |
| `_ParentWrongCard` | parent_dashboard.dart | 家长错题条目（标准答案 + 解析 + 分隔线） |
| `_TutorLogCard` | parent_dashboard.dart | AI 答疑日志条目（问/答 + 拦截 Badge） |
| `_OptionTile` | practice_screen.dart | 选择题选项卡（A/B/C/D 前缀 + 选中态描边） |
| `_ReviewOptionTile` | review_screen.dart | 复习页选项卡（设计同 _OptionTile） |
| `_WrongQuestionCard` | wrong_questions_screen.dart | 娃娃错题卡片（错因 + 最近答错/下次复习时间） |
| `_SubjectToggle` | tutor_quota_screen.dart | 学科多选胶囊（选中打勾 + 主色描边） |
| `_InfoRow` / `_Divider` / `_ThemeModeSetting` | profile_screen.dart | 账号信息行 / 分隔线 / 主题分段控件 |

---

## 5. 迁移到 Shadcn UI 的映射方案（自研组件 → `shadcn_ui`）

> 目标包：`shadcn_ui` **0.56.1**（已 `flutter pub add` 安装；官方文档示例如 0.2.x，API 以 0.56.1 实装为准）。采用 **Shad + Cupertino 混合**。官方「Shadcn + Cupertino」接法：

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

return ShadApp.custom(
  theme: <ShadThemeData 亮>,      // AppColors.light 映射
  darkTheme: <ShadThemeData 暗>,  // AppColors.dark 映射
  themeMode: <转换到 Material ThemeMode>,  // ShadApp.custom.themeMode 用 Material ThemeMode
  appBuilder: (context) {
    return CupertinoApp(
      theme: <CupertinoThemeData，来自 AppColors>,   // 不要依赖 CupertinoTheme.of(context)
      localizationsDelegates: const [
        GlobalShadLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      builder: (context, child) => ShadAppBuilder(child: child!),
      // 其余原 app.dart 参数照搬：title/home/locale/supportedLocales/debugShowCheckedModeBanner…
    );
  },
);
```
> 关键：`ShadTheme` 由顶层 `ShadAnimatedTheme` 提供；`ShadAppBuilder` 额外挂载 `ShadToaster/ShadSonner` 并提供背景色。`themeMode` 需转成 Material `ThemeMode`。`ShadColorScheme` 结构体构造需全部必填字段通过（background/foreground/card/…/selection + custom map）。

### 5.1 主题令牌映射

| 现有 | → | Shadcn |
| --- | --- | --- |
| `AppTheme.colorsOf(context)` | → | `ShadTheme.of(context).colorScheme`（并用 `ShadColorScheme` 自定义三强调色） |
| `AppText` 排版令牌 | → | `ShadTextTheme`（h1…h4 / p / large / small / muted），字号按护眼规范改 |
| `AppSpacing` / `AppRadius` | → | 保留自有常量（Shadcn 无等价令牌） |
| `ThemeProvider`（亮/暗/系统） | → | `ShadApp.custom(themeMode:…, darkTheme:…)` |

### 5.2 组件映射（自研 → Shadcn）

| 现有组件 | 数量级用途 | → 建议 Shad 组件 |
| --- | --- | --- |
| `AppCard`（扁平卡片） | 首页/看板/表单/结果 | `ShadCard` |
| `AppPrimaryButton` | 表单提交/CTA | `ShadButton`（primary） |
| 各页 `CupertinoButton.filled` 提交按钮 | 提交答案/保存/创建 | `ShadButton` |
| `AppTextField` | 登录/注册/建号/任务表单 | `ShadInput` / `ShadInputFormField` + `ShadField` label |
| 各页内联 `CupertinoTextField` | 答题/提问/管控 | `ShadInput` / `ShadTextarea` |
| `AppPickerField<T> + _PickerSheet` | 题型/年级/学科 | `ShadSelect` + `ShadOption` / `ShadSelectFormField` |
| `AppTags`（5 态） | 学科/年级/知识点/状态标签 | `ShadBadge`（默认/secondary/outline/destructive）+ 自定义彩色 |
| `AppBadge`（3 态） | 已完成/已拦截/正常 | `ShadBadge`（primary/secondary/destructive） |
| `_SubjectToggle` / 多选 | 学科多选 | `ShadCheckbox` 或胶囊 `ShadBadge` + 选中态 |
| `AppProgressBar` | 掌握度/正确率进度 | `ShadProgress` |
| `AppLoading`（spinner） | 整页/区域加载 | `ShadSkeleton`（骨架）+ `CupertinoActivityIndicator`（spinner，保留） |
| `AppLoading.skeleton`（shimmer） | 列表骨架 | `ShadSkeleton` |
| `AppError` | 错误占位 + 重试 | 自定义（`ShadAlert` destructive 风格 + `ShadButton`） |
| `AppToast` | 轻提示 | `ShadSonner` / `ShadToast` |
| `_ReviewBanner` / `_TutorBanner` | 首页横幅 | `ShadCard` + `ShadBadge` + `ShadButton` |
| `_TaskCard` | 任务卡片 | `ShadCard` |
| `_StatCard` | 统计卡 | `ShadCard` |
| `_MasteryBar` | 掌握度行 | `ShadCard` + `ShadProgress` + `ShadBadge` |
| `_OptionTile` / `_ReviewOptionTile` | 选择题 | `ShadCard`(可选描边) + `ShadRadio` / `ShadRadioGroup` 或 `ShadButton.outline` |
| `_ParentWrongCard` / `_WrongQuestionCard` / `_TutorLogCard` | 列表条目 | `ShadCard` |
| `SectionTitle` | 区块标题 | 保留自定义，或用 `ShadCard` header |
| `AvatarSquircle` | 头像 | `ShadAvatar`（含多格式图片支持） |
| `ResultTone` 结果页图标容器 | 完成/复习结果 | `ShadCard` + `ShadBadge` / 自定义图标色 |
| `PopIn` / `PressScale` / `ConfettiBurst` | 动画/彩带 | 保留（Shadcn 内部依赖 `flutter_animate`，可复用它替代） |
| `CupertinoAlertDialog` 结果弹窗 | 判题结果 | `ShadDialog` / `ShadDialog.alert` |
| `CupertinoSlidingSegmentedControl` 主题切换 | 外观 | `ShadTabs` |

### 5.3 Chrome / 导航层（保留 Cupertino · 已确认）

| 现有 | 处理（混合模式） |
| --- | --- |
| `CupertinoApp`（根） | **保留**，外包 `ShadApp.custom` + `appBuilder` 内 `ShadAppBuilder` |
| `CupertinoPageScaffold` | 保留（页面脚手架） |
| `CupertinoNavigationBar` / `CupertinoNavigationBarBackButton` | 保留（Shadcn 无顶部导航栏） |
| `CupertinoTabScaffold` / `CupertinoTabBar` | 保留（Shadcn 未提供底部导航） |
| `CupertinoSliverRefreshControl` | 保留（Shadcn 未提供下拉刷新） |
| `CupertinoIcons` | 保留（shadcn 依赖 lucide_icons 一并可用，非必须替换） |
| `showCupertinoModalPopup` / `CupertinoPicker` | 保留（或用 `ShadSelect` / `ShadSheet` 替换自研 `AppPickerField`） |
| `CupertinoSlidingSegmentedControl` | 保留（或用 `ShadTabs` 替换 `_ThemeModeSetting`） |

### 5.4 迁移顺序（混合模式，P0 → P1 → P2）

1. **P0 依赖与主题**：`flutter pub add shadcn_ui`（已完成 0.56.1）；`app.dart` 根改为 `ShadApp.custom + CupertinoApp + ShadAppBuilder`（`themeMode` 转 Material `ThemeMode`）；在 `app_theme.dart` 新增 `Static ShadThemeData AppTheme.shadThemeData(AppColors c)` 将 `AppColors` 映射到 `ShadColorScheme`（植物绿主/暖橙 secondary/天蓝 tertiary→custom）+ `ShadTextTheme` + 组价主题（按钮/卡片大圆角、无阴影）。保留 `colorsOf/textOf/isDarkOf` 与 `cupertinoLight/Dark`。（注：0.56.1 **无 `ShadSkeleton`**，骨架需自研 shimmer。）
2. **P0 共享组件**：`AppCard`→`ShadCard`、`AppPrimaryButton`→`ShadButton`(loading=禁用+spinner)、`AppProgressBar`→`ShadProgress`、`AppTags/AppBadge`→`ShadBadge`(.primary/.secondary/.outline/.destructive)、`AppTextField`→`ShadInput`、`AppPickerField`→`ShadSelect`/`ShadSheet`、`AppError`→`ShadAlert`+`ShadButton`、`AppToast`→`ShadSonner`/`ShadToast`。保留类名与参数（`AppTextField/AppPickerField`）以少改上层。
3. **P1 页面级组件**：`_TaskCard / _StatCard / _MasteryBar / _OptionTile / _ReviewBanner / _TutorBanner / _SubjectToggle / _ParentWrongCard / _TutorLogCard / _WrongQuestionCard` 落到 Shad 基件组合；移动 `AppTags/AppBadge/AvatarSquircle` 图标到 `LucideIcons`（沙 kn 依赖 lucide_icons_flutter 3.1.17）。
4. **P2 chrome 与动画**：Cupertino 导航/TabBar/Picker/刷新/滑动分段全部保留；`PopIn/PressScale/ConfettiBurst` 保留；图标可从 `CupertinoIcons` 逐步换 `LucideIcons`（可选）。移除 `cupertino_ui` 依赖。
5. 全程 `flutter analyze --no-pub` 校验零告警。

---

## 6. 汇总

- **第三方主导（当前）**：`cupertino_ui`（唯一 UI 包），覆盖全部 iOS 原生 chrome + 图标 + 系统控件；迁入后将新增主导 `shadcn_ui`（0.56.1，含 lucide_icons/flutter_animate/boxy/universal_image 等传递依赖），`cupertino_ui` 移除。
- **自研主导模式**：以「语义化 Chip（AppTags/AppBadge）+ 扁平卡片（AppCard）+ 表单（AppTextField/AppPickerField）+ 状态（AppLoading/AppError/AppToast）+ 动画（PopIn/PressScale/ConfettiBurst）+ 主题令牌」为核心的高复用设计系统，逐一映射到 `shadcn_ui` 组件。
- **迁移影响面**：约 10 个 Screen + 1 个共享组件库 + 1 套主题令牌；导航/TabBar/Picker/下拉刷新归 Shadcn 缺口，**保留 Cupertino**，因此为「Shad + Cupertino 混合」而非纯 Shad 全量迁移。