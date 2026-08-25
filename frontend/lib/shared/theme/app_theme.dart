import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shadcn_ui/shadcn_ui.dart';

/// 按正确率分级的视觉情绪。
///
/// 用于做题完成页的图标容器配色，基于植物绿/暖橙/天蓝语义色。
enum ResultTone { positive, warm, alert, neutral }

/// 应用主题模式（替代 Material ThemeMode）。
enum AppThemeMode { system, light, dark }

/// 解析系统/主题下的实际亮度。
Brightness resolveBrightness(AppThemeMode mode, Brightness systemBrightness) {
  return switch (mode) {
    AppThemeMode.system => systemBrightness,
    AppThemeMode.light => Brightness.light,
    AppThemeMode.dark => Brightness.dark,
  };
}

/// 应用主题模式 → Material [ThemeMode]，供 `ShadApp.custom.themeMode` 使用。
ThemeMode appThemeModeToMaterial(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };

/// 护眼双主题（亮色 + 暗色 · 纯 Cupertino 设计系统 · 明快儿童化配色）。
///
/// 设计约定（见 .impeccable.md / copilot-instructions.md）：
/// - 亮色：护眼暖白背景 + 明快植物绿主强调（提亮饱和）+ 暖橙/天蓝次强调
/// - 暗色：暖调深炭（**禁用纯黑**）+ 提亮后的植物绿/暖橙/天蓝
/// - 三强调色方案：primary 植物绿主操作 / secondary 暖橙（AI 暖区）/ tertiary 天蓝（积极反馈）/ error 温柔珊瑚
/// - 正文 ≥ 20sp、选项 ≥ 22sp、辅助说明 ≥ 16sp、行高 ≥ 1.5
/// - 卡片无描边 + surfaceRaised 暖色填充（无重阴影）、大圆角
/// - 字体：HarmonyOS Sans SC / Noto Sans SC 回退链
///
/// 本文件 **不含任何 Material 主题配置**。业务代码请统一通过
/// `AppTheme.colorsOf(context)` 取语义色、`AppTheme.textOf(context)` 取排版，
/// 或使用本文件下方的语义化组件（AppTags、AppBadge、AvatarSquircle 等）。
/// 语义化组件会自动跟随亮/暗模式。
///
/// 依赖：Flutter 3.47 去耦合落地后的独立包 `cupertino_ui`（纯 Cupertino 组件库）。
class AppTheme {
  const AppTheme._();

  /// 字体回退链（HarmonyOS Sans SC 优先，运行时缺失自动回退）。
  static const String fontFamily = 'HarmonyOS_Sans_SC';

  /// 亮色语义色令牌。
  static const AppColors light = AppColors(
    brightness: Brightness.light,
    primary: Color(0xFF43A047), // 明快植物绿
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD8F0D9),
    onPrimaryContainer: Color(0xFF0F3D1A),
    secondary: Color(0xFFF97316), // 暖橙次强调
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFFE4D0),
    onSecondaryContainer: Color(0xFF4A1D00),
    tertiary: Color(0xFF38BDF8), // 天蓝次强调
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD3F0FC),
    onTertiaryContainer: Color(0xFF0B3447),
    error: Color(0xFFE56B54), // 温柔珊瑚
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFBE3DC),
    onErrorContainer: Color(0xFF44150F),
    surface: Color(0xFFFDF8F0), // Warm Canvas 主背景
    onSurface: Color(0xFF2D2D2D), // Charcoal Ink 主文字
    surfaceContainerLowest: Color(0xFFFFFBF3), // → surfaceRaised
    surfaceContainerLow: Color(0xFFFFFBF3), // = surfaceRaised
    surfaceContainer: Color(0xFFFFFBF3), // = surfaceRaised
    surfaceContainerHigh: Color(0xFFF4ECDA), // = surfaceSunken
    surfaceContainerHighest: Color(0xFFF4ECDA), // → surfaceSunken
    onSurfaceVariant: Color(0xFF70685B), // Muted Stone 次文字（达 WCAG AA ≥4.5:1）
    outline: Color(0xFFEFE7D8), // Whisper Border
    outlineVariant: Color(0x99EFE7D8), // whisper border 60%
    inverseSurface: Color(0xFFEDE6D8),
    onInverseSurface: Color(0xFF1D1B17),
  );

  /// 暗色语义色令牌（暖调深炭，非纯黑）。
  static const AppColors dark = AppColors(
    brightness: Brightness.dark,
    primary: Color(0xFF76C87A), // 深底用提亮后的植物绿
    onPrimary: Color(0xFF0A3311),
    primaryContainer: Color(0xFF23522A),
    onPrimaryContainer: Color(0xFFCBEECE),
    secondary: Color(0xFFFFA85C), // 暖橙提亮
    onSecondary: Color(0xFF3A1C00),
    secondaryContainer: Color(0xFF5C3408),
    onSecondaryContainer: Color(0xFFFFE3C4),
    tertiary: Color(0xFF6FD0F4), // 天蓝提亮
    onTertiary: Color(0xFF062A3A),
    tertiaryContainer: Color(0xFF10455C),
    onTertiaryContainer: Color(0xFFCDEDFC),
    error: Color(0xFFF29B8F),
    onError: Color(0xFF3A0D06),
    errorContainer: Color(0xFF5E2B20),
    onErrorContainer: Color(0xFFFBE3DC),
    surface: Color(0xFF1D1B17), // 暖调深炭主背景
    onSurface: Color(0xFFEDE6D8),
    surfaceContainerLowest: Color(0xFF171512), // = surfaceSunken
    surfaceContainerLow: Color(0xFF2A261F), // → surfaceRaised
    surfaceContainer: Color(0xFF2A261F), // = surfaceRaised
    surfaceContainerHigh: Color(0xFF2A261F), // → surfaceRaised
    surfaceContainerHighest: Color(0xFF171512), // → surfaceSunken
    onSurfaceVariant: Color(0xFFBFB6A8),
    outline: Color(0xFF4A4438),
    outlineVariant: Color(0xB34A4438), // outline 70%
    inverseSurface: Color(0xFF2D2D2D),
    onInverseSurface: Color(0xFFFDF8F0),
  );

  static bool isDarkOf(BuildContext context) {
    return CupertinoTheme.brightnessOf(context) == Brightness.dark;
  }

  /// 取当前主题亮/暗对应的语义色集合。
  static AppColors colorsOf(BuildContext context) {
    return CupertinoTheme.brightnessOf(context) == Brightness.dark ? dark : light;
  }

  // ============ 排版令牌 ============
  static final AppText _lightText = AppText._build(light);
  static final AppText _darkText = AppText._build(dark);

  /// 取当前主题对应的排版。字号/行高与亮暗无关，行内颜色取自语义色。
  static AppText textOf(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.dark ? _darkText : _lightText;

  // ============ Cupertino 主题 ============

  /// 亮色 Cupertino 主题，用于 [CupertinoApp.theme]。
  static CupertinoThemeData get cupertinoLight => _cupertino(light);

  /// 暗色 Cupertino 主题。
  static CupertinoThemeData get cupertinoDark => _cupertino(dark);

  static CupertinoThemeData _cupertino(AppColors c) {
    return CupertinoThemeData(
      brightness: c.brightness,
      primaryColor: c.primary,
      primaryContrastingColor: c.onPrimary,
      barBackgroundColor: c.surface,
      scaffoldBackgroundColor: c.surface,
      textTheme: CupertinoTextThemeData(
        primaryColor: c.primary,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          color: c.onSurface,
        ),
      ),
    );
  }

  // ============ Shad Theme（混合模式：Shadcn + Cupertino） ============

  /// 由 [AppColors] 语义色令牌映射出 `ShadThemeData`，供
  /// `ShadApp.custom(theme: …shadThemeData(light), darkTheme: …shadThemeData(dark))`。
  ///
  /// ShadColorScheme 结构体构造需全部必填字段通过；除标准角色外，
  /// 把项目独有的三强调色与各 container 语义色放入 custom map 供业务侧读取。
  static ShadThemeData shadThemeData(AppColors c) {
    final scheme = ShadColorScheme(
      background: c.surface,
      foreground: c.onSurface,
      card: c.surfaceContainerLow,
      cardForeground: c.onSurface,
      popover: c.surface,
      popoverForeground: c.onSurface,
      primary: c.primary,
      primaryForeground: c.onPrimary,
      secondary: c.secondaryContainer,
      secondaryForeground: c.onSecondaryContainer,
      muted: c.surfaceContainer,
      mutedForeground: c.onSurfaceVariant,
      accent: c.surfaceContainerHigh,
      accentForeground: c.onSurface,
      destructive: c.error,
      destructiveForeground: c.onError,
      border: c.outline,
      input: c.outlineVariant,
      ring: c.primary,
      selection: c.primary,
      custom: {
        'secondary': c.secondary,
        'onSecondary': c.onSecondary,
        'tertiary': c.tertiary,
        'onTertiary': c.onTertiary,
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
      },
    );

    // 常量透明度（禁用纯黑，用透明表示“无填充”）
    const transparent = Color(0x00000000);

    /// 实心按钮（primary / secondary / destructive）。
    ShadButtonTheme button(Color bg, Color fg) => ShadButtonTheme(
          backgroundColor: bg,
          foregroundColor: fg,
          hoverBackgroundColor: bg,
          hoverForegroundColor: fg,
          pressedBackgroundColor: bg,
          pressedForegroundColor: fg,
          decoration: ShadDecoration(
            border: ShadBorder.all(
              color: bg,
              width: 0,
              radius: BorderRadius.all(Radius.circular(AppRadius.button)),
            ),
          ),
        );

    /// 胶囊/圆角徽标。
    ShadBadgeTheme badge(Color bg, Color fg) => ShadBadgeTheme(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadius.chip),
            ),
          ),
        );

    return ShadThemeData(
      brightness: c.brightness,
      colorScheme: scheme,
      radius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
      textTheme: _shadTextTheme(c),
      disabledOpacity: 0.5,
      primaryButtonTheme: button(c.primary, c.onPrimary),
      secondaryButtonTheme: button(c.secondaryContainer, c.onSecondaryContainer),
      destructiveButtonTheme: button(c.error, c.onError),
      outlineButtonTheme: ShadButtonTheme(
        backgroundColor: transparent,
        foregroundColor: c.primary,
        hoverBackgroundColor: c.primaryContainer,
        pressedBackgroundColor: c.primaryContainer,
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
        foregroundColor: c.primary,
        hoverBackgroundColor: c.primaryContainer,
        pressedBackgroundColor: c.primaryContainer,
      ),
      linkButtonTheme: ShadButtonTheme(
        backgroundColor: transparent,
        foregroundColor: c.primary,
        textDecoration: TextDecoration.underline,
      ),
      primaryBadgeTheme: badge(c.primary, c.onPrimary),
      secondaryBadgeTheme: badge(c.secondaryContainer, c.onSecondaryContainer),
      destructiveBadgeTheme: badge(c.error, c.onError),
      outlineBadgeTheme: ShadBadgeTheme(
        backgroundColor: transparent,
        foregroundColor: c.onSurface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.outline, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
      ),
      cardTheme: ShadCardTheme(
        backgroundColor: c.surfaceContainerLow,
        border: ShadBorder.all(color: const Color(0x00000000), width: 0),
        radius: const BorderRadius.all(Radius.circular(AppRadius.card)),
        padding: const EdgeInsets.all(AppSpacing.xl),
        shadows: const <BoxShadow>[],
      ),
      progressTheme: ShadProgressTheme(
        backgroundColor: c.surfaceContainerHighest,
        color: c.primary,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        minHeight: 8,
      ),
      inputTheme: ShadInputTheme(
        decoration: ShadDecoration(
          color: c.surfaceContainerLow,
          border: ShadBorder.all(
            color: c.outline,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
          focusedBorder: ShadBorder.all(
            color: c.primary,
            width: 1.5,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
        ),
        placeholderStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          color: c.onSurfaceVariant,
        ),
        cursorColor: c.primary,
      ),
    );
  }

  /// 护眼排版 → `ShadTextTheme`（正文 ≥20sp、辅助 ≥16sp、行高 ≥1.4）。
  static ShadTextTheme _shadTextTheme(AppColors c) {
    TextStyle style({
      required double size,
      required FontWeight weight,
      double height = 1.4,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color ?? c.onSurface,
      );
    }

    return ShadTextTheme(
      family: fontFamily,
      h1Large: style(size: 40, weight: FontWeight.w700, height: 1.15),
      h1: style(size: 34, weight: FontWeight.w700, height: 1.2),
      h2: style(size: 30, weight: FontWeight.w700, height: 1.25),
      h3: style(size: 26, weight: FontWeight.w700, height: 1.3),
      h4: style(size: 24, weight: FontWeight.w600, height: 1.3),
      p: style(size: 20, weight: FontWeight.w400, height: 1.5),
      blockquote: style(
        size: 20,
        weight: FontWeight.w400,
        height: 1.5,
        color: c.onSurfaceVariant,
      ),
      table: style(size: 18, weight: FontWeight.w600, height: 1.4),
      list: style(size: 20, weight: FontWeight.w400, height: 1.5),
      lead: style(size: 24, weight: FontWeight.w500, height: 1.4),
      large: style(size: 22, weight: FontWeight.w600, height: 1.4),
      small: style(size: 16, weight: FontWeight.w500, height: 1.4),
      muted: style(
        size: 16,
        weight: FontWeight.w400,
        height: 1.5,
        color: c.onSurfaceVariant,
      ),
    );
  }
}

