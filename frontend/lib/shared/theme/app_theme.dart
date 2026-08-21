import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 按正确率分级的视觉情绪。
///
/// 用于做题完成页的图标容器配色，以植物绿暖色系为基础，
/// 不引入红/黄/蓝等新色相。
enum ResultTone { positive, warm, alert, neutral }

/// 护眼双主题（亮色 + 暗色 · redesign 升级）。
///
/// 设计约定（见 .impeccable.md / copilot-instructions.md）：
/// - 亮色：低饱和暖白背景 + 植物绿单强调色
/// - 暗色：暖调深炭（**禁用纯黑**）+ 植物绿强调色
/// - 单强调色方案：primary 主操作 / secondary AI 暖区（琥珀）/ tertiary 积极反馈 / error 温柔珊瑚
/// - 正文 ≥ 20sp、选项 ≥ 22sp、辅助说明 ≥ 16sp、行高 ≥ 1.5
/// - 卡片 1px 描边 + 暖色填充（无重阴影）、大圆角
/// - 字体：HarmonyOS Sans SC / Noto Sans SC 回退链
///
/// 业务代码中请一律使用 `Theme.of(context).colorScheme.* / textTheme.*`，
/// 或调用本文件下方的语义化组件（AppTags、AppBadge、AvatarSquircle 等）。
/// 语义化组件会自动跟随亮/暗模式。
class AppTheme {
  // ============ §1 亮色色彩令牌 ============
  static const Color primary = Color(0xFF5B8C5A); // Botanical Green
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFE8F0E7);
  static const Color onPrimaryContainer = Color(0xFF1F3A26);

  static const Color secondary = Color(0xFFB5894A); // 柔和琥珀（AI 语义）
  static const Color secondaryContainer = Color(0xFFFBF0DB);
  static const Color onSecondaryContainer = Color(0xFF3A2A10);

  static const Color tertiary = Color(0xFF6FA06E);
  static const Color tertiaryContainer = Color(0xFFDDEBDB);
  static const Color onTertiaryContainer = Color(0xFF24402A);

  static const Color error = Color(0xFFD97757); // 温柔珊瑚
  static const Color errorContainer = Color(0xFFFBE4DA);
  static const Color onErrorContainer = Color(0xFF3E1A10);

  static const Color surface = Color(0xFFFDF8F0); // Warm Canvas 主背景
  static const Color onSurface = Color(0xFF2D2D2D); // Charcoal Ink 主文字
  static const Color surfaceContainerLowest = Color(0xFFFFFDF9);
  static const Color surfaceContainerLow = Color(0xFFFFFBF3);
  static const Color surfaceContainer = Color(0xFFFBF5E8);
  static const Color surfaceContainerHigh = Color(0xFFF4ECDA);
  static const Color surfaceContainerHighest = Color(0xFFEEE4CE);
  static const Color onSurfaceVariant = Color(0xFF7A7368); // Muted Stone 次文字
  static const Color outline = Color(0xFFEFE7D8); // Whisper Border
  static Color get outlineVariant => outline.withValues(alpha: 0.6);

  // ============ §2 暗色色彩令牌（暖调深炭，非纯黑）============
  static const Color darkPrimary = Color(0xFF7FBA7E); // 深底用提亮后的植物绿
  static const Color darkOnPrimary = Color(0xFF0E2E14);
  static const Color darkPrimaryContainer = Color(0xFF26451F);
  static const Color darkOnPrimaryContainer = Color(0xFFD0E5CB);

  static const Color darkSecondary = Color(0xFFD0A25A);
  static const Color darkOnSecondary = Color(0xFF2A1A00);
  static const Color darkSecondaryContainer = Color(0xFF4A3A12);
  static const Color darkOnSecondaryContainer = Color(0xFFF6E3BB);

  static const Color darkTertiary = Color(0xFF8FB98D);
  static const Color darkOnTertiary = Color(0xFF12301A);
  static const Color darkTertiaryContainer = Color(0xFF33562F);
  static const Color darkOnTertiaryContainer = Color(0xFFD7E8D0);

  static const Color darkError = Color(0xFFE5A390);
  static const Color darkOnError = Color(0xFF3A1206);
  static const Color darkErrorContainer = Color(0xFF61301F);
  static const Color darkOnErrorContainer = Color(0xFFFBE4DA);

  static const Color darkSurface = Color(0xFF1D1B17); // 暖调深炭主背景
  static const Color darkOnSurface = Color(0xFFEDE6D8);
  static const Color darkSurfaceContainerLowest = Color(0xFF171512);
  static const Color darkSurfaceContainerLow = Color(0xFF232019);
  static const Color darkSurfaceContainer = Color(0xFF2A261F);
  static const Color darkSurfaceContainerHigh = Color(0xFF322D25);
  static const Color darkSurfaceContainerHighest = Color(0xFF3A342B);
  static const Color darkOnSurfaceVariant = Color(0xFFBFB6A8);
  static const Color darkOutline = Color(0xFF4A4438);
  static Color get darkOutlineVariant => darkOutline.withValues(alpha: 0.7);

  // ============ §3 字体与圆角 ============
  static const String fontFamily = 'HarmonyOS_Sans_SC';

  /// 统一的字体排版。字号/行高与亮暗无关，行内颜色用传入的语义色传入。
  static TextTheme _textTheme({
    required Color base,
    required Color muted,
    required Color onPrimaryText,
  }) {
    return TextTheme(
      displayLarge: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 40,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        height: 1.15,
      ).copyWith(color: base),
      displayMedium: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.2,
      ).copyWith(color: base),
      headlineLarge: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.25,
      ).copyWith(color: base),
      headlineMedium: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.3,
      ).copyWith(color: base),
      headlineSmall: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
      ).copyWith(color: base),
      titleLarge: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.35,
      ).copyWith(color: base),
      titleMedium: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        height: 1.4,
      ).copyWith(color: base),
      titleSmall: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ).copyWith(color: base),
      bodyLarge: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w400,
        height: 1.55,
      ).copyWith(color: base),
      bodyMedium: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.55,
      ).copyWith(color: base),
      bodySmall: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ).copyWith(color: muted),
      labelLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: onPrimaryText,
      ),
      labelMedium: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ).copyWith(color: base),
      labelSmall: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.3,
      ).copyWith(color: muted),
    );
  }

  static ThemeData get light => _build(
        brightness: Brightness.light,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: Colors.white,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: Colors.white,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: Colors.white,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        onSurface: onSurface,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        primary: darkPrimary,
        onPrimary: darkOnPrimary,
        primaryContainer: darkPrimaryContainer,
        onPrimaryContainer: darkOnPrimaryContainer,
        secondary: darkSecondary,
        onSecondary: darkOnSecondary,
        secondaryContainer: darkSecondaryContainer,
        onSecondaryContainer: darkOnSecondaryContainer,
        tertiary: darkTertiary,
        onTertiary: darkOnTertiary,
        tertiaryContainer: darkTertiaryContainer,
        onTertiaryContainer: darkOnTertiaryContainer,
        error: darkError,
        onError: darkOnError,
        errorContainer: darkErrorContainer,
        onErrorContainer: darkOnErrorContainer,
        surface: darkSurface,
        onSurface: darkOnSurface,
        surfaceContainerLowest: darkSurfaceContainerLowest,
        surfaceContainerLow: darkSurfaceContainerLow,
        surfaceContainer: darkSurfaceContainer,
        surfaceContainerHigh: darkSurfaceContainerHigh,
        surfaceContainerHighest: darkSurfaceContainerHighest,
        onSurfaceVariant: darkOnSurfaceVariant,
        outline: darkOutline,
        outlineVariant: darkOutlineVariant,
      );

  /// 统一构建亮/暗主题：组件与配色全部引用传入的 [scheme]，保证不越界。
  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color onPrimary,
    required Color primaryContainer,
    required Color onPrimaryContainer,
    required Color secondary,
    required Color onSecondary,
    required Color secondaryContainer,
    required Color onSecondaryContainer,
    required Color tertiary,
    required Color onTertiary,
    required Color tertiaryContainer,
    required Color onTertiaryContainer,
    required Color error,
    required Color onError,
    required Color errorContainer,
    required Color onErrorContainer,
    required Color surface,
    required Color onSurface,
    required Color surfaceContainerLowest,
    required Color surfaceContainerLow,
    required Color surfaceContainer,
    required Color surfaceContainerHigh,
    required Color surfaceContainerHighest,
    required Color onSurfaceVariant,
    required Color outline,
    required Color outlineVariant,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      error: error,
      onError: onError,
      errorContainer: errorContainer,
      onErrorContainer: onErrorContainer,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerLowest: surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      shadow: brightness == Brightness.light
          ? const Color(0x24000000)
          : const Color(0x3D000000),
      scrim: const Color(0x66000000),
      inverseSurface: brightness == Brightness.light
          ? darkOnSurface
          : onSurface,
      onInverseSurface: brightness == Brightness.light
          ? darkSurface
          : surface,
      inversePrimary: brightness == Brightness.light
          ? primaryContainer
          : primaryContainer,
      surfaceTint: primary,
    );

    final textTheme = _textTheme(
      base: onSurface,
      muted: onSurfaceVariant,
      onPrimaryText: onPrimary,
    );

    // —— 圆角令牌副本 ——
    const cardRadius = Radius.circular(AppRadius.card);
    const bannerRadius = Radius.circular(AppRadius.banner);
    const btnRadius = Radius.circular(AppRadius.button);
    const inputRadius = Radius.circular(AppRadius.input);
    const chipRadius = Radius.circular(AppRadius.chip);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: textTheme,
      primaryColor: primary,

      // —— 背景 & 分割 ——
      scaffoldBackgroundColor: surface,
      dividerColor: outline,
      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 1,
        space: 24,
      ),

      // —— 全局动画 / 水波纹：统一用强调色，避免暗色下高亮刺眼 ——
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: OpenUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      splashFactory: InkSparkle.splashFactory,
      splashColor: primary.withValues(alpha: 0.08),
      highlightColor: primary.withValues(alpha: 0.04),

      // —— 卡片：1px 边 + 0 阴影 ——
      cardTheme: CardThemeData(
        color: surfaceContainerLow,
        elevation: 0,
        shadowColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(cardRadius),
          side: BorderSide(color: outline, width: 1),
        ),
      ),

      // —— AppBar ——
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        toolbarHeight: 64,
        iconTheme: IconThemeData(color: primary, size: 26),
        actionsIconTheme: IconThemeData(color: onSurfaceVariant, size: 26),
      ),

      // —— 填充按钮（主按钮）——
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(88, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: surfaceContainerHighest,
          disabledForegroundColor: onSurfaceVariant,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(btnRadius),
          ),
        ).copyWith(elevation: const WidgetStatePropertyAll(0)),
      ),

      // —— 轮廓按钮 ——
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(88, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          backgroundColor: surfaceContainerLow,
          foregroundColor: onSurface,
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(btnRadius),
            side: BorderSide(color: outline, width: 1),
          ),
          disabledBackgroundColor: surfaceContainerLow,
          disabledForegroundColor: onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),

      // —— 文本按钮 ——
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
        ),
      ),

      // —— 输入框 ——
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: textTheme.bodyMedium?.copyWith(color: onSurfaceVariant),
        labelStyle: textTheme.bodyMedium?.copyWith(color: onSurfaceVariant),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(color: primary),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: error),
        prefixIconColor: onSurfaceVariant,
        suffixIconColor: onSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(inputRadius),
          borderSide: BorderSide(color: outline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(inputRadius),
          borderSide: BorderSide(color: outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(inputRadius),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(inputRadius),
          borderSide: BorderSide(color: error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(inputRadius),
          borderSide: BorderSide(color: error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(inputRadius),
          borderSide: BorderSide(color: outlineVariant, width: 1),
        ),
      ),

      // —— Chip ——
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainerHigh,
        selectedColor: primaryContainer,
        disabledColor: surfaceContainer,
        labelStyle: textTheme.labelSmall?.copyWith(color: onSurface),
        secondaryLabelStyle:
            textTheme.labelSmall?.copyWith(color: onPrimaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(chipRadius),
        ),
        side: BorderSide.none,
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        iconTheme: const IconThemeData(size: 16),
      ),

      // —— 下拉菜单 ——
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surfaceContainerLow),
          elevation: const WidgetStatePropertyAll(2),
          shadowColor: WidgetStatePropertyAll(
            onSurface.withValues(alpha: 0.06),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              side: BorderSide(color: outline, width: 1),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 8),
          ),
        ),
        textStyle: textTheme.bodyMedium,
      ),

      // —— 图标 & ListTile ——
      iconTheme: IconThemeData(color: primary, size: 24, opticalSize: 24),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        textColor: onSurface,
        minVerticalPadding: 12,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // —— AlertDialog ——
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(bannerRadius),
          side: BorderSide(color: outline, width: 1),
        ),
        alignment: Alignment.center,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      ),

      // —— SnackBar ——
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        elevation: 4,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        closeIconColor: scheme.onInverseSurface,
        showCloseIcon: true,
      ),

      // —— 进度条 ——
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: surfaceContainerHighest,
        linearMinHeight: 8,
        circularTrackColor: surfaceContainerHighest,
        refreshBackgroundColor: surfaceContainerLow,
      ),

      // —— SegmentedButton ——
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: surfaceContainerLow,
          foregroundColor: onSurface,
          selectedBackgroundColor: primaryContainer,
          selectedForegroundColor: onPrimaryContainer,
          disabledBackgroundColor: surfaceContainer,
          disabledForegroundColor: onSurfaceVariant,
          side: BorderSide(color: outline, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(btnRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: textTheme.labelMedium,
        ),
      ),

      // —— 选择框 / 单选 ——
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(onPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: outline, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return primary;
          return onSurfaceVariant;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : onSurfaceVariant),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? primaryContainer
                : surfaceContainerHighest),
      ),
    );
  }
}

// =====================================================================
// §语义化组件（自动跟随亮/暗模式，取色一律来自 Theme.of(context)）
// =====================================================================

/// 4 种语义化 Chip/Pill：避免全局 chipTheme 被误用，且兼容双主题。
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
        icon: icon ?? Icons.auto_awesome_rounded,
        semantics: _TagSemantics.ai,
      );

  static Widget success(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon ?? Icons.check_circle_rounded,
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
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (semantics) {
      _TagSemantics.normal => (scheme.surfaceContainerHigh, scheme.onSurface),
      _TagSemantics.info => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _TagSemantics.ai => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _TagSemantics.success => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _TagSemantics.warning => (scheme.errorContainer, scheme.onErrorContainer),
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
        icon: Icons.check_rounded,
        semantics: _BadgeSemantics.success,
      );

  static Widget warningChip(String label) => _BadgePill(
        label: label,
        icon: Icons.warning_amber_rounded,
        semantics: _BadgeSemantics.warning,
      );

  static Widget infoChip(String label) => _BadgePill(
        label: label,
        icon: Icons.info_outline_rounded,
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
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (semantics) {
      _BadgeSemantics.success => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _BadgeSemantics.warning => (scheme.errorContainer, scheme.onErrorContainer),
      _BadgeSemantics.info => (scheme.primaryContainer, scheme.onPrimaryContainer),
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
    final color = Theme.of(context).colorScheme.primary;
    final style = Theme.of(context).textTheme.titleMedium;
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
              color: color,
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
    final scheme = Theme.of(context).colorScheme;
    final background = bg ?? scheme.primaryContainer;
    final foreground = fg ?? scheme.onPrimaryContainer;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.all(Radius.circular(size * 0.32)),
        border: Border.all(
          color: scheme.outline,
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