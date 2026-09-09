import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shadcn_ui/shadcn_ui.dart';

/// 按正确率分级的视觉情绪。
enum ResultTone { positive, warm, alert, neutral }

/// 应用主题模式。
enum AppThemeMode { system, light, dark }

Brightness resolveBrightness(AppThemeMode mode, Brightness systemBrightness) {
  return switch (mode) {
    AppThemeMode.system => systemBrightness,
    AppThemeMode.light => Brightness.light,
    AppThemeMode.dark => Brightness.dark,
  };
}

ThemeMode appThemeModeToMaterial(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };

/// 用户模式（双模式，ADR-0014）：家长工作台 / 娃娃学习台。
///
/// 独立于亮暗主题（[AppThemeMode]），控制字号阶梯与语气。
/// 家长端 = 密排专业；娃娃端 = 更大字号 + 学科色 + 适度趣味。
enum AppUserMode { parent, child }

/// 学科色（ADR-0014 Subject Accent Tokens）。
///
/// 在中性 + 靛蓝基底上叠加，中饱和，**仅小面积使用**（学科标识 / 进度条 /
/// 图标容器 / 小面积 chip）。`reserved` 为未来学科（科学 / 历史…）预留槽。
enum SubjectKey { math, chinese, english, reserved }

/// 学科色三件套：强调色 / 容器底 / 前景文字。
class SubjectColors {
  final Color accent;
  final Color container;
  final Color fg;
  const SubjectColors(this.accent, this.container, this.fg);
}

/// 学科色令牌解析（亮 / 暗各一套，与 [AppColors] 同源管理）。
class SubjectAccent {
  const SubjectAccent._();

  static const SubjectColors _lightMath =
      SubjectColors(Color(0xFF4C7DE0), Color(0xFFE9F0FC), Color(0xFF2B5BB0));
  static const SubjectColors _lightChinese =
      SubjectColors(Color(0xFFD85A6E), Color(0xFFFCEBEE), Color(0xFFB23A4E));
  static const SubjectColors _lightEnglish =
      SubjectColors(Color(0xFF3FA67E), Color(0xFFE7F5EE), Color(0xFF2C7C5C));
  static const SubjectColors _lightReserved =
      SubjectColors(Color(0xFF8A8F98), Color(0xFFF1F1F0), Color(0xFF5C6068));

  static const SubjectColors _darkMath =
      SubjectColors(Color(0xFF7FA8F0), Color(0xFF1B2740), Color(0xFFA9C4F5));
  static const SubjectColors _darkChinese =
      SubjectColors(Color(0xFFE78FA0), Color(0xFF3A1F26), Color(0xFFF2B6C2));
  static const SubjectColors _darkEnglish =
      SubjectColors(Color(0xFF6FC4A2), Color(0xFF163026), Color(0xFFA7E0C6));
  static const SubjectColors _darkReserved =
      SubjectColors(Color(0xFF9CA3AF), Color(0xFF2A2A28), Color(0xFFC7CBD1));

  /// 按学科 + 亮暗解析三件套。
  static SubjectColors resolve(SubjectKey key, {required bool isDark}) {
    switch (key) {
      case SubjectKey.math:
        return isDark ? _darkMath : _lightMath;
      case SubjectKey.chinese:
        return isDark ? _darkChinese : _lightChinese;
      case SubjectKey.english:
        return isDark ? _darkEnglish : _lightEnglish;
      case SubjectKey.reserved:
        return isDark ? _darkReserved : _lightReserved;
    }
  }

  /// 按当前 context 的亮暗解析。
  static SubjectColors forContext(SubjectKey key, BuildContext context) =>
      resolve(key, isDark: AppTheme.isDarkOf(context));

  /// 学科中文名。
  static String label(SubjectKey key) => switch (key) {
        SubjectKey.math => '数学',
        SubjectKey.chinese => '语文',
        SubjectKey.english => '英语',
        SubjectKey.reserved => '其它',
      };

  /// 由领域字符串（如 '数学' / 'math'）映射到学科键，未知归 reserved。
  static SubjectKey fromName(String? name) {
    switch (name?.trim()) {
      case '数学':
      case 'math':
      case 'Math':
        return SubjectKey.math;
      case '语文':
      case 'chinese':
      case 'Chinese':
        return SubjectKey.chinese;
      case '英语':
      case 'english':
      case 'English':
        return SubjectKey.english;
      default:
        return SubjectKey.reserved;
    }
  }
}

/// Linear 风格主题（亮色 + 暗色 · 中性灰白 + 靛蓝强调）。
///
/// 设计约定（见 .impeccable.md / ADR-0003）：
/// - surface 微暖白、卡片纯白 + 1px 极细描边、无阴影
/// - accent 靛蓝用于 selection/focus/progress/link/CTA（primary = accent 品牌主色）
/// - 语义色降饱和（极淡绿/琥珀/红/靛蓝底）
/// - Inter 西文/数字 + Noto Sans SC（OFL）CJK 回退（HarmonyOS Sans SC 因授权限制再分发，未打包）
/// - 密排字号 15sp 基线，双端共用
class AppTheme {
  const AppTheme._();

  /// Inter 为西文/数字主字体；CJK 回退到打包进工程的 Noto Sans SC
  ///（SIL OFL 变量字体，含字重轴，assets/fonts/NotoSansSC.ttf，pubspec.yaml 已声明）。
  /// 设计规范原列 HarmonyOS Sans SC，但其授权限制再分发，故改用可自由内嵌的 Noto Sans SC。
  static const String fontFamily = 'Inter';
  static const List<String> fontFamilyFallback = [
    'Noto Sans SC',
  ];

  /// 亮色令牌（中性灰白 + 靛蓝）。
  static const AppColors light = AppColors(
    brightness: Brightness.light,
    // CTA / 品牌主色：复用靛蓝 accent（全站品牌色统一为蓝紫）
    primary: Color(0xFF5E6AD2), // = accent 靛蓝
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEAF0FE), // 浅靛蓝容器（头像底 / 选中底）
    onPrimaryContainer: Color(0xFF4338CA), // 深靛蓝（容器前景）
    // 中性灰次强调
    secondary: Color(0xFF6B7280),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFAF3E8), // = semanticWarning 底
    onSecondaryContainer: Color(0xFF8A6D1F), // = semanticWarningFg
    // positive 语义
    tertiary: Color(0xFF3B7A2D),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFEFF5EC), // = semanticPositive 底
    onTertiaryContainer: Color(0xFF3B7A2D), // = semanticPositiveFg
    // error 语义
    error: Color(0xFFB91C1C),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFCE8E6), // = semanticError 底
    onErrorContainer: Color(0xFFB91C1C), // = semanticErrorFg
    // Surface 层次
    surface: Color(0xFFFBFAFA), // 内容区微暖白
    onSurface: Color(0xFF1D1B17),
    surfaceContainerLowest: Color(0xFFFFFFFF), // = surfaceRaised
    surfaceContainerLow: Color(0xFFFFFFFF), // = surfaceRaised（卡片）
    surfaceContainer: Color(0xFFF4F4F2), // = surfaceSunken（侧栏）
    surfaceContainerHigh: Color(0xFFF4F4F2), // = surfaceSunken（仅作 surface 色调，禁止当边框用）
    surfaceContainerHighest: Color(0xFFEDEDF0), // = surfaceActive
    onSurfaceVariant: Color(0xFF6B7280),
    outline: Color(0xFFDEDDD8), // 边框令牌（1px 描边）：亮模式 ~1.36:1，可见但克制
    inverseSurface: Color(0xFF1D1B17),
    onInverseSurface: Color(0xFFF5F5F4),
    // 靛蓝强调 + hover
    accent: Color(0xFF5E6AD2),
    onAccent: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFF4F4F2),
    outlineHover: Color(0xFFD1D1CE),
    // info 语义（靛蓝系）
    infoContainer: Color(0xFFEEF0FC), // = semanticInfo 底（AI 标记亦走此档）
    onInfoContainer: Color(0xFF4338CA), // = semanticInfoFg
    // CTA hover（靛蓝 CTA：hover 加深一档）
    ctaHover: Color(0xFF4F5AC4),
    // Toast 浮层（深色反色底，不用 surface 令牌以免与页面糊在一起）
    toast: Color(0xFF2F2A24),
    onToast: Color(0xFFFFFFFF),
    scrim: Color(0x66000000),
  );

  /// 暗色令牌（暖中性深炭 + 靛蓝提亮）。
  static const AppColors dark = AppColors(
    brightness: Brightness.dark,
    primary: Color(0xFF7B82EA), // 暗底品牌靛蓝
    onPrimary: Color(0xFF0F0F0E),
    primaryContainer: Color(0xFF20203A), // 深靛蓝容器（选中/头像底）
    onPrimaryContainer: Color(0xFFB9BEF2), // 浅靛蓝（容器前景）
    secondary: Color(0xFF9CA3AF),
    onSecondary: Color(0xFF0F0F0E),
    secondaryContainer: Color(0xFF2E2618), // = semanticWarning 底
    onSecondaryContainer: Color(0xFFD4A82E), // = semanticWarningFg
    tertiary: Color(0xFF86C060),
    onTertiary: Color(0xFF0F0F0E),
    tertiaryContainer: Color(0xFF1A2E1A), // = semanticPositive 底
    onTertiaryContainer: Color(0xFF86C060), // = semanticPositiveFg
    error: Color(0xFFF08888),
    onError: Color(0xFF0F0F0E),
    errorContainer: Color(0xFF2E1A1A), // = semanticError 底
    onErrorContainer: Color(0xFFF08888), // = semanticErrorFg
    surface: Color(0xFF0F0F0E), // 内容区暖中性深炭
    onSurface: Color(0xFFF5F5F4),
    surfaceContainerLowest: Color(0xFF161615),
    surfaceContainerLow: Color(0xFF161615), // = surfaceRaised
    surfaceContainer: Color(0xFF1A1A19), // = surfaceSunken
    surfaceContainerHigh: Color(0xFF1A1A19), // = surfaceSunken（仅作 surface 色调，禁止当边框用）
    surfaceContainerHighest: Color(0xFF2A2A28), // = surfaceActive
    onSurfaceVariant: Color(0xFF9CA3AF),
    outline: Color(0xFF2F2F2C), // 暗模式边框：~1.4:1 可见
    inverseSurface: Color(0xFFF5F5F4),
    onInverseSurface: Color(0xFF0F0F0E),
    accent: Color(0xFF7B82EA),
    onAccent: Color(0xFF0F0F0E),
    surfaceHover: Color(0xFF242423),
    outlineHover: Color(0xFF3D3D3A),
    infoContainer: Color(0xFF1A1A2E), // = semanticInfo 底（AI 标记亦走此档）
    onInfoContainer: Color(0xFF9BA0E8), // = semanticInfoFg
    ctaHover: Color(0xFFFFFFFF),
    toast: Color(0xFF242423),
    onToast: Color(0xFFF5F5F4),
    scrim: Color(0x66000000),
  );

  static bool isDarkOf(BuildContext context) {
    return CupertinoTheme.brightnessOf(context) == Brightness.dark;
  }

  static AppColors colorsOf(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return isDark ? dark : light;
  }

  static final AppText _lightText = AppText._build(light, child: false);
  static final AppText _darkText = AppText._build(dark, child: false);
  static final AppText _lightTextChild = AppText._build(light, child: true);
  static final AppText _darkTextChild = AppText._build(dark, child: true);

  /// 取当前用户模式的排版集合。
  ///
  /// 默认从 [UserModeScope] 读取（由 [userModeProvider] 驱动，全局自动重建）；
  /// 也可显式传 [mode] 覆盖（如测试或部分布局固定用家长尺度）。
  static AppText textOf(BuildContext context, {AppUserMode? mode}) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final m = mode ?? UserModeScope.of(context);
    if (isDark) {
      return m == AppUserMode.child ? _darkTextChild : _darkText;
    }
    return m == AppUserMode.child ? _lightTextChild : _lightText;
  }

  // ============ Cupertino 主题 ============

  static CupertinoThemeData get cupertinoLight => _cupertino(light);
  static CupertinoThemeData get cupertinoDark => _cupertino(dark);

  static CupertinoThemeData cupertinoFor(bool isDark) =>
      _cupertino(isDark ? dark : light);

  /// [density] 为全局控件密度（默认 [AppDensity.compact]，即 parent 32 / child 40）。
  /// 密度与亮暗、用户模式正交：三者共同决定 shadcn 组件主题里的控件高度，
  /// 使裸 `ShadButton` / `ShadInput` 与 `App*` 组件严格同高。
  static ShadThemeData shadFor(
    bool isDark, [
    AppUserMode mode = AppUserMode.parent,
    AppDensity density = AppDensity.compact,
  ]) =>
      shadThemeData(
        isDark ? dark : light,
        child: mode == AppUserMode.child,
        density: density,
      );

  static CupertinoThemeData _cupertino(AppColors c) {
    return CupertinoThemeData(
      brightness: c.brightness,
      primaryColor: c.accent,
      primaryContrastingColor: c.onAccent,
      barBackgroundColor: c.surface,
      scaffoldBackgroundColor: c.surface,
      textTheme: CupertinoTextThemeData(
        primaryColor: c.accent,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          color: c.onSurface,
        ),
      ),
    );
  }

  // ============ Shad Theme ============

  /// 设计系统令牌 → shadcn `custom` 色表。
  ///
  /// 命名以 `.impeccable.md` 的 public 令牌名为准（语义名优先），
  /// 旧的角色名 key（primaryContainer / secondaryContainer / tertiaryContainer /
  /// infoContainer…）一并保留做兼容，**新代码只用语义名**。
  static Map<String, Color> _customColors(AppColors c) {
    final isDark = c.brightness == Brightness.dark;
    final Map<String, Color> subject = {};
    for (final key in SubjectKey.values) {
      final sc = SubjectAccent.resolve(key, isDark: isDark);
      final name = switch (key) {
        SubjectKey.math => 'math',
        SubjectKey.chinese => 'chinese',
        SubjectKey.english => 'english',
        SubjectKey.reserved => 'reserved',
      };
      subject['subject${name[0].toUpperCase()}${name.substring(1)}'] =
          sc.accent;
      subject['subject${name[0].toUpperCase()}${name.substring(1)}Container'] =
          sc.container;
      subject['subject${name[0].toUpperCase()}${name.substring(1)}Fg'] = sc.fg;
    }
    return <String, Color>{
      // —— 强调（注意：ShadColorScheme.accent 是 shadcn 的 hover 高亮灰，
      //    不是设计系统 accent；靛蓝在这里，另见 ring / selection）——
      'accent': c.accent,
      'onAccent': c.onAccent,
      'cta': c.cta,
      'onCta': c.onCta,
      'ctaHover': c.ctaHover,
      // —— Surface 层次 ——
      'surfaceRaised': c.surfaceRaised,
      'surfaceSunken': c.surfaceSunken,
      'surfaceActive': c.surfaceActive,
      'surfaceHover': c.surfaceHover,
      'outlineHover': c.outlineHover,
      // —— 语义色（文档 public 令牌名）——
      'semanticPositive': c.semanticPositive,
      'semanticPositiveFg': c.semanticPositiveFg,
      'semanticWarning': c.semanticWarning,
      'semanticWarningFg': c.semanticWarningFg,
      'semanticError': c.semanticError,
      'semanticErrorFg': c.semanticErrorFg,
      'semanticInfo': c.semanticInfo,
      'semanticInfoFg': c.semanticInfoFg,
      // —— 浮层 ——
      'toast': c.toast,
      'onToast': c.onToast,
      'scrim': c.scrim,
      // —— 学科色（ADR-0014）——
      ...subject,
      // —— 旧角色名（兼容，新代码勿用）——
      'infoContainer': c.infoContainer,
      'onInfoContainer': c.onInfoContainer,
      'primaryContainer': c.primaryContainer,
      'onPrimaryContainer': c.onPrimaryContainer,
      'secondaryContainer': c.secondaryContainer,
      'onSecondaryContainer': c.onSecondaryContainer,
      'tertiaryContainer': c.tertiaryContainer,
      'onTertiaryContainer': c.onTertiaryContainer,
      'errorContainer': c.errorContainer,
      'onErrorContainer': c.onErrorContainer,
      'surfaceContainerLowest': c.surfaceContainerLowest,
      'surfaceContainer': c.surfaceContainer,
      'surfaceContainerHigh': c.surfaceContainerHigh,
      'surfaceContainerHighest': c.surfaceContainerHighest,
    };
  }

  /// 卡片 / 浮层 / 弹层通用装饰：surfaceRaised 底 + 1px outline 描边 + 无阴影。
  static ShadDecoration _surfaceDecoration(AppColors c, {double? radius}) =>
      ShadDecoration(
        color: c.surfaceRaised,
        border: ShadBorder.all(
          color: c.outline,
          width: 1,
          radius: BorderRadius.all(Radius.circular(radius ?? AppRadius.card)),
        ),
        shadows: const <BoxShadow>[],
      );

  static ShadThemeData shadThemeData(
    AppColors c, {
    required bool child,
    AppDensity density = AppDensity.compact,
  }) {
    // 交互控件（按钮 / 输入框 / 选择器）统一高度：主题层无 context，
    // 按「当前用户模式 × 全局密度」推导，与 AppControl.heightOf(context) 同源。
    // 密度由 [densityProvider] 驱动（默认 compact → parent 32 / child 40）。
    final mode = child ? AppUserMode.child : AppUserMode.parent;
    final controlH = AppControl.height(mode, density);
    final controlSmH = AppControl.heightSm(mode, density);
    final scheme = ShadColorScheme(
      background: c.surface,
      foreground: c.onSurface,
      card: c.surfaceRaised,
      cardForeground: c.onSurface,
      popover: c.surfaceRaised,
      popoverForeground: c.onSurface,
      primary: c.primary,
      primaryForeground: c.onPrimary,
      secondary: c.surfaceSunken,
      secondaryForeground: c.onSurface,
      muted: c.surfaceContainer,
      mutedForeground: c.onSurfaceVariant,
      // 陷阱提示：shadcn 的 `accent` 是「hover 高亮」语义（=我们的 surfaceSunken），
      // **不是**设计系统 accent 靛蓝。靛蓝走 `ring` / `selection` / custom['accent']。
      accent: c.surfaceSunken,
      accentForeground: c.onSurface,
      destructive: c.error,
      destructiveForeground: c.onError,
      border: c.outline,
      input: c.outline, // 描边只有一个令牌：outline（边框与分隔线同档）
      ring: c.accent,
      selection: c.accent,
      custom: _customColors(c),
    );

    const transparent = Color(0x00000000);

    // hover / press 分级（文档：hover surface 变色、press 再深一档）。
    // 实心按钮（CTA / destructive）底已是近黑或饱和色，hover 提亮/加深一档，
    // 绝不是「无反馈」——此前 hover=bg 等于把 hover 令牌废掉。
    ShadButtonTheme button(Color bg, Color fg, {Color? hover}) => ShadButtonTheme(
          backgroundColor: bg,
          foregroundColor: fg,
          hoverBackgroundColor: hover ?? bg,
          pressedBackgroundColor: hover ?? bg,
          pressedForegroundColor: fg,
          decoration: ShadDecoration(
            border: ShadBorder.all(
              color: bg,
              width: 0,
              radius: BorderRadius.all(Radius.circular(AppRadius.button)),
            ),
          ),
        );

    ShadBadgeTheme badge(Color bg, Color fg) => ShadBadgeTheme(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
          ),
        );

    return ShadThemeData(
      brightness: c.brightness,
      colorScheme: scheme,
      radius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
      textTheme: _shadTextTheme(c, child: child),
      disabledOpacity: 0.5,
      // 按钮尺寸走 AppControl 令牌：与输入框 / 选择器同高，
      // 避免 shadcn 默认 36px 与 App* 组件（compact 32 / normal 40）混排。
      buttonSizesTheme: ShadButtonSizesTheme(
        regular: ShadButtonSizeTheme(
          height: controlH,
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        sm: ShadButtonSizeTheme(
          height: controlSmH,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        lg: ShadButtonSizeTheme(
          height: controlH + AppSpacing.sm,
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        icon: ShadButtonSizeTheme(
          height: controlH,
          width: controlH,
          padding: EdgeInsets.zero,
        ),
      ),
      primaryButtonTheme: button(c.cta, c.onCta, hover: c.ctaHover),
      secondaryButtonTheme: ShadButtonTheme(
        backgroundColor: c.surfaceSunken,
        foregroundColor: c.onSurface,
        hoverBackgroundColor: c.surfaceHover,
        pressedBackgroundColor: c.surfaceActive,
        pressedForegroundColor: c.onSurface,
        decoration: ShadDecoration(
          border: ShadBorder.all(
            color: c.outline,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
        ),
      ),
      destructiveButtonTheme: button(c.error, c.onError),
      outlineButtonTheme: ShadButtonTheme(
        backgroundColor: transparent,
        foregroundColor: c.onSurface,
        hoverBackgroundColor: c.surfaceHover,
        pressedBackgroundColor: c.surfaceActive,
        decoration: ShadDecoration(
          border: ShadBorder.all(
            color: c.outline,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
        ),
      ),
      ghostButtonTheme: ShadButtonTheme(
        backgroundColor: transparent,
        foregroundColor: c.onSurface,
        hoverBackgroundColor: c.surfaceHover,
        pressedBackgroundColor: c.surfaceActive,
      ),
      linkButtonTheme: ShadButtonTheme(
        backgroundColor: transparent,
        foregroundColor: c.accent,
        textDecoration: TextDecoration.underline,
      ),
      primaryBadgeTheme: badge(c.semanticInfo, c.semanticInfoFg),
      secondaryBadgeTheme: badge(c.surfaceSunken, c.onSurface),
      destructiveBadgeTheme: badge(c.semanticError, c.semanticErrorFg),
      outlineBadgeTheme: ShadBadgeTheme(
        backgroundColor: transparent,
        foregroundColor: c.onSurface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.outline, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
      ),
      cardTheme: ShadCardTheme(
        backgroundColor: c.surfaceRaised,
        border: ShadBorder.all(color: c.outline, width: 1),
        radius: const BorderRadius.all(Radius.circular(AppRadius.card)),
        padding: const EdgeInsets.all(AppSpacing.md),
        shadows: const <BoxShadow>[],
      ),
      progressTheme: ShadProgressTheme(
        backgroundColor: c.surfaceActive,
        color: c.accent,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xs)),
        minHeight: 6,
      ),
      inputTheme: ShadInputTheme(
        // 竖向 padding 归零：高度由 tight 约束钉死，文字靠 crossAxisAlignment 居中。
        // 若这里给竖向 padding，ConstrainedBox 只会把「内容高」顶到约束之外，
        // 输入框又比按钮高出一截（32 → 34）。
        padding: AppControl.inputPadding,
        crossAxisAlignment: CrossAxisAlignment.center,
        alignment: Alignment.centerLeft,
        placeholderAlignment: Alignment.centerLeft,
        // 与按钮同高（单行至少 32）：用 minHeight 而非 tight——
        // tight 会把多行输入/带竖向 padding 的输入死钉 32，导致多行内容溢出、
        // 单行文字顶对齐不居中。minHeight 让多行按内容增高、单行仍落在 32。
        // 注意：单行文字垂直居中需在具体输入上用 editableTextSize 钉高（见 AppTextField）。
        constraints: BoxConstraints(minHeight: controlH),
        decoration: ShadDecoration(
          disableSecondaryBorder: true,
          color: c.surfaceRaised,
          border: ShadBorder.all(
            color: c.outline,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
          focusedBorder: ShadBorder.all(
            color: c.accent,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
        ),
        placeholderStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          fontSize: 15,
          color: c.onSurfaceVariant,
        ),
        cursorColor: c.accent,
      ),
      // 统一交互主色（A）：开关/勾选/单选选中态走靛蓝 accent，
      // 与 focus ring / selection / progress 同色；primary 现亦为靛蓝，
      // CTA 与全站品牌色（状态色/图标/光标）统一为蓝紫。
      switchTheme: ShadSwitchTheme(
        checkedTrackColor: c.accent,
        uncheckedTrackColor: c.surfaceSunken,
        thumbColor: c.onAccent,
      ),
      checkboxTheme: ShadCheckboxTheme(
        color: c.accent,
        uncheckedColor: c.outline,
      ),
      radioTheme: ShadRadioTheme(color: c.accent),
      // —— 浮层 / 弹层 / 表单接管 ——
      // 不接管这些主题时，shadcn 会退回内置 slate 配色 + 阴影，
      // 与「描边分层、无阴影、走令牌」的设计系统脱节（同一页面两套管语言）。
      // 接管后 Popover / Dialog / Select / Toast / Alert 与 AppCard 同构。
      // 无半透明 focus ring：focus 用 1px accent（各输入类组件已显式配
      // focusedBorder）表达。注意不要在全局 `decoration` 上挂 border——
      // 它会漏到 switch / checkbox 等无框控件上，凭空长出描边。
      disableSecondaryBorder: true,
      popoverTheme: ShadPopoverTheme(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: _surfaceDecoration(c, radius: AppRadius.card),
        shadows: const <BoxShadow>[],
      ),
      primaryDialogTheme: _dialogTheme(c),
      alertDialogTheme: _dialogTheme(c),
      selectTheme: ShadSelectTheme(
        decoration: ShadDecoration(
          disableSecondaryBorder: true,
          color: c.surfaceRaised,
          border: ShadBorder.all(
            color: c.outline,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
          focusedBorder: ShadBorder.all(
            color: c.accent,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
        ),
        padding: AppControl.inputPadding,
        optionsPadding: const EdgeInsets.all(AppSpacing.xs),
        // 下拉面板（浮在页面之上）走 surfaceRaised + 描边 + 无阴影。
        shadows: const <BoxShadow>[],
      ),
      optionTheme: ShadOptionTheme(
        backgroundColor: c.surfaceRaised,
        hoveredBackgroundColor: c.surfaceHover,
        selectedBackgroundColor: c.surfaceActive,
        selectedIconColor: c.accent,
        radius: BorderRadius.all(Radius.circular(AppRadius.chip)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      primaryToastTheme: _toastTheme(c),
      destructiveToastTheme: _toastTheme(c),
      primaryAlertTheme: _alertTheme(c),
      destructiveAlertTheme: _alertTheme(c),
      textareaTheme: ShadTextareaTheme(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // 多行控件至少两行高，但底边与单行控件同圆角同描边。
        constraints: BoxConstraints(minHeight: controlH * 2),
        decoration: ShadDecoration(
          disableSecondaryBorder: true,
          color: c.surfaceRaised,
          border: ShadBorder.all(
            color: c.outline,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
          focusedBorder: ShadBorder.all(
            color: c.accent,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
        ),
      ),
      // 分隔线与卡片边框同档：全站描边只有 outline 一个令牌。
      separatorTheme: ShadSeparatorTheme(
        color: c.outline,
        thickness: 1,
      ),
      // 文档：tooltip 延迟 500ms、tooltip 属交互态（120ms 淡入）。
      tooltipTheme: ShadTooltipTheme(
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: ShadDecoration(
          color: c.inverseSurface,
          border: ShadBorder.all(
            color: c.inverseSurface,
            width: 0,
            radius: BorderRadius.all(Radius.circular(AppRadius.chip)),
          ),
          shadows: const <BoxShadow>[],
        ),
      ),
    );
  }

  static ShadDialogTheme _dialogTheme(AppColors c) => ShadDialogTheme(
        backgroundColor: c.surfaceRaised,
        radius: BorderRadius.all(Radius.circular(AppRadius.card)),
        border: Border.all(color: c.outline, width: 1),
        padding: const EdgeInsets.all(AppSpacing.lg),
        gap: AppSpacing.md,
        shadows: const <BoxShadow>[],
      );

  static ShadToastTheme _toastTheme(AppColors c) => ShadToastTheme(
        backgroundColor: c.toast,
        border: ShadBorder.all(color: c.toast, width: 0),
        radius: BorderRadius.all(Radius.circular(AppRadius.bubble)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shadows: const <BoxShadow>[],
      );

  static ShadAlertTheme _alertTheme(AppColors c) => ShadAlertTheme(
        decoration: _surfaceDecoration(c),
        iconSize: 16,
        iconPadding: const EdgeInsets.only(right: AppSpacing.sm),
      );

  /// 排版 → ShadTextTheme。复用 [AppText._typeScale] 单一事实源（设计系统约束 D），
  /// Child Mode 在 Parent 基础上整体放大一档（ADR-0014）。
  static ShadTextTheme _shadTextTheme(AppColors c, {required bool child}) {
    double grow(double s) => child ? _childScale(s) : s;

    TextStyle style(String k, {Color? color}) {
      final (size, weight, height, spacing) = AppText._typeScale[k]!;
      return TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: grow(size),
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? c.onSurface,
      );
    }

    return ShadTextTheme(
      family: fontFamily,
      h1Large: style('displayLarge'),
      h1: style('displayMedium'),
      h2: style('headlineLarge'),
      h3: style('headlineMedium'),
      h4: style('headlineSmall'),
      p: style('bodyLarge'),
      blockquote: style('bodyLarge', color: c.onSurfaceVariant),
      table: style('labelMedium'),
      list: style('bodyLarge'),
      lead: style('headlineMedium'),
      large: style('titleLarge'),
      small: style('labelSmall'),
      muted: style('bodySmall', color: c.onSurfaceVariant),
    );
  }
}

// =====================================================================
// §语义色令牌集合
// =====================================================================

class AppColors {
  final Brightness brightness;

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;

  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;

  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  final Color surface;
  final Color onSurface;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurfaceVariant;
  final Color outline;

  final Color inverseSurface;
  final Color onInverseSurface;

  // 靛蓝强调 + hover + info 语义
  final Color accent;
  final Color onAccent;
  final Color surfaceHover;
  final Color outlineHover;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color ctaHover; // CTA（近黑/反色）按钮的 hover 底色
  final Color toast; // Toast 浮层底
  final Color onToast; // Toast 浮层文字
  final Color scrim; // 模态遮罩（抽屉/弹层）：固定半透明黑，避免运行时 withValues 伪造

  const AppColors({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurfaceVariant,
    required this.outline,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.accent,
    required this.onAccent,
    required this.surfaceHover,
    required this.outlineHover,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.ctaHover,
    required this.toast,
    required this.onToast,
    required this.scrim,
  });

  /// 浮起表面（卡片/容器背景）。
  Color get surfaceRaised => surfaceContainerLow;

  /// 下沉表面（侧栏/凹槽/弱化背景）。
  Color get surfaceSunken => surfaceContainerHigh;

  /// 选中态表面。
  Color get surfaceActive => surfaceContainerHighest;

  // ============ 语义色别名（文档 @.impeccable.md 的 public 令牌名） ============
  //
  // 底层存储沿用 shadcn / Material 角色名（primary/secondary/tertiary…），
  // 但**业务代码一律只用本段语义别名**，与文档令牌名一一对应，杜绝
  // 「用 secondaryContainer 表达 warning」这类角色名错读（CONTEXT.md 已把
  // primaryContainer/secondaryContainer/tertiaryContainer 列为 Avoid 词）。

  /// 正向（positive）容器底 / 前景。
  Color get semanticPositive => tertiaryContainer;

  Color get semanticPositiveFg => onTertiaryContainer;

  /// 警告（warning）容器底 / 前景。
  Color get semanticWarning => secondaryContainer;

  Color get semanticWarningFg => onSecondaryContainer;

  /// 错误（error）容器底 / 前景。
  Color get semanticError => errorContainer;

  Color get semanticErrorFg => onErrorContainer;

  /// 信息（info）容器底 / 前景。
  Color get semanticInfo => infoContainer;

  Color get semanticInfoFg => onInfoContainer;

  /// CTA 按钮底 / 文字（文档 `cta` / `onCta`）。
  Color get cta => primary;

  Color get onCta => onPrimary;
}

// =====================================================================
// §排版令牌（密排 15sp 基线）
// =====================================================================

/// Child Mode 字号放大映射（ADR-0014 Dual-Mode Type Scale）。
/// [AppText] 与 [AppTheme._shadTextTheme] 共用，消除双排版表漂移。
double _childScale(double s) {
  if (s == 22) return 26;
  if (s == 20) return 24;
  if (s == 18) return 21;
  if (s == 17) return 19;
  if (s == 16) return 18;
  if (s == 15) return 17;
  if (s == 14) return 16;
  if (s == 13) return 14;
  if (s == 12) return 13;
  return s + 2;
}

class AppText {
  final TextStyle? displayLarge;
  final TextStyle? displayMedium;
  final TextStyle? headlineLarge;
  final TextStyle? headlineMedium;
  final TextStyle? headlineSmall;
  final TextStyle? titleLarge;
  final TextStyle? titleMedium;
  final TextStyle? titleSmall;
  final TextStyle? bodyLarge;
  final TextStyle? bodyMedium;
  final TextStyle? bodySmall;
  final TextStyle? labelLarge;
  final TextStyle? labelMedium;
  final TextStyle? labelSmall;

  const AppText({
    required this.displayLarge,
    required this.displayMedium,
    required this.headlineLarge,
    required this.headlineMedium,
    required this.headlineSmall,
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
  });

  /// 单一字号事实源（双模式共用）。[AppText] 与 [_shadTextTheme] 均从此取数，
  /// 杜绝两套并行排版表漂移（设计系统约束 D）。
  static const Map<String, (double size, FontWeight weight, double height,
      double spacing)> _typeScale = {
    'displayLarge': (22, FontWeight.w700, 1.2, -0.6),
    'displayMedium': (20, FontWeight.w700, 1.2, -0.4),
    'headlineLarge': (18, FontWeight.w600, 1.25, -0.3),
    'headlineMedium': (17, FontWeight.w600, 1.3, -0.2),
    'headlineSmall': (16, FontWeight.w600, 1.3, -0.1),
    'titleLarge': (16, FontWeight.w600, 1.35, -0.1),
    'titleMedium': (15, FontWeight.w600, 1.35, 0),
    'titleSmall': (15, FontWeight.w600, 1.35, 0),
    'bodyLarge': (15, FontWeight.w400, 1.5, 0),
    'bodyMedium': (14, FontWeight.w400, 1.45, 0),
    'bodySmall': (13, FontWeight.w400, 1.45, 0.2),
    'labelLarge': (14, FontWeight.w600, 1.35, 0.2),
    'labelMedium': (13, FontWeight.w600, 1.35, 0.3),
    'labelSmall': (12, FontWeight.w500, 1.35, 0.3),
  };

  factory AppText._build(AppColors c, {required bool child}) {
    const ff = AppTheme.fontFamily;
    const ffb = AppTheme.fontFamilyFallback;
    final base = c.onSurface;
    final muted = c.onSurfaceVariant;
    final onCta = c.onPrimary;

    // Child Mode 字号映射（与 Dual-Mode Type Scale 表一致，复用 _childScale）。
    double cs(double s) => child ? _childScale(s) : s;

    // 每令牌前景色覆盖（其余默认 base）。
    Color? colorOf(String k) => switch (k) {
          'labelLarge' => onCta,
          'bodySmall' || 'labelSmall' => muted,
          _ => base,
        };
    // Child Mode 正文行高微调（低龄可读性）。
    double heightOf(String k, double h) => (child && k == 'bodyLarge') ? 1.55 : h;

    TextStyle mk(String k) {
      final (size, weight, height, spacing) = _typeScale[k]!;
      return TextStyle(
        fontFamily: ff,
        fontFamilyFallback: ffb,
        fontSize: cs(size),
        fontWeight: weight,
        height: heightOf(k, height),
        letterSpacing: spacing,
        color: colorOf(k),
      );
    }

    return AppText(
      displayLarge: mk('displayLarge'),
      displayMedium: mk('displayMedium'),
      headlineLarge: mk('headlineLarge'),
      headlineMedium: mk('headlineMedium'),
      headlineSmall: mk('headlineSmall'),
      titleLarge: mk('titleLarge'),
      titleMedium: mk('titleMedium'),
      titleSmall: mk('titleSmall'),
      bodyLarge: mk('bodyLarge'),
      bodyMedium: mk('bodyMedium'),
      bodySmall: mk('bodySmall'),
      labelLarge: mk('labelLarge'),
      labelMedium: mk('labelMedium'),
      labelSmall: mk('labelSmall'),
    );
  }
}

// =====================================================================
// §通用组件
// =====================================================================

/// 卡片：1px 极细描边 + surfaceRaised 填充，无阴影（Linear 风格）。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double? radius;
  final Border? border;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = const EdgeInsets.symmetric(vertical: 4),
    this.color,
    this.radius,
    this.border,
    this.onTap,
  });

  static ShadBorder _convertBorder(Border b) {
    ShadBorderSide side(BorderSide s) => ShadBorderSide(
          color: s.color,
          width: s.width,
          style: s.style,
        );
    return ShadBorder(
      top: side(b.top),
      right: side(b.right),
      bottom: side(b.bottom),
      left: side(b.left),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    ShadCard buildCard(Color borderColor) => ShadCard(
          padding: padding,
          backgroundColor: color ?? app.surfaceContainerLow,
          radius: BorderRadius.circular(radius ?? AppRadius.card),
          border: border != null
              ? _convertBorder(border!)
              : ShadBorder.all(color: borderColor, width: 1),
          shadows: const <BoxShadow>[],
          child: child,
        );
    // NOTE: Do NOT wrap `buildCard(...)` in `ShadButton.ghost(width: double.infinity)`.
    // That injects a `BoxConstraints(minWidth: ∞, maxWidth: ∞)` into the card,
    // which shadcn's internal `ShadCard` structure
    // (`Row(mainAxisSize: min) → Flexible → Column → Flexible → child`) then
    // passes down as UNBOUNDED width. Any `Expanded`/`Flexible` inside the
    // card content (e.g. the task-list card's `Row(Expanded)`) then throws
    // "RenderFlex children have non-zero flex but incoming width constraints
    // are unbounded". A bare `GestureDetector` is pass-through: it imposes no
    // width constraint, so the card receives the parent's bounded width and
    // still fills it via its own `Expanded` content. `GestureDetector` needs
    // no `Material` ancestor, so it is safe under `ShadApp`.
    if (onTap == null) {
      return Container(margin: margin, child: buildCard(app.outline));
    }
    // 可点击卡片：hover 时边框微深到 outlineHover，让"可点"有真实反馈，
    // 同时激活此前定义却从未接入的 outlineHover 令牌（shadcn 原生 button/input
    // 无 hover-border API，故在我们的卡片组件里接）。
    final hover = ValueNotifier(false);
    return Container(
      margin: margin,
      child: ValueListenableBuilder<bool>(
        valueListenable: hover,
        builder: (_, h, __) => MouseRegion(
          cursor: SystemMouseCursors.basic,
          onEnter: (_) => hover.value = true,
          onExit: (_) => hover.value = false,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: buildCard(h ? app.outlineHover : app.outline),
          ),
        ),
      ),
    );
  }
}

/// 主操作按钮：品牌靛蓝 CTA（走 accent）。
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool fullWidth;
  final IconData? icon;
  final String? loadingLabel;
  final double? height;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.fullWidth = true,
    this.icon,
    this.loadingLabel,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final spinner = Icon(
      LucideIcons.loaderCircle,
      size: 18,
      color: app.onCta,
    ).animate(onPlay: (c) => c.repeat()).rotate(
          begin: 0,
          end: 1,
          duration: const Duration(milliseconds: 900),
          curve: Curves.linear,
        );
    final labelWidget = Text(
      loading ? (loadingLabel ?? label) : label,
      textAlign: TextAlign.center,
      style: AppTheme.textOf(context).labelLarge?.copyWith(
            color: app.onCta,
          ),
    );
    final child = icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              loading ? spinner : Icon(icon, size: 16, color: app.onCta),
              const SizedBox(width: 8),
              labelWidget,
            ],
          )
        : (loading ? spinner : labelWidget);
    return ShadButton(
      height: height ?? AppControl.heightOf(context),
      expands: fullWidth,
      onPressed: loading ? null : onPressed,
      child: child,
    );
  }
}

/// 线性进度条：靛蓝填充。
class AppProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  const AppProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return ShadProgress(
      value: value.clamp(0.0, 1.0),
      minHeight: height,
      color: color ?? app.accent,
      backgroundColor: trackColor ?? app.surfaceContainerHighest,
    );
  }
}

// =====================================================================
// §语义化组件
// =====================================================================

/// Hover 感知的语义 pill：常态与 hover 态同步切换底色（克制版——同色微深，
/// 不填实饱和色），前景色保持不变，文字始终可读且整体协调。
///
/// 设计背景：shadcn 的 [ShadBadge] 仅支持单一 [foregroundColor]，hover 时
/// 背景切到 [hoverBackgroundColor] 而文字颜色不变；本 App 的 badge 主题未设
/// [hoverBackgroundColor]，导致 hover 背景变透明、文字残留容器前景色而不可读。
/// 这里自管 hover 状态，同时切换底色（同色微深）+ 保持前景，彻底解决「背景变、
/// 字不变、看不清」，且 hover 不再填实饱和色（修复标签成全站最吵元素的问题）。
Color _hoverDeepen(Color bg, Brightness b) => b == Brightness.dark
    ? Color.lerp(bg, const Color(0xFFFFFFFF), 0.10)!
    : Color.lerp(bg, const Color(0xFF000000), 0.08)!;

class _HoverPill extends StatelessWidget {
  final Color bg;
  final Color fg;
  final ShapeBorder shape;
  final EdgeInsetsGeometry padding;
  final double iconSize;
  final double gap;
  final IconData? icon;
  final String label;