// =====================================================================
// §语义色令牌集合（亮/暗实例）
// =====================================================================

/// 应用自有语义色令牌（对应过去 Material ColorScheme 的角色，但完全独立于 Material）。
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
  final Color outlineVariant;

  final Color inverseSurface;
  final Color onInverseSurface;

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
    required this.outlineVariant,
    required this.inverseSurface,
    required this.onInverseSurface,
  });

  /// 主操作（植物绿）。
  Color get accent => primary;

  /// AI 暖区（暖橙）。
  Color get aiAccent => secondary;

  /// 积极反馈（天蓝）。
  Color get feedbackAccent => tertiary;

  /// 浮起表面（卡片/容器背景，替代 surfaceContainerLow）。
  Color get surfaceRaised => surfaceContainerLow;

  /// 下沉表面（轨道/凹槽/弱化背景，替代 surfaceContainerHighest）。
  Color get surfaceSunken => surfaceContainerHighest;
}

// =====================================================================
// §排版令牌（自研 AppText，非 Material TextTheme）
// =====================================================================

/// 应用自有排版集合。字号/行高固定，行内颜色随亮暗语义色。
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

  factory AppText._build(AppColors c) {
    const fontFamily = AppTheme.fontFamily;
    final base = c.onSurface;
    final muted = c.onSurfaceVariant;
    final onPrimaryText = c.onPrimary;

    TextStyle textStyle({
      required double size,
      required FontWeight weight,
      double height = 1.4,
      double spacing = 0,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? base,
      );
    }

    return AppText(
      displayLarge: textStyle(size: 40, weight: FontWeight.w700, height: 1.15, spacing: -1.0),
      displayMedium: textStyle(size: 32, weight: FontWeight.w700, height: 1.2, spacing: -0.6),
      headlineLarge: textStyle(size: 28, weight: FontWeight.w700, height: 1.25, spacing: -0.4),
      headlineMedium: textStyle(size: 26, weight: FontWeight.w700, height: 1.3, spacing: -0.3),
      headlineSmall: textStyle(size: 24, weight: FontWeight.w600, height: 1.3, spacing: -0.2),
      titleLarge: textStyle(size: 24, weight: FontWeight.w700, height: 1.35, spacing: -0.3),
      titleMedium: textStyle(size: 22, weight: FontWeight.w600, height: 1.4, spacing: -0.15),
      titleSmall: textStyle(size: 20, weight: FontWeight.w600),
      bodyLarge: textStyle(size: 20, weight: FontWeight.w400, height: 1.55),
      bodyMedium: textStyle(size: 18, weight: FontWeight.w400, height: 1.55),
      bodySmall: textStyle(size: 16, weight: FontWeight.w400, height: 1.5, color: muted),
      labelLarge: textStyle(size: 20, weight: FontWeight.w600, color: onPrimaryText),
      labelMedium: textStyle(size: 18, weight: FontWeight.w600),
      labelSmall: textStyle(size: 16, weight: FontWeight.w500, color: muted),
    );
  }
}

// =====================================================================
// §通用扁平化组件（纯 Cupertino 场景下的补位）
// =====================================================================

/// 扁平卡片：无描边 + surfaceRaised 暖色填充，无阴影（基于 ShadCard）。
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
    this.padding = const EdgeInsets.all(20),
    this.margin = const EdgeInsets.symmetric(vertical: 6),
    this.color,
    this.radius,
    this.border,
    this.onTap,
  });

  /// 将 Flutter [Border] 转换为 [ShadBorder]（仅在调用方显式传 border 时使用）。
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
    final card = ShadCard(
      padding: padding,
      backgroundColor: color ?? app.surfaceContainerLow,
      radius: BorderRadius.circular(radius ?? AppRadius.card),
      border: border != null
          ? _convertBorder(border!)
          : ShadBorder.all(color: const Color(0x00000000), width: 0),
      shadows: const <BoxShadow>[],
      child: child,
    );
    return Container(
      margin: margin,
      child: onTap != null
          ? ShadButton.ghost(
              width: double.infinity,
              height: null,
              padding: EdgeInsets.zero,
              backgroundColor: const Color(0x00000000),
              hoverBackgroundColor: const Color(0x00000000),
              pressedBackgroundColor: const Color(0x00000000),
              decoration: const ShadDecoration(border: null),
              onPressed: onTap,
              child: card,
            )
          : card,
    );
  }
}

