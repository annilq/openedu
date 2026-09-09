/// 设计系统收敛 A/B/C/D 运行时预览（DEV ONLY，不参与 App 主流程）。
///
/// 运行方式（桌面有真实鼠标，可验证 hover）：
/// ```sh
/// flutter run -d macos -t lib/dev/theme_preview.dart
/// # 或 web：flutter run -d chrome -t lib/dev/theme_preview.dart
/// ```
///
/// 覆盖四项收敛：
/// - **A** 统一交互主色：开关 / 勾选 / 单选选中态与 CTA 主按钮统一走「靛蓝 accent」，
///   与 focus ring / selection / progress 同色；primary 保留中性近黑（强调/状态/图标）。
/// - **B** 修复 `secondary` 名实不符：secondary 按钮 / badge 由琥珀（像 warning）
///   改为中性灰 + 1px 描边 + hover 反馈。
/// - **C** 标签 hover 克制版：hover 由「填实饱和色 + 反色字」改为「同色微深 + 前景不变」。
/// - **D** 排版单一事实源：`AppText` 与 shadcn `ShadTextTheme` 共用
///   `AppText._typeScale`，字号 / 字重 / 行高逐项一致（含 Child Mode 同步放大）。
/// - **E** 边框可见性 + 三灰分工：outline 提到可见但仍克制的发丝值；
///   描边令牌收敛为一个 outline（卡片/输入/分隔线同档），surface 色调走 surface* 家族；
///   可点击 `AppCard` hover 时边框微深到 outlineHover（激活此前死令牌）。
/// - **F** 语义色 / 学科色 / shadcn 映射契约：`AppColors` 为唯一事实源，
///   单向映射到 `ShadColorScheme`（含 `custom` 语义键与学科色）；逐项核对
///   映射是否与令牌一致，并展示接管后的 shadcn 组件（描边 + hover/press 分级）。
library;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalMaterialLocalizations;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/app_chip.dart';
import '../shared/widgets/app_inputs.dart';

void main() => runApp(const ThemePreviewApp());

class ThemePreviewApp extends StatefulWidget {
  const ThemePreviewApp({super.key});

  @override
  State<ThemePreviewApp> createState() => _ThemePreviewAppState();
}

class _ThemePreviewAppState extends State<ThemePreviewApp> {
  bool _dark = false;
  AppUserMode _mode = AppUserMode.parent;
  AppDensity _density = AppControl.defaultDensity;

  @override
  Widget build(BuildContext context) {
    final active = _dark ? AppTheme.dark : AppTheme.light;
    return ShadApp.custom(
      // 密度进了主题层：shadcn 组件高度随「模式 × 密度」重建，与 App* 组件同源。
      theme: AppTheme.shadFor(false, _mode, _density),
      darkTheme: AppTheme.shadFor(true, _mode, _density),
      themeMode: appThemeModeToMaterial(
          _dark ? AppThemeMode.dark : AppThemeMode.light),
      appBuilder: (context) => CupertinoApp(
        title: '设计令牌收敛预览',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.cupertinoFor(_dark),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: [
          GlobalShadLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          ...GlobalCupertinoLocalizations.delegates,
        ],
        builder: (context, child) => ShadAppBuilder(
          backgroundColor: active.surface,
          child: DensityScope(
            density: _density,
            child: UserModeScope(
              mode: _mode,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  platformBrightness: _dark ? Brightness.dark : Brightness.light,
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        home: _PreviewHome(
          dark: _dark,
          mode: _mode,
          density: _density,
          onToggleDark: () => setState(() => _dark = !_dark),
          onToggleMode: () => setState(() => _mode = _mode == AppUserMode.parent
              ? AppUserMode.child
              : AppUserMode.parent),
          onToggleDensity: () => setState(() => _density =
              _density == AppDensity.compact ? AppDensity.normal : AppDensity.compact),
        ),
      ),
    );
  }
}

// =====================================================================
// 预览主页
// =====================================================================

class _PreviewHome extends StatefulWidget {
  final bool dark;
  final AppUserMode mode;
  final AppDensity density;
  final VoidCallback onToggleDark;
  final VoidCallback onToggleMode;
  final VoidCallback onToggleDensity;

  const _PreviewHome({
    required this.dark,
    required this.mode,
    required this.density,
    required this.onToggleDark,
    required this.onToggleMode,
    required this.onToggleDensity,
  });

  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  final _fieldCtrl = TextEditingController();

  @override
  void dispose() {
    _fieldCtrl.dispose();
    super.dispose();
  }

  // A 区交互控件状态
  bool _switchOld = true;
  bool _switchNew = true;
  bool _checkOld = true;
  bool _checkNew = true;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final t = AppTheme.textOf(context);

    return ColoredBox(
      color: app.surface,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl2),
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(app, t),
                const SizedBox(height: AppSpacing.xxl),
                _sectionA(app, t),
                const SizedBox(height: AppSpacing.lg),
                _sectionB(app, t),
                const SizedBox(height: AppSpacing.lg),
                _sectionC(app, t),
                const SizedBox(height: AppSpacing.lg),
                _sectionD(app, t),
                const SizedBox(height: AppSpacing.lg),
                _sectionE(app, t),
                const SizedBox(height: AppSpacing.lg),
                _sectionControl(app, t),
                const SizedBox(height: AppSpacing.lg),
                _sectionF(app, t),
                const SizedBox(height: AppSpacing.xl2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- 顶部工具栏 ----------------

  Widget _header(AppColors app, AppText t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设计令牌收敛预览', style: t.displayLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'A 统一交互主色 · B 修复 secondary · C 标签 hover 克制版 · D 排版单一事实源 · '
          'E 描边归一 · 控件高度（密度感知） · F 语义色/学科色映射'
          '　—　把鼠标移到标签 / 按钮上验证 hover；切 Normal/Compact 看控件高度联动',
          style: t.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: widget.onToggleDark,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.dark ? LucideIcons.moon : LucideIcons.sun,
                    size: 14,
                    color: app.onSurface,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    widget.dark ? '暗色模式' : '亮色模式',
                    style: t.labelMedium?.copyWith(color: app.onSurface),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: widget.onToggleMode,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.mode == AppUserMode.child
                        ? LucideIcons.baby
                        : LucideIcons.userCog,
                    size: 14,
                    color: app.onSurface,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    widget.mode == AppUserMode.child
                        ? 'Child Mode（放大一档）'
                        : 'Parent Mode（密排）',
                    style: t.labelMedium?.copyWith(color: app.onSurface),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: widget.onToggleDensity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.density == AppDensity.compact
                        ? LucideIcons.alignVerticalJustifyEnd
                        : LucideIcons.alignVerticalJustifyStart,
                    size: 14,
                    color: app.onSurface,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    widget.density == AppDensity.compact
                        ? 'Compact（紧凑）'
                        : 'Normal（常规）',
                    style: t.labelMedium?.copyWith(color: app.onSurface),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------- A 统一交互主色 ----------------

  Widget _sectionA(AppColors app, AppText t) {
    return _Section(
      tag: 'A',
      title: '统一交互主色：选中态 → 靛蓝 accent',
      desc: '改前 shadcn primary 接的是近黑 #1D1B17，开关/勾选/单选选中态渲染近黑，'
          '而 focus ring / selection / progress 却是靛蓝 → 交互主色分裂。'
          '改后交互态与 CTA 主按钮统一走 accent 靛蓝，primary 保留中性近黑（强调/状态/图标）。',
      body: _Compare(
        before: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShadSwitch(
              value: _switchOld,
              onChanged: (v) => setState(() => _switchOld = v),
              checkedTrackColor: Color(0xFF1D1B17),
              thumbColor: app.onPrimary,
              label: Text('按兴趣出题', style: t.bodyMedium),
            ),
            const SizedBox(height: AppSpacing.md),
            ShadCheckbox(
              value: _checkOld,
              onChanged: (v) => setState(() => _checkOld = v),
              color: app.primary,
              uncheckedColor: app.outline,
              label: Text('加入错题本', style: t.bodyMedium),
            ),
            const SizedBox(height: AppSpacing.md),
            ShadRadioGroup<String>(
              initialValue: 'auto',
              items: [
                ShadRadio(
                  value: 'auto',
                  color: app.primary,
                  label: Text('自动判分', style: t.bodyMedium),
                ),
                ShadRadio(
                  value: 'manual',
                  color: app.primary,
                  label: Text('人工批改', style: t.bodyMedium),
                ),
              ],
            ),
          ],
        ),
        after: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 不传颜色 → 走主题（switchTheme/checkboxTheme/radioTheme = accent）
            ShadSwitch(
              value: _switchNew,
              onChanged: (v) => setState(() => _switchNew = v),
              label: Text('按兴趣出题', style: t.bodyMedium),
            ),
            const SizedBox(height: AppSpacing.md),
            ShadCheckbox(
              value: _checkNew,
              onChanged: (v) => setState(() => _checkNew = v),
              label: Text('加入错题本', style: t.bodyMedium),
            ),
            const SizedBox(height: AppSpacing.md),
            ShadRadioGroup<String>(
              initialValue: 'auto',
              items: [
                ShadRadio(value: 'auto', label: Text('自动判分', style: t.bodyMedium)),
                ShadRadio(
                    value: 'manual', label: Text('人工批改', style: t.bodyMedium)),
              ],
            ),
          ],
        ),
      ),
      footer: Row(
        children: [
          _Swatch(color: app.cta, label: 'cta 靛蓝（主按钮）'),
          const SizedBox(width: AppSpacing.lg),
          _Swatch(color: app.primary, label: 'primary 近黑（中性）'),
          const SizedBox(width: AppSpacing.lg),
          _Swatch(color: app.accent, label: 'accent 靛蓝（交互态）'),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: AppProgressBar(value: 0.62),
          ),
        ],
      ),
    );
  }

  // ---------------- B 修复 secondary ----------------

  Widget _sectionB(AppColors app, AppText t) {
    return _Section(
      tag: 'B',
      title: 'secondary 去琥珀：不再"像 warning"',
      desc: '改前 shadcn secondary 接的是 secondaryContainer #FAF3E8（琥珀=warning 底），'
          '于是次级按钮看起来像警告，且 hover 无反馈（hover 色=底色）。'
          '改后走中性 surfaceContainerHigh + 1px outline 描边，并补了 hover。',
      body: _Compare(
        before: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShadButton.secondary(
              size: ShadButtonSize.sm,
              backgroundColor: app.secondaryContainer,
              foregroundColor: app.onSecondaryContainer,
              hoverBackgroundColor: app.secondaryContainer, // 原状：hover 无变化
              onPressed: () {},
              child: Text(
                '稍后再说',
                style: t.labelMedium?.copyWith(color: app.onSecondaryContainer),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('↑ 琥珀底，易被读成 warning；hover 无反馈', style: t.bodySmall),
          ],
        ),
        after: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShadButton.secondary(
              size: ShadButtonSize.sm,
              onPressed: () {},
              child: Text(
                '稍后再说',
                style: t.labelMedium?.copyWith(color: app.onSurface),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('↑ 中性灰 + 1px 描边；hover 有 surfaceHover 反馈', style: t.bodySmall),
          ],
        ),
      ),
      footer: Row(
        children: [
          Text('同排对照（CTA / 次级 / 选择 chip）：', style: t.bodySmall),
          const SizedBox(width: AppSpacing.md),
          ShadButton(
            size: ShadButtonSize.sm,
            onPressed: () {},
            child: Text(
              '开始练习',
              style: t.labelMedium?.copyWith(color: app.onPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ShadButton.secondary(
            size: ShadButtonSize.sm,
            onPressed: () {},
            child: Text(
              '取消',
              style: t.labelMedium?.copyWith(color: app.onSurface),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const AppChip(label: '数学', selected: true),
          const SizedBox(width: AppSpacing.xs),
          const AppChip(label: '语文'),
        ],
      ),
    );
  }

  // ---------------- C 标签 hover 克制版 ----------------

  Widget _sectionC(AppColors app, AppText t) {
    return _Section(
      tag: 'C',
      title: '标签 hover 克制版：同色微深，前景不变',
      desc: '改前 hover 填实饱和色（淡染 → 实色绿/红/琥珀/靛蓝）并反色字，跳变过大，'
          '标签成了全站最吵的元素。改后只把底色压暗 8%（暗色模式提亮 10%），前景不动。'
          '把鼠标依次移过两行标签，对比跳变幅度。',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('改前（填实饱和色，hover 试试）', style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _LegacyPill(
                bg: app.surfaceContainerHigh,
                fg: app.onSurface,
                hoverBg: app.surfaceContainerHighest,
                label: '普通',
              ),
              _LegacyPill(
                bg: app.infoContainer,
                fg: app.onInfoContainer,
                hoverBg: app.accent,
                label: '待复习',
                icon: LucideIcons.info,
              ),
              _LegacyPill(
                bg: app.secondaryContainer,
                fg: app.onSecondaryContainer,
                hoverBg: app.secondary,
                label: 'AI 生成',
                icon: LucideIcons.sparkles,
              ),
              _LegacyPill(
                bg: app.tertiaryContainer,
                fg: app.onTertiaryContainer,
                hoverBg: app.tertiary,
                label: '已掌握',
                icon: LucideIcons.check,
              ),
              _LegacyPill(
                bg: app.errorContainer,
                fg: app.onErrorContainer,
                hoverBg: app.error,
                label: '错题',
                icon: LucideIcons.triangleAlert,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('改后（同色微深，hover 试试）', style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppTags.normal('普通'),
              AppTags.info('待复习', icon: LucideIcons.info),
              AppTags.ai('AI 生成', icon: LucideIcons.sparkles),
              AppTags.success('已掌握', icon: LucideIcons.check),
              AppTags.warning('错题', icon: LucideIcons.triangleAlert),
              AppTags.subject(SubjectKey.math),
              AppTags.subject(SubjectKey.chinese),
              AppTags.subject(SubjectKey.english),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('AppBadge 胶囊（同样克制 hover）', style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppBadge.successChip('全部答对'),
              AppBadge.warningChip('3 题待订正'),
              AppBadge.infoChip('今日新增 5 题'),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- D 排版单一事实源 ----------------

  Widget _sectionD(AppColors app, AppText t) {
    final st = ShadTheme.of(context).textTheme;
    final rows = <(String, TextStyle?, String, TextStyle?)>[
      ('h1Large', st.h1Large, 'displayLarge', t.displayLarge),
      ('h1', st.h1, 'displayMedium', t.displayMedium),
      ('h2', st.h2, 'headlineLarge', t.headlineLarge),
      ('h3', st.h3, 'headlineMedium', t.headlineMedium),
      ('h4', st.h4, 'headlineSmall', t.headlineSmall),
      ('large', st.large, 'titleLarge', t.titleLarge),
      ('p / list', st.p, 'bodyLarge', t.bodyLarge),
      ('table', st.table, 'labelMedium', t.labelMedium),
      ('lead', st.lead, 'headlineMedium', t.headlineMedium),
      ('small', st.small, 'labelSmall', t.labelSmall),
      ('muted', st.muted, 'bodySmall', t.bodySmall),
    ];

    String fmt(TextStyle? s) => s == null
        ? '—'
        : '${s.fontSize?.toStringAsFixed(0)}sp'
            ' / w${s.fontWeight?.value ?? 400}'
            ' / h${s.height?.toStringAsFixed(2)}';

    bool same(TextStyle? a, TextStyle? b) =>
        a?.fontSize == b?.fontSize &&
        a?.fontWeight == b?.fontWeight &&
        a?.height == b?.height;

    return _Section(
      tag: 'D',
      title: '排版单一事实源：shadcn 与 AppText 逐项一致',
      desc: '改前 AppText 与 ShadTextTheme 各写一套尺寸/字重/tracking，'
          '同屏混用即漂移。改后二者都从 AppText._typeScale 取数——'
          '下表每行左右应完全相同（含 Child Mode 同步放大，可用顶部按钮切换验证）。',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _typeRow(app, t, 'shadcn 令牌', 'ShadTextTheme 实际值', 'AppText 令牌',
              'AppText 实际值', null,
              header: true),
          ...rows.map((r) {
            final (shadName, shadStyle, appName, appStyle) = r;
            return _typeRow(app, t, shadName, fmt(shadStyle), appName,
                fmt(appStyle), same(shadStyle, appStyle));
          }),
          const SizedBox(height: AppSpacing.xl),
          Text('实际渲染阶梯（当前模式）', style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Text('displayLarge 22/26', style: t.displayLarge),
          Text('headlineLarge 18/21', style: t.headlineLarge),
          Text('titleMedium 15/17', style: t.titleMedium),
          Text('bodyLarge 15/17 —— 正文基线，密排 15sp（Child 17sp）', style: t.bodyLarge),
          Text('bodySmall 13/14 —— 次要说明', style: t.bodySmall),
        ],
      ),
    );
  }

  // ---------------- E 边框可见性 + 三灰分工 ----------------

  Widget _sectionE(AppColors app, AppText t) {
    final oldOutline = const Color(0xFFECECEA); // 改前：近乎不可见
    Row sw(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: app.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: c, width: 1),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: t.bodySmall),
          ],
        );
    return _Section(
      tag: 'E',
      title: '描边只有一档：outline',
      desc: '改前 outline #ECECEA（~1.18:1）在白卡上近乎不可见，"1px 描边分层"失效；'
          '改后提到 #DEDDD8（~1.36:1），可见但仍克制。**描边令牌收敛为一个 outline**——'
          '卡片边框、输入边框、分隔线全部同档（不再有更淡的 outlineVariant），'
          'surface 色调走 surfaceSunken 等面令牌（面不是线，禁止当描边用）。'
          '可点击卡片 hover 时边框微深到 outlineHover（左下角卡片，移上去看）。',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Compare(
            before: AppCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              border: Border.all(color: oldOutline, width: 1),
              child: Text('改前卡片（边框 #ECECEA，几乎看不见）', style: t.bodyMedium),
            ),
            after: AppCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('改后卡片（边框 #DEDDD8，清晰但克制）', style: t.bodyMedium),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('线与面各一档（禁止互串）', style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: [
              sw(app.outline, 'outline 线 #DEDDD8'),
              sw(app.surfaceSunken, 'surfaceSunken 面 #F4F4F2'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('↑ 线只有 outline 一档，面走 surface 家族（亮模式）',
              style: t.bodySmall),
          const SizedBox(height: AppSpacing.xl),
          Text('分隔线示例（与卡片边框同色同档）', style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Container(
            height: 1,
            color: app.outline,
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          ),
          Text('↑ 分隔线与卡片边框同为 outline，不再有更淡的一档', style: t.bodySmall),
          const SizedBox(height: AppSpacing.xl),
          Text('可点击卡片 hover（移上去看边框微深到 outlineHover）', style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            onTap: () {},
            child: Row(
              children: [
                Icon(LucideIcons.mousePointerClick, size: 14, color: app.accent),
                const SizedBox(width: AppSpacing.sm),
                Text('点我 / 悬停我（hover 边框加深）', style: t.bodyMedium),
                const Spacer(),
                const Icon(LucideIcons.chevronRight, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- F 语义色 / 学科色 / shadcn 映射契约 ----------------

  // ---------------- 控件高度（密度感知，单一事实源）----------------

  static String _subjectName(SubjectKey k) => switch (k) {
        SubjectKey.math => 'Math',
        SubjectKey.chinese => 'Chinese',
        SubjectKey.english => 'English',
        SubjectKey.reserved => 'Reserved',
      };

  Widget _sectionControl(AppColors app, AppText t) {
    final h = AppControl.heightOf(context);
    final hSm = AppControl.heightSmOf(context);
    return _Section(
      tag: '控件高度',
      title: '控件高度 · 密度感知令牌',
      desc: '输入框 / 按钮 / 选择器共用同一高度，由 `AppControl` 按「用户模式 × 密度」'
          '从间距令牌推导，无硬编码。顶部切 Parent/Child 与 Normal/Compact 看高度联动；'
          '下方输入框与按钮渲染高度严格相等（用尺子/对齐印证）。',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: '输入框',
                  controller: _fieldCtrl,
                  hintText: '高度 = 控件高度令牌',
                  prefixIcon: LucideIcons.textCursorInput,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppPrimaryButton(
                label: '主按钮',
                onPressed: () {},
                fullWidth: false,
              ),
              const SizedBox(width: AppSpacing.sm),
              ShadButton.outline(
                height: hSm,
                onPressed: () {},
                child: const Text('紧凑按钮'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            '当前解析高度：主控件 ${h.toStringAsFixed(0)}px · 紧凑控件 ${hSm.toStringAsFixed(0)}px'
            '（parent/compact=32·28【默认】，parent/normal=40·32，'
            'child/compact=40·32，child/normal=48·40）',
            style: t.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '所有取值来自 AppSpacing 令牌（xl2=28 / xl3=32 / xl4=40 / xl5=48），无魔法数字。',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _sectionF(AppColors app, AppText t) {
    final theme = ShadTheme.of(context);
    final cs = theme.colorScheme;
    // 主题层无 context：控件高度按「当前用户模式 × 当前密度」推导，
    // 与 shadThemeData() 内部取值同源（密度已全局接入，随顶部开关联动）。
    final controlH = AppControl.height(widget.mode, widget.density);

    String hex(Color? c) => c == null
        ? '—'
        : '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

    bool all(List<bool> xs) => xs.every((e) => e);

    // 同类色合并成一行核对：不再逐令牌罗列（颜色太多看不出问题）。
    final checks = <(String, bool, String)>[
      (
        'card / popover（浮起面）',
        cs.card == app.surfaceRaised && cs.popover == app.surfaceRaised,
        hex(cs.card)
      ),
      (
        'border / input / separator（描边同档）',
        cs.border == app.outline &&
            cs.input == app.outline &&
            theme.separatorTheme.color == app.outline,
        hex(cs.border)
      ),
      (
        'ring / selection / progress（靛蓝 accent）',
        cs.ring == app.accent &&
            cs.selection == app.accent &&
            theme.progressTheme.color == app.accent,
        hex(cs.ring)
      ),
      (
        'accent（shadcn=hover 灰，非靛蓝）',
        cs.accent == app.surfaceSunken,
        hex(cs.accent)
      ),
      (
        'custom 语义四档（positive/warning/error/info）',
        all([
          cs.custom['semanticPositive'] == app.semanticPositive,
          cs.custom['semanticWarning'] == app.semanticWarning,
          cs.custom['semanticError'] == app.semanticError,
          cs.custom['semanticInfo'] == app.semanticInfo,
        ]),
        '4/4'
      ),
      (
        'custom 学科三件套（math/chinese/english）',
        all([
          for (final k in SubjectKey.values)
            ...[
              cs.custom['subject${_subjectName(k)}'] ==
                  SubjectAccent.forContext(k, context).accent,
              cs.custom['subject${_subjectName(k)}Container'] ==
                  SubjectAccent.forContext(k, context).container,
              cs.custom['subject${_subjectName(k)}Fg'] ==
                  SubjectAccent.forContext(k, context).fg,
            ],
        ]),
        '12/12'
      ),
      (
        'custom ctaHover / toast',
        cs.custom['ctaHover'] == app.ctaHover && cs.custom['toast'] == app.toast,
        hex(cs.custom['ctaHover'])
      ),
      (
        '输入框与按钮同高（AppControl：模式 × 密度）',
        theme.inputTheme.constraints?.minHeight == controlH &&
            theme.inputTheme.constraints?.maxHeight == controlH &&
            theme.buttonSizesTheme.regular?.height == controlH,
        '${controlH.toStringAsFixed(0)}px'
      ),
      (
        'tooltip 延迟 500ms',
        theme.tooltipTheme.waitDuration == const Duration(milliseconds: 500),
        '${theme.tooltipTheme.waitDuration?.inMilliseconds}ms'
      ),
    ];

    Widget row(String name, bool ok, String actual) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 300,
              child: Text(name, style: t.bodySmall),
            ),
            SizedBox(
              width: 90,
              child: Text(
                actual,
                style: t.bodySmall?.copyWith(
                  color: ok ? null : app.semanticErrorFg,
                ),
              ),
            ),
            Icon(
              ok ? LucideIcons.check : LucideIcons.x,
              size: 13,
              color: ok ? app.semanticPositiveFg : app.semanticErrorFg,
            ),
          ],
        ),
      );
    }

    Widget swatch(String label, Color bg, Color fg) => Container(
          margin: const EdgeInsets.only(right: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Text(
            label,
            style: t.labelSmall?.copyWith(color: fg),
          ),
        );

    return _Section(
      tag: 'F',
      title: '语义色 / 学科色 / shadcn 映射契约',
      desc: '设计系统令牌 → shadcn 主题单向映射：AppColors 是唯一事实源，'
          'ShadColorScheme 只是消费方。同类色合并核对，任一行出现 ✗ 即说明主题层与令牌脱节。'
          '语义色只有四档（AI 归 info），学科色是业务标识色（ADR-0014），均已注入 custom。',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('语义色四档（AI 归 info，不再新增重复琥珀）', style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            children: [
              swatch('positive', app.semanticPositive, app.semanticPositiveFg),
              swatch('warning', app.semanticWarning, app.semanticWarningFg),
              swatch('error', app.semanticError, app.semanticErrorFg),
              swatch('info / ai', app.semanticInfo, app.semanticInfoFg),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('学科色（小面积使用）', style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              AppTags.subject(SubjectKey.math),
              AppTags.subject(SubjectKey.chinese),
              AppTags.subject(SubjectKey.english),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('映射核对（实际值 vs 令牌）', style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          ...checks.map((c) => row(c.$1, c.$2, c.$3)),
          const SizedBox(height: AppSpacing.lg),
          Text('接管后的 shadcn 组件（描边 + hover/press 分级 + 与按钮同高）',
              style: t.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ShadButton(
                onPressed: () {},
                child: Text(
                  'CTA（hover 提亮一档）',
                  style: t.labelMedium?.copyWith(color: app.onCta),
                ),
              ),
              ShadButton.outline(
                onPressed: () {},
                child: Text(
                  'Outline（hover→press）',
                  style: t.labelMedium?.copyWith(color: app.onSurface),
                ),
              ),
              SizedBox(
                width: 200,
                child: ShadInput(
                  placeholder:
                      Text('输入框：focus 边框转靛蓝', style: t.bodySmall),
                  // shadcn 的 EditableText 默认 textAlignVertical=top（文字偏上），
                  // 用 forceStrutHeight 把行高撑满编辑盒（controlH - 4）使字形居中。
                  strutStyle:
                      AppControl.inputStrut(context, t.bodySmall),
                  constraints: AppControl.inputConstraintsOf(context),
                ),
              ),
              SizedBox(
                width: 160,
                child: ShadProgress(
                  value: 0.62,
                  color: app.accent,
                  backgroundColor: app.surfaceActive,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeRow(
    AppColors app,
    AppText t,
    String c1,
    String c2,
    String c3,
    String c4,
    bool? ok, {
    bool header = false,
  }) {
    final style = header
        ? t.labelMedium?.copyWith(color: app.onSurfaceVariant)
        : t.bodySmall?.copyWith(color: app.onSurface);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: app.outline, width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(c1, style: style)),
          SizedBox(width: 190, child: Text(c2, style: style)),
          SizedBox(width: 130, child: Text(c3, style: style)),
          SizedBox(width: 190, child: Text(c4, style: style)),
          if (ok != null)
            Icon(
              ok ? LucideIcons.check : LucideIcons.x,
              size: 14,
              color: ok ? app.tertiary : app.error,
            ),
        ],
      ),
    );
  }
}

// =====================================================================
// 预览用小组件
// =====================================================================

/// 分区容器：标签 + 标题 + 说明 + 内容 + 可选页脚。
class _Section extends StatelessWidget {
  final String tag;
  final String title;
  final String desc;
  final Widget body;
  final Widget? footer;

  const _Section({
    required this.tag,
    required this.title,
    required this.desc,
    required this.body,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final t = AppTheme.textOf(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: app.accent,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  tag,
                  style: t.labelSmall?.copyWith(color: app.onAccent),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(title, style: t.headlineSmall)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(desc, style: t.bodySmall),
          const SizedBox(height: AppSpacing.xl),
          body,
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: app.outline, width: 1)),
              ),
              child: footer,
            ),
          ],
        ],
      ),
    );
  }
}

/// 改前 / 改后并列对比。
class _Compare extends StatelessWidget {
  final Widget before;
  final Widget after;

  const _Compare({required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final t = AppTheme.textOf(context);

    Widget col(String label, Color dot, Widget body) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: app.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: app.outline, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dot,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(label,
                        style:
                            t.labelSmall?.copyWith(color: app.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                body,
              ],
            ),
          ),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        col('改前', app.error, before),
        const SizedBox(width: AppSpacing.lg),
        col('改后', app.tertiary, after),
      ],
    );
  }
}

/// 色板小样。
class _Swatch extends StatelessWidget {
  final Color color;
  final String label;

  const _Swatch({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final t = AppTheme.textOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(color: app.outline, width: 1),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: t.bodySmall),
      ],
    );
  }
}

/// 改前行为复刻：hover 填实饱和色 + 前景按亮度反色（仅用于对比展示）。
class _LegacyPill extends StatefulWidget {
  final Color bg;
  final Color fg;
  final Color hoverBg;
  final String label;
  final IconData? icon;

  const _LegacyPill({
    required this.bg,
    required this.fg,
    required this.hoverBg,
    required this.label,
    this.icon,
  });

  @override
  State<_LegacyPill> createState() => _LegacyPillState();
}

class _LegacyPillState extends State<_LegacyPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.textOf(context);
    final bg = _hovered ? widget.hoverBg : widget.bg;
    // 改前逻辑：hover 时前景按背景亮度反色（黑或白）。
    final fg = _hovered
        ? (widget.hoverBg.computeLuminance() > 0.5
            ? const Color(0xFF000000)
            : const Color(0xFFFFFFFF))
        : widget.fg;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 13, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              widget.label,
              style: (t.labelSmall ?? const TextStyle())
                  .copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
