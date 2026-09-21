import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'subject_mark_icon.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

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

  /// 自定义前导件（学科 chip 传几何标记 [SubjectMarkIcon]）。优先于 [icon]。
  final Widget? leading;
  final String label;

  const _HoverPill({
    required this.bg,
    required this.fg,
    required this.shape,
    required this.padding,
    this.iconSize = 13,
    this.gap = 5,
    this.icon,
    this.leading,
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
                    if (leading != null) ...[
                      leading!,
                      SizedBox(width: gap),
                    ] else if (icon != null) ...[
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
    Widget? leading;
    ShapeBorder shape;
    if (subject != null) {
      final sc = SubjectAccent.forContext(subject!, context);
      // 学科 chip 属「小面积强调」，允许全填充。前景**必须**由 [AppBrutal.onColor]
      // 判定：数学蓝是深块配白字，语文珊瑚 / 英语黄是亮块配墨黑字——反过来就不过 AA。
      bg = sc.accent;
      fg = AppBrutal.onColor(sc.accent);
      leading = SubjectMarkIcon(mark: subject!.mark, color: fg, size: 9);
      // 英语黄在纸底上仅 1.38:1、语文珊瑚 2.71:1，不描边时 chip 边界不存在。
      shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
        side: const BorderSide(
            color: AppBrutal.ink, width: AppElevation.borderWidthSm),
      );
    } else {
      // 非学科 chip 同样要描边：nearest 底色是 surfaceSunken(#F2F0EA)，在白色卡面上
      // 对比约 1.09:1，不描边则标签边界不存在（与上面学科分支同一个理由，原先只给
      // 学科分支加了边，这里漏了）。
      shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
        side: const BorderSide(
            color: AppBrutal.ink, width: AppElevation.borderWidthSm),
      );
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
      shape: shape,
      iconSize: 13,
      gap: 4,
      icon: icon,
      leading: leading,
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