/// 主操作按钮：ShadButton 主变体（扁平、无阴影），供业务主 CTA 使用。
///
/// [icon] 存在时渲染「图标 + 文案」行；[loadingLabel] 仅在 [loading] 且有 [icon]
/// 时生效（如「判题中…」），缺省回退到 [label]。无 [icon] 时保持原行为
/// （loading 显示裸 spinner，否则纯文案）。
/// [fullWidth] 控制 [ShadButton.expands]：true 占满可用宽度（主 CTA / 保存），
/// false 按内容宽度（行内发送、表单内提交）。
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool fullWidth;
  final IconData? icon;
  final String? loadingLabel;
  final double height;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.fullWidth = true,
    this.icon,
    this.loadingLabel,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final spinner = Icon(
      LucideIcons.loaderCircle,
      size: 22,
      color: app.onPrimary,
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
            color: app.onPrimary,
          ),
    );
    final child = icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              loading ? spinner : Icon(icon, size: 20, color: app.onPrimary),
              const SizedBox(width: 8),
              labelWidget,
            ],
          )
        : (loading ? spinner : labelWidget);
    return ShadButton(
      height: height,
      expands: fullWidth,
      // loading 时 onPressed 置空以禁用点击，但保持 enabled（不触发半透明）
      onPressed: loading ? null : onPressed,
      child: child,
    );
  }
}

/// 线性进度条：基于 ShadProgress。
class AppProgressBar extends StatelessWidget {
  final double value; // 0.0 - 1.0
  final double height;
  final Color? color;
  final Color? trackColor;

  const AppProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.color,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return ShadProgress(
      value: value.clamp(0.0, 1.0),
      minHeight: height,
      color: color ?? app.primary,
      backgroundColor: trackColor ?? app.surfaceContainerHighest,
    );
  }
}

// =====================================================================
// §语义化组件（自动跟随亮/暗模式，取色一律来自 AppTheme）
// =====================================================================

/// 4 种语义化 Chip/Pill：基于 ShadBadge，避免全局 comparator 风格被误用，且兼容双主题。
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
}

enum _TagSemantics { normal, info, ai, success, warning }

class _TagChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final _TagSemantics semantics;
  const _TagChip({
    required this.label,
    required this.semantics,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final (bg, fg) = switch (semantics) {
      _TagSemantics.normal => (app.surfaceContainerHigh, app.onSurface),
      _TagSemantics.info => (app.primaryContainer, app.onPrimaryContainer),
      _TagSemantics.ai => (app.secondaryContainer, app.onSecondaryContainer),
      _TagSemantics.success => (app.tertiaryContainer, app.onTertiaryContainer),
      _TagSemantics.warning => (app.errorContainer, app.onErrorContainer),
    };

    return ShadBadge.raw(
      variant: ShadBadgeVariant.primary,
      backgroundColor: bg,
      foregroundColor: fg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppTheme.textOf(context).labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// 语义化 Badge（胶囊，基于 ShadBadge）。
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
      _BadgeSemantics.success => (app.tertiaryContainer, app.onTertiaryContainer),
      _BadgeSemantics.warning => (app.errorContainer, app.onErrorContainer),
      _BadgeSemantics.info => (app.primaryContainer, app.onPrimaryContainer),
    };

    return ShadBadge.raw(
      variant: ShadBadgeVariant.primary,
      backgroundColor: bg,
      foregroundColor: fg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: const StadiumBorder(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTheme.textOf(context).labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// 章节标题：左侧 4px 植物绿色条 + 标题文字
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 12),
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
            width: 4,
            height: 22,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: app.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(child: Text(text, style: style)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Squircle 方圆形头像（基于 ShadAvatar，替代俗套 CircleAvatar）。
/// 自动折行亮/暗配色。
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
  }) : size = 48;

  const AvatarSquircle.medium({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 72;

  const AvatarSquircle.large({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 104;

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
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// 间距统一令牌（8 倍网格）
class AppSpacing {
  static const double xs2 = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double xl2 = 32;
  static const double xl3 = 40;
  static const double xl4 = 48;
  static const double xl5 = 64;
}

/// 圆角令牌
class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double chip = 10;
  static const double button = 14;
  static const double input = 14;
  static const double bubble = 16;
  static const double card = 20;
  static const double banner = 24;
}