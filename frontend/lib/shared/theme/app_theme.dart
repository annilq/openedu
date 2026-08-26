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

/// Linear 风格主题（亮色 + 暗色 · 中性灰白 + 靛蓝强调）。
///
/// 设计约定（见 .impeccable.md / ADR-0003）：
/// - surface 微暖白、卡片纯白 + 1px 极细描边、无阴影
/// - accent 靛蓝用于 selection/focus/progress/link；CTA 近黑底白字
/// - 语义色降饱和（极淡绿/琥珀/红/靛蓝底）
/// - Inter 西文/数字 + HarmonyOS Sans SC CJK 回退
/// - 密排字号 15sp 基线，双端共用
class AppTheme {
  const AppTheme._();

  /// Inter 为西文/数字主字体，CJK 自动回退 HarmonyOS Sans SC。
  /// 变量字体打包于 assets/fonts/Inter.ttf，pubspec.yaml 已声明。
  static const String fontFamily = 'Inter';
  static const List<String> fontFamilyFallback = [
    'HarmonyOS Sans SC',
    'Noto Sans SC',
  ];

  /// 亮色令牌（中性灰白 + 靛蓝）。
  static const AppColors light = AppColors(
    brightness: Brightness.light,
    // CTA 近黑底白字
    primary: Color(0xFF1D1B17),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEDEDF0),
    onPrimaryContainer: Color(0xFF1D1B17),
    // 中性灰次强调
    secondary: Color(0xFF6B7280),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFAF3E8), // 语义·warning 底
    onSecondaryContainer: Color(0xFF8A6D1F),
    // positive 语义
    tertiary: Color(0xFF3B7A2D),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFEFF5EC), // 语义·positive 底
    onTertiaryContainer: Color(0xFF3B7A2D),
    // error 语义
    error: Color(0xFFB91C1C),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFCE8E6), // 语义·error 底
    onErrorContainer: Color(0xFFB91C1C),
    // Surface 层次
    surface: Color(0xFFFBFAFA), // 内容区微暖白
    onSurface: Color(0xFF1D1B17),
    surfaceContainerLowest: Color(0xFFFFFFFF), // = surfaceRaised
    surfaceContainerLow: Color(0xFFFFFFFF), // = surfaceRaised（卡片）
    surfaceContainer: Color(0xFFF4F4F2), // = surfaceSunken（侧栏）
    surfaceContainerHigh: Color(0xFFF4F4F2), // = surfaceSunken
    surfaceContainerHighest: Color(0xFFEDEDF0), // = surfaceActive
    onSurfaceVariant: Color(0xFF6B7280),
    outline: Color(0xFFECECEA), // 极细描边
    outlineVariant: Color(0xFFECECEA),
    inverseSurface: Color(0xFF1D1B17),
    onInverseSurface: Color(0xFFF5F5F4),
    // 新增：靛蓝强调 + hover
    accent: Color(0xFF5E6AD2),
    onAccent: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFF4F4F2),
    outlineHover: Color(0xFFD1D1CE),
    // info 语义（靛蓝系）
    infoContainer: Color(0xFFEEF0FC),
    onInfoContainer: Color(0xFF4338CA),
  );

  /// 暗色令牌（暖中性深炭 + 靛蓝提亮）。
  static const AppColors dark = AppColors(
    brightness: Brightness.dark,
    primary: Color(0xFFF5F5F4), // 暗底 CTA 反色
    onPrimary: Color(0xFF0F0F0E),
    primaryContainer: Color(0xFF2A2A28), // active 药丸
    onPrimaryContainer: Color(0xFFF5F5F4),
    secondary: Color(0xFF9CA3AF),
    onSecondary: Color(0xFF0F0F0E),
    secondaryContainer: Color(0xFF2E2618), // 语义·warning 底
    onSecondaryContainer: Color(0xFFD4A82E),
    tertiary: Color(0xFF86C060),
    onTertiary: Color(0xFF0F0F0E),
    tertiaryContainer: Color(0xFF1A2E1A), // 语义·positive 底
    onTertiaryContainer: Color(0xFF86C060),
    error: Color(0xFFF08888),
    onError: Color(0xFF0F0F0E),
    errorContainer: Color(0xFF2E1A1A), // 语义·error 底
    onErrorContainer: Color(0xFFF08888),
    surface: Color(0xFF0F0F0E), // 内容区暖中性深炭
    onSurface: Color(0xFFF5F5F4),
    surfaceContainerLowest: Color(0xFF161615),
    surfaceContainerLow: Color(0xFF161615), // = surfaceRaised
    surfaceContainer: Color(0xFF1A1A19), // = surfaceSunken
    surfaceContainerHigh: Color(0xFF1A1A19), // = surfaceSunken
    surfaceContainerHighest: Color(0xFF2A2A28), // = surfaceActive
    onSurfaceVariant: Color(0xFF9CA3AF),
    outline: Color(0xFF2A2A28),
    outlineVariant: Color(0xFF2A2A28),
    inverseSurface: Color(0xFFF5F5F4),
    onInverseSurface: Color(0xFF0F0F0E),
    accent: Color(0xFF7B82EA),
    onAccent: Color(0xFF0F0F0E),
    surfaceHover: Color(0xFF242423),
    outlineHover: Color(0xFF3D3D3A),
    infoContainer: Color(0xFF1A1A2E),
    onInfoContainer: Color(0xFF9BA0E8),
  );

  static bool isDarkOf(BuildContext context) {
    return CupertinoTheme.brightnessOf(context) == Brightness.dark;
  }

  static AppColors colorsOf(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return isDark ? dark : light;
  }

  static final AppText _lightText = AppText._build(light);
  static final AppText _darkText = AppText._build(dark);

  static AppText textOf(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return isDark ? _darkText : _lightText;
  }

  // ============ Cupertino 主题 ============

  static CupertinoThemeData get cupertinoLight => _cupertino(light);
  static CupertinoThemeData get cupertinoDark => _cupertino(dark);

  static CupertinoThemeData cupertinoFor(bool isDark) =>
      _cupertino(isDark ? dark : light);

  static ShadThemeData shadFor(bool isDark) =>
      shadThemeData(isDark ? dark : light);

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
      ring: c.accent,
      selection: c.accent,
      custom: {
        'accent': c.accent,
        'onAccent': c.onAccent,
        'cta': c.primary,
        'onCta': c.onPrimary,
        'surfaceHover': c.surfaceHover,
        'outlineHover': c.outlineHover,
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
      },
    );

    const transparent = Color(0x00000000);

    ShadButtonTheme button(Color bg, Color fg) => ShadButtonTheme(
          backgroundColor: bg,
          foregroundColor: fg,
          hoverBackgroundColor: bg,
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
      textTheme: _shadTextTheme(c),
      disabledOpacity: 0.5,
      primaryButtonTheme: button(c.primary, c.onPrimary),
      secondaryButtonTheme: button(c.secondaryContainer, c.onSecondaryContainer),
      destructiveButtonTheme: button(c.error, c.onError),
      outlineButtonTheme: ShadButtonTheme(
        backgroundColor: transparent,
        foregroundColor: c.onSurface,
        hoverBackgroundColor: c.surfaceHover,
        pressedBackgroundColor: c.surfaceHover,
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
        pressedBackgroundColor: c.surfaceHover,
      ),
      linkButtonTheme: ShadButtonTheme(
        backgroundColor: transparent,
        foregroundColor: c.accent,
        textDecoration: TextDecoration.underline,
      ),
      primaryBadgeTheme: badge(c.infoContainer, c.onInfoContainer),
      secondaryBadgeTheme: badge(c.secondaryContainer, c.onSecondaryContainer),
      destructiveBadgeTheme: badge(c.errorContainer, c.onErrorContainer),
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
        border: ShadBorder.all(color: c.outline, width: 1),
        radius: const BorderRadius.all(Radius.circular(AppRadius.card)),
        padding: const EdgeInsets.all(AppSpacing.xl),
        shadows: const <BoxShadow>[],
      ),
      progressTheme: ShadProgressTheme(
        backgroundColor: c.surfaceContainerHighest,
        color: c.accent,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        minHeight: 6,
      ),
      inputTheme: ShadInputTheme(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: ShadDecoration(
          disableSecondaryBorder: true,
          color: c.surfaceContainerLow,
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
    );
  }

  /// 密排排版 → ShadTextTheme（15sp 基线）。
  static ShadTextTheme _shadTextTheme(AppColors c) {
    TextStyle style({
      required double size,
      required FontWeight weight,
      double height = 1.4,
      double spacing = 0,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? c.onSurface,
      );
    }

    return ShadTextTheme(
      family: fontFamily,
      h1Large: style(size: 22, weight: FontWeight.w700, height: 1.2, spacing: -0.6),
      h1: style(size: 20, weight: FontWeight.w700, height: 1.2, spacing: -0.4),
      h2: style(size: 18, weight: FontWeight.w600, height: 1.25, spacing: -0.3),
      h3: style(size: 17, weight: FontWeight.w600, height: 1.3, spacing: -0.2),
      h4: style(size: 16, weight: FontWeight.w600, height: 1.3, spacing: -0.1),
      p: style(size: 15, weight: FontWeight.w400, height: 1.5),
      blockquote: style(size: 15, weight: FontWeight.w400, height: 1.5, color: c.onSurfaceVariant),
      table: style(size: 14, weight: FontWeight.w600, height: 1.4),
      list: style(size: 15, weight: FontWeight.w400, height: 1.5),
      lead: style(size: 17, weight: FontWeight.w500, height: 1.4),
      large: style(size: 16, weight: FontWeight.w600, height: 1.4),
      small: style(size: 13, weight: FontWeight.w500, height: 1.4, spacing: 0.2),
      muted: style(size: 13, weight: FontWeight.w400, height: 1.45, spacing: 0.2, color: c.onSurfaceVariant),
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
  final Color outlineVariant;

  final Color inverseSurface;
  final Color onInverseSurface;

  // 新增：靛蓝强调 + hover + info 语义
  final Color accent;
  final Color onAccent;
  final Color surfaceHover;
  final Color outlineHover;
  final Color infoContainer;
  final Color onInfoContainer;

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
    required this.accent,
    required this.onAccent,
    required this.surfaceHover,
    required this.outlineHover,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  /// 浮起表面（卡片/容器背景）。
  Color get surfaceRaised => surfaceContainerLow;

  /// 下沉表面（侧栏/凹槽/弱化背景）。
  Color get surfaceSunken => surfaceContainerHigh;

  /// 选中态表面。
  Color get surfaceActive => surfaceContainerHighest;
}

// =====================================================================
// §排版令牌（密排 15sp 基线）
// =====================================================================

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
    const ff = AppTheme.fontFamily;
    const ffb = AppTheme.fontFamilyFallback;
    final base = c.onSurface;
    final muted = c.onSurfaceVariant;
    final onCta = c.onPrimary;

    TextStyle textStyle({
      required double size,
      required FontWeight weight,
      double height = 1.35,
      double spacing = 0,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: ff,
        fontFamilyFallback: ffb,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? base,
      );
    }

    return AppText(
      displayLarge: textStyle(size: 22, weight: FontWeight.w700, height: 1.2, spacing: -0.6),
      displayMedium: textStyle(size: 20, weight: FontWeight.w700, height: 1.2, spacing: -0.4),
      headlineLarge: textStyle(size: 18, weight: FontWeight.w600, height: 1.25, spacing: -0.3),
      headlineMedium: textStyle(size: 17, weight: FontWeight.w600, height: 1.3, spacing: -0.2),
      headlineSmall: textStyle(size: 16, weight: FontWeight.w600, height: 1.3, spacing: -0.1),
      titleLarge: textStyle(size: 16, weight: FontWeight.w600, height: 1.35, spacing: -0.1),
      titleMedium: textStyle(size: 15, weight: FontWeight.w600, height: 1.35),
      titleSmall: textStyle(size: 15, weight: FontWeight.w600, height: 1.35),
      bodyLarge: textStyle(size: 15, weight: FontWeight.w400, height: 1.5),
      bodyMedium: textStyle(size: 14, weight: FontWeight.w400, height: 1.45),
      bodySmall: textStyle(size: 13, weight: FontWeight.w400, height: 1.45, spacing: 0.2, color: muted),
      labelLarge: textStyle(size: 14, weight: FontWeight.w600, height: 1.35, spacing: 0.2, color: onCta),
      labelMedium: textStyle(size: 13, weight: FontWeight.w600, height: 1.35, spacing: 0.3),
      labelSmall: textStyle(size: 12, weight: FontWeight.w500, height: 1.35, spacing: 0.3, color: muted),
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
    this.padding = const EdgeInsets.all(16),
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
    final card = ShadCard(
      padding: padding,
      backgroundColor: color ?? app.surfaceContainerLow,
      radius: BorderRadius.circular(radius ?? AppRadius.card),
      border: border != null
          ? _convertBorder(border!)
          : ShadBorder.all(color: app.outline, width: 1),
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

/// 主操作按钮：近黑底白字 CTA。
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
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final spinner = Icon(
      LucideIcons.loaderCircle,
      size: 18,
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
              loading ? spinner : Icon(icon, size: 16, color: app.onPrimary),
              const SizedBox(width: 8),
              labelWidget,
            ],
          )
        : (loading ? spinner : labelWidget);
    return ShadButton(
      height: height,
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
      _TagSemantics.info => (app.infoContainer, app.onInfoContainer),
      _TagSemantics.ai => (app.secondaryContainer, app.onSecondaryContainer),
      _TagSemantics.success => (app.tertiaryContainer, app.onTertiaryContainer),
      _TagSemantics.warning => (app.errorContainer, app.onErrorContainer),
    };

    return ShadBadge.raw(
      variant: ShadBadgeVariant.primary,
      backgroundColor: bg,
      foregroundColor: fg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
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
      _BadgeSemantics.success => (app.tertiaryContainer, app.onTertiaryContainer),
      _BadgeSemantics.warning => (app.errorContainer, app.onErrorContainer),
      _BadgeSemantics.info => (app.infoContainer, app.onInfoContainer),
    };

    return ShadBadge.raw(
      variant: ShadBadgeVariant.primary,
      backgroundColor: bg,
      foregroundColor: fg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      shape: const StadiumBorder(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
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

/// 章节标题：左侧 3px 靛蓝色条 + 标题文字
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 16, 4, 10),
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

/// 间距令牌（8 倍网格，密排缩减）
class AppSpacing {
  static const double xs2 = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xl2 = 32;
  static const double xl3 = 40;
  static const double xl4 = 48;
  static const double xl5 = 56;
}

/// 圆角令牌（密排缩减）
class AppRadius {
  static const double xs = 4;
  static const double sm = 6;
  static const double chip = 8;
  static const double button = 10;
  static const double input = 10;
  static const double bubble = 12;
  static const double card = 12;
  static const double banner = 16;
}

/// 转场时长令牌
class AppMotion {
  static const Duration interaction = Duration(milliseconds: 120);
  static const Duration state = Duration(milliseconds: 200);
  static const Duration page = Duration(milliseconds: 300);
}