  const _HoverPill({
    required this.bg,
    required this.fg,
    required this.shape,
    required this.padding,
    this.iconSize = 13,
    this.gap = 5,
    this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final bright = CupertinoTheme.brightnessOf(context) == Brightness.dark
        ? Brightness.dark
        : Brightness.light;
    final hovered = ValueNotifier(false);
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => hovered.value = true,
      onExit: (_) => hovered.value = false,
      child: ValueListenableBuilder<bool>(
        valueListenable: hovered,
        builder: (ctx, h, _) {
          final b = h ? _hoverDeepen(bg, bright) : bg;
          final f = fg;
          return Container(
            decoration: ShapeDecoration(shape: shape, color: b),
            padding: padding,
            child: IconTheme(
              data: IconThemeData(color: f, size: iconSize),
              child: DefaultTextStyle(
                style: (AppTheme.textOf(context).labelSmall ??
                        const TextStyle())
                    .copyWith(color: f, fontWeight: FontWeight.w600),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: iconSize),
                      SizedBox(width: gap),
                    ],
                    Text(label),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 语义 Chip/Pill：降饱和底色 + 对应前景色。
class AppTags {
  static Widget normal(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon,
        semantics: _TagSemantics.normal,
      );

  static Widget info(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon,
        semantics: _TagSemantics.info,
      );

  static Widget ai(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon ?? LucideIcons.sparkles,
        semantics: _TagSemantics.ai,
      );

  static Widget success(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon ?? LucideIcons.checkCircle2,
        semantics: _TagSemantics.success,
      );

  static Widget warning(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon,
        semantics: _TagSemantics.warning,
      );

  /// 学科标签：用学科色（accent/container/fg）着色，仅小面积使用。
  static Widget subject(SubjectKey key, {String? label, IconData? icon}) =>
      _TagChip(
        label: label ?? SubjectAccent.label(key),
        icon: icon,
        semantics: _TagSemantics.normal,
        subject: key,
      );
}

enum _TagSemantics { normal, info, ai, success, warning }

class _TagChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final _TagSemantics semantics;
  final SubjectKey? subject;
  const _TagChip({
    required this.label,
    this.semantics = _TagSemantics.normal,
    this.icon,
    this.subject,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    late final Color bg;
    late final Color fg;
    if (subject != null) {
      final sc = SubjectAccent.forContext(subject!, context);
      bg = sc.container;
      fg = sc.fg;
    } else {
      (bg, fg) = switch (semantics) {
        _TagSemantics.normal => (app.surfaceSunken, app.onSurface),
        _TagSemantics.info => (app.semanticInfo, app.semanticInfoFg),
        // AI 归 info 靛蓝档：不新增与 warning 琥珀重复的色，保持「一色 + 四档语义色」。
        _TagSemantics.ai => (app.semanticInfo, app.semanticInfoFg),
        _TagSemantics.success => (app.semanticPositive, app.semanticPositiveFg),
        // 曾经误用 errorContainer（红）表达 warning——与文档 semanticWarning
        // 琥珀档不符，红/琥珀语义串味。改走语义别名，杜绝再次错读。
        _TagSemantics.warning => (app.semanticWarning, app.semanticWarningFg),
      };
    }

    return _HoverPill(
      bg: bg,
      fg: fg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
      ),
      iconSize: 13,
      gap: 4,
      icon: icon,
      label: label,
    );
  }
}

/// 语义 Badge（胶囊）。
class AppBadge {
  static Widget successChip(String label) => _BadgePill(
        label: label,
        icon: LucideIcons.check,
        semantics: _BadgeSemantics.success,
      );

  static Widget warningChip(String label) => _BadgePill(
        label: label,
        icon: LucideIcons.alertTriangle,
        semantics: _BadgeSemantics.warning,
      );

  static Widget infoChip(String label) => _BadgePill(
        label: label,
        icon: LucideIcons.info,
        semantics: _BadgeSemantics.info,
      );
}

enum _BadgeSemantics { success, warning, info }

class _BadgePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final _BadgeSemantics semantics;
  const _BadgePill({
    required this.label,
    required this.icon,
    required this.semantics,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final (bg, fg) = switch (semantics) {
      _BadgeSemantics.success =>
        (app.semanticPositive, app.semanticPositiveFg),
      _BadgeSemantics.warning =>
        (app.semanticWarning, app.semanticWarningFg),
      _BadgeSemantics.info => (app.semanticInfo, app.semanticInfoFg),
    };

    return _HoverPill(
      bg: bg,
      fg: fg,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      shape: const StadiumBorder(),
      iconSize: 12,
      gap: 4,
      icon: icon,
      label: label,
    );
  }
}

/// 章节标题：左侧 3px 靛蓝色条 + 标题文字
/// 规范章节节奏（统一间距事实源，ADR 设计系统约束）：
/// - top    = [AppSpacing.sm] (8)：标题上沿留白；相邻 section 靠「上标题 bottom(8)
///   + 下标题 top(8)」叠加成 16px 统一间隔，页面无需再手动加 SizedBox。
/// - bottom = [AppSpacing.sm] (8)：标题 → 内容的统一间隔。
/// - 水平 0：标题左缘与全宽卡片（AppCard）左缘对齐；页面不要再给卡片套
///   `Padding(horizontal: lg)`，否则会与标题错位 ~12px。
/// 所有家长/设置页共用此节奏，确保跨页面 UI 一致。
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding =
        const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.sm),
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final style = AppTheme.textOf(context).titleMedium;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 18,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: app.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(child: Text(text, style: style)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Squircle 方圆形头像。
class AvatarSquircle extends StatelessWidget {
  final String name;
  final double size;
  final Color? bg;
  final Color? fg;

  const AvatarSquircle({
    super.key,
    required this.name,
    this.size = 96,
    this.bg,
    this.fg,
  });

  const AvatarSquircle.small({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 40;

  /// 紧凑预设：用于侧栏/顶栏的触发芯片（如切换娃娃按钮），比 [small] 更小。
  const AvatarSquircle.xs({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 28;

  const AvatarSquircle.medium({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 56;

  const AvatarSquircle.large({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 80;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final background = bg ?? app.primaryContainer;
    final foreground = fg ?? app.onPrimaryContainer;
    return ShadAvatar(
      null,
      size: Size.square(size),
      backgroundColor: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(size * 0.32)),
        side: BorderSide.none,
      ),
      placeholder: Text(
        name.isNotEmpty ? name[0] : '?',
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontFamilyFallback: AppTheme.fontFamilyFallback,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// 间距令牌（4 基准模数刻度：xs=4 为步长；密排缩减，非 8 倍网格）
class AppSpacing {
  static const double xs2 = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xl2 = 28;
  static const double xl3 = 32;
  static const double xl4 = 40;
  static const double xl5 = 48;
}

/// 圆角令牌（密排 / 简洁收敛）
///
/// 设计约束（单一事实源，全站通用组件共用）：
/// - 采用 4 / 6 / 8 三档阶梯，避免「容器比内部控件更尖」的倒置。
/// - 控件（chip / button / input）与卡片（card）统一 6，保证按钮落在卡片内时
///   角半径一致、视觉内聚；大面（banner / bubble）略放至 8 维持体量。
/// - 装饰性大圆角（头像 / 分数环 / 浮层）不在本表约束内，按场景取 28/32/999。
class AppRadius {
  static const double xs = 4; // 标记点 / 极小元素
  static const double sm = 6; // 微缩元素
  static const double chip = 6; // 标签 / 侧栏项
  static const double button = 6; // 按钮
  static const double input = 6; // 输入框
  static const double card = 6; // 卡片容器
  static const double bubble = 8; // 答案气泡 / 浮层小卡
  static const double banner = 8; // 大面横幅
}

/// 控件高度令牌（交互控件统一高度）
///
/// 设计约束（单一事实源）：输入框、按钮、下拉选择器等同属「交互控件」，
/// 必须共用同一高度，避免同行控件高低不齐（如布置任务表单中 36px 按钮与
/// ~40px 输入框并排错落）。平板优先 + Child Mode 放大，取 40（= AppSpacing.xl4）。
/// 紧凑场景（表格行内小按钮）用 [heightSm] = 32（= AppSpacing.xl3）。
/// 控件密度（交互控件紧凑度）。与亮暗（[AppThemeMode]）、用户模式（[AppUserMode]）正交，
/// 用于推导统一的控件高度，使按钮 / 输入框 / 选择器随紧凑度缩放。
///
/// **默认 [compact]**（parent 32 / child 40）。密度已全局接入：由 `densityProvider`
/// 持久化并驱动 `AppTheme.shadFor(isDark, mode, density)`，[DensityScope] 只需在
/// 需要局部偏离的子树上包一层（如数据密集型表格切 [normal]）。
/// 所有控件高度都由该维度推导，无硬编码魔法值。
enum AppDensity { normal, compact }

/// 控件高度令牌（交互控件统一高度，单一事实源）
///
/// 设计约束：输入框、按钮、下拉选择器等同属「交互控件」，必须共用同一高度，避免同行控件
/// 高低不齐。高度完全由「用户模式 × 密度」推导，**全部取自间距令牌 [AppSpacing]，无魔法数字**，
/// 并随紧凑度 / 双模式自动缩放（呼应 ADR-0014 双模式字号阶梯）。
///
/// | 用户模式＼密度 | normal | **compact（默认）** |
/// |---|---|---|
/// | parent（密排专业） | xl4 = 40 | **xl3 = 32** |
/// | child（大字趣味）  | xl5 = 48 | **xl4 = 40** |
///
/// 取值依据：平板优先 + 触控目标；parent 默认取 32（扁平工具型界面，节省纵向空间）；
/// child 模式字号放大一档，控件同步放大到 40 以匹配更大点击区；
/// normal 各升一档（40 / 48）用于需要更松呼吸感 / 纯触控的场景。
class AppControl {
  /// 全局默认密度（= [AppDensity.compact]，parent 32 / child 40）。
  static const AppDensity defaultDensity = AppDensity.compact;

  /// 主交互控件高度（输入框 / 按钮 / 选择器）。
  static double height(AppUserMode mode, AppDensity density) => switch ((mode, density)) {
        (AppUserMode.child, AppDensity.compact) => AppSpacing.xl4, // 40
        (AppUserMode.child, AppDensity.normal) => AppSpacing.xl5, // 48
        (AppUserMode.parent, AppDensity.compact) => AppSpacing.xl3, // 32
        (AppUserMode.parent, AppDensity.normal) => AppSpacing.xl4, // 40
      };

  /// 紧凑控件（表格行内小按钮 / 行内操作）：比主控件小一档（间距 md=12 档差）。
  static double heightSm(AppUserMode mode, AppDensity density) => switch ((mode, density)) {
        (AppUserMode.child, AppDensity.compact) => AppSpacing.xl3, // 32
        (AppUserMode.child, AppDensity.normal) => AppSpacing.xl4, // 40
        (AppUserMode.parent, AppDensity.compact) => AppSpacing.xl2, // 28
        (AppUserMode.parent, AppDensity.normal) => AppSpacing.xl3, // 32
      };

  /// 从上下文解析当前模式 + 密度（[UserModeScope] / [DensityScope] 未挂载时回退
  /// parent / [AppControl.defaultDensity]）。
  static double heightOf(BuildContext context) =>
      height(UserModeScope.of(context), DensityScope.of(context));

  /// 从上下文解析紧凑控件高度。
  static double heightSmOf(BuildContext context) =>
      heightSm(UserModeScope.of(context), DensityScope.of(context));

  /// 输入类控件（ShadInput / ShadSelect / ShadTextarea 外层）的内边距。
  ///
  /// **竖向必须为 0**：高度由 [inputConstraintsOf] 的 tight 约束钉死，竖向 padding 只会
  /// 把内容挤出去；垂直居中靠 `crossAxisAlignment: center`。
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(horizontal: 12);

  /// 输入类控件的盒约束：钉死到 [heightOf]，与按钮严格同高。
  ///
  /// 用 `minHeight` 不够——单行文字行高（15px 字 ≈ 18~20px）+ padding 会把它顶成
  /// 34px，按钮却是 32px，同行又错落。必须用 `tightFor`。
  static BoxConstraints inputConstraintsOf(BuildContext context) =>
      BoxConstraints.tightFor(height: heightOf(context));

  /// 单行输入框文字垂直居中所需的 [StrutStyle]。
  ///
  /// 根因：shadcn 的 `ShadInput` 不暴露 `textAlignVertical`，其内部 `EditableText`
  /// 默认 `textAlignVertical: top`，文字会落在编辑盒**顶端**（实测 compact 偏上
  /// ~2.8px、child 模式偏上 ~8.7px）——这就是「输入框文字不上下居中」的真正原因。
  /// 用 `forceStrutHeight` 把行高强制撑满编辑盒（controlH - 4，扣边框与 shadcn
  /// 内部预留），Flutter 的半行距（half-leading）会把字形上下均分 → 视觉严格居中。
  ///
  /// 仅用于「精确 controlH 高、无额外竖向 padding」的**单行**输入；多行输入本就该
  /// 顶对齐，带大竖向 padding 的输入（如聊天栏）已因盒子高、文字盒短而被居中，勿用。
  static StrutStyle inputStrut(BuildContext context, TextStyle? style) {
    final fontSize = style?.fontSize ?? 16;
    return StrutStyle(
      fontSize: fontSize,
      height: (heightOf(context) - 4) / fontSize,
      forceStrutHeight: true,
    );
  }

  /// 多行输入的最小高度（两行起步）。
  static BoxConstraints textareaConstraintsOf(BuildContext context) =>
      BoxConstraints(minHeight: heightOf(context) * 2);
}

/// 转场时长令牌（三档 + Child Mode 庆祝档，ADR-0014）
class AppMotion {
  /// 交互态：hover / press / focus
  static const Duration interaction = Duration(milliseconds: 120);

  /// 状态切换：展开 / 收起 / 切换
  static const Duration state = Duration(milliseconds: 200);

  /// 页面进入
  static const Duration page = Duration(milliseconds: 300);

  /// 庆祝反馈：徽章解锁 / 连击 +1 / 打卡成功。**仅 Child Mode**（见
  /// [celebrateFor]）；Parent Mode 不触发，避免游戏化。
  static const Duration celebrate = Duration(milliseconds: 450);

  /// 答对题的 scale-pop（Child Mode 微奖励）
  static const Duration pop = interaction;

  /// 庆祝动效按用户模式取值：Child 走 450ms 庆祝档，Parent 退回状态切换档。
  static Duration celebrateFor(AppUserMode mode) =>
      mode == AppUserMode.child ? celebrate : state;
}

/// 转场曲线令牌（与 [AppMotion] 配套，禁止裸写 Curves.*）。
class AppCurves {
  /// 交互态：快出
  static const Curve interaction = Curves.easeOut;

  /// 状态切换：快出
  static const Curve state = Curves.easeOut;

  /// 页面进入：渐进渐出
  static const Curve page = Curves.easeInOut;

  /// 庆祝：回弹（仅 Child Mode）
  static const Curve celebrate = Curves.easeOutBack;
}

// =====================================================================
// §用户模式作用域（双模式切换，ADR-0014）
// =====================================================================

/// 将当前 [AppUserMode] 注入 Widget 树。
///
/// [AppTheme.textOf] 通过它读取模式，从而所有 `Text(style: AppTheme.textOf(context)...)`
/// 在模式切换时自动重建——无需逐个 widget 监听 [userModeProvider]。
/// 未挂载时默认 [AppUserMode.parent]，避免脱离作用域调用崩溃。
class UserModeScope extends InheritedWidget {
  final AppUserMode mode;

  const UserModeScope({
    super.key,
    required this.mode,
    required super.child,
  });

  static AppUserMode of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserModeScope>()?.mode ??
      AppUserMode.parent;

  @override
  bool updateShouldNotify(UserModeScope old) => old.mode != mode;
}

/// 控件密度作用域：向子树广播 [AppDensity]，使 [AppControl.heightOf] 随紧凑度推导高度。
///
/// 用法同 [UserModeScope]。全局密度已由 `densityProvider` 驱动（默认
/// [AppDensity.compact]），本 Scope 只用于**局部偏离**（如密集表格切回 [normal]）。
/// 未挂载时回退 [AppControl.defaultDensity]，与主题层保持一致。
class DensityScope extends InheritedWidget {
  final AppDensity density;

  const DensityScope({
    super.key,
    required this.density,
    required super.child,
  });

  static AppDensity of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DensityScope>()?.density ??
      AppControl.defaultDensity;

  @override
  bool updateShouldNotify(DensityScope old) => old.density != density;
}
