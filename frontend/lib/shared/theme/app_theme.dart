import 'package:cupertino_ui/cupertino_ui.dart';

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

/// 护眼双主题（亮色 + 暗色 · 纯 Cupertino 设计系统 · 明快儿童化配色）。
///
/// 设计约定（见 .impeccable.md / copilot-instructions.md）：
/// - 亮色：护眼暖白背景 + 明快植物绿主强调（提亮饱和）+ 暖橙/天蓝次强调
/// - 暗色：暖调深炭（**禁用纯黑**）+ 提亮后的植物绿/暖橙/天蓝
/// - 三强调色方案：primary 植物绿主操作 / secondary 暖橙（AI 暖区）/ tertiary 天蓝（积极反馈）/ error 温柔珊瑚
/// - 正文 ≥ 20sp、选项 ≥ 22sp、辅助说明 ≥ 16sp、行高 ≥ 1.5
/// - 卡片 1px 描边 + 暖色填充（无重阴影）、大圆角
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
    surfaceContainerLowest: Color(0xFFFFFDF9),
    surfaceContainerLow: Color(0xFFFFFBF3),
    surfaceContainer: Color(0xFFFBF5E8),
    surfaceContainerHigh: Color(0xFFF4ECDA),
    surfaceContainerHighest: Color(0xFFEEE4CE),
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
    surfaceContainerLowest: Color(0xFF171512),
    surfaceContainerLow: Color(0xFF232019),
    surfaceContainer: Color(0xFF2A261F),
    surfaceContainerHigh: Color(0xFF322D25),
    surfaceContainerHighest: Color(0xFF3A342B),
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

/// 扁平卡片：1px 描边 + 暖色填充，无阴影（替代 Material Card）。
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

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? app.surfaceContainerLow,
        borderRadius: BorderRadius.all(
          Radius.circular(radius ?? AppRadius.card),
        ),
        border: border ??
            Border.all(
              color: app.outline,
              width: 1,
            ),
      ),
      child: child,
    );
    return Container(
      margin: margin,
      child: onTap != null
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              pressedOpacity: 0.8,
              onPressed: onTap,
              child: box,
            )
          : box,
    );
  }
}

/// 主操作按钮：纯 CupertinoButton.filled，扁平（无阴影）。
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool fullWidth;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return SizedBox(
      height: 56,
      child: fullWidth
          ? _inner(context, app)
          : Center(child: _inner(context, app)),
    );
  }

  Widget _inner(BuildContext context, AppColors app) {
    return CupertinoButton.filled(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      borderRadius: const BorderRadius.all(
        Radius.circular(AppRadius.button),
      ),
      disabledColor: app.surfaceContainerHighest,
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CupertinoActivityIndicator(radius: 11),
            )
          : Text(
              label,
              textAlign: TextAlign.center,
              style: AppTheme.textOf(context).labelLarge?.copyWith(
                    color: loading ? app.onSurfaceVariant : app.onPrimary,
                  ),
            ),
    );
  }
}

/// 扁平线性进度条（替代 Material LinearProgressIndicator）。
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: trackColor ?? app.surfaceContainerHighest),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color ?? app.primary,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// §语义化组件（自动跟随亮/暗模式，取色一律来自 AppTheme）
// =====================================================================

/// 4 种语义化 Chip/Pill：避免全局 comparator 风格被误用，且兼容双主题。
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
        icon: icon ?? CupertinoIcons.sparkles,
        semantics: _TagSemantics.ai,
      );

  static Widget success(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon ?? CupertinoIcons.checkmark_circle_fill,
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
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

/// 语义化 Badge（胶囊）。
class AppBadge {
  static Widget successChip(String label) => _BadgePill(
        label: label,
        icon: CupertinoIcons.checkmark,
        semantics: _BadgeSemantics.success,
      );

  static Widget warningChip(String label) => _BadgePill(
        label: label,
        icon: CupertinoIcons.exclamationmark_triangle,
        semantics: _BadgeSemantics.warning,
      );

  static Widget infoChip(String label) => _BadgePill(
        label: label,
        icon: CupertinoIcons.info,
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
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

/// Squircle 方圆形头像（替代俗套 CircleAvatar）。自动折行亮/暗配色。
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.all(Radius.circular(size * 0.32)),
        border: Border.all(
          color: app.outline,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
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