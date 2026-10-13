import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../domain/figures.dart';
import '../theme/app_theme.dart';
import '../utils/option_text.dart';
import 'app_focusable_action.dart';
import 'app_motion.dart';
import 'scene_interpreter/reflection_figure_gallery.dart';
import 'scene_interpreter/reflection_scene_data.dart';
import 'scene_interpreter/reflection_scene_dialog.dart';

/// 选项卡片：字母圆圈 + 文案 + 选中描边/勾选。
///
/// 合并自 practice `_OptionTile` 与 review `_ReviewOptionTile`：统一用 [PressScale]
/// 作为按压反馈（项目手势标准），[disabled] 承载提交中禁用态（判题时不可改答）。
///
/// [figure] 非空时，选项右侧渲染该图形的行内缩略图；点图形（不点整卡）打开对折演示
/// 弹窗（ADR-0089-04）。整卡点按仍是「选该选项」，二者不冲突。
class AppOptionTile extends StatelessWidget {
  final int index;
  final String text;
  final bool selected;
  final VoidCallback? onTap;
  final bool disabled;

  /// 是否多选题（ADR-0004 D5）：True 时前导标记为方块复选框、False 为圆形单选框。
  /// 渲染差异只在前导形状与勾选图标语义，选中/描边逻辑与单选一致。
  final bool multi;

  /// 选项内嵌图形（ADR-0089-04）：非 null 时右侧渲染缩略图，点图形开演示。
  /// null = 纯文字选项，不渲染图形区。
  final FigureShape? figure;

  /// 点击图形缩略图的回调；null = 走默认行为（直接打开对折演示弹窗）。
  final VoidCallback? onFigureTap;

  const AppOptionTile({
    super.key,
    required this.index,
    required this.text,
    required this.selected,
    this.onTap,
    this.disabled = false,
    this.multi = false,
    this.figure,
    this.onFigureTap,
  });

  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final letter = index < _letters.length ? _letters[index] : '${index + 1}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: PressScale(
        onTap: disabled ? null : onTap,
        downScale: 0.975,
        child: AnimatedContainer(
          // 隐式动画不会自动尊重 reduce-motion（ADR-0044）：显式归零时长。
          duration: reducedMotionOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: selected ? scheme.semanticInfo : scheme.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.card),
            // 未选中态也必须有墨黑描边：surfaceRaised 是纯白，纸底是 #FDFBF7，
            // 两者对比仅 ~1.02——旧写法只在选中时描边，未选中时选项块在卡片上
            // 没有任何可见边界。新粗野的描边在此是功能必需，不是装饰。
            border: Border.all(
              color: scheme.outline,
              width: selected
                  ? AppElevation.borderWidth
                  : AppElevation.borderWidthSm,
            ),
            // 选中态用 2px 边 + 硬阴影做强调，刻意不整行填实心撞色：
            // 选项属「列表行」，ADR-0044 明令列表行禁止整行填充。
            boxShadow:
                selected ? AppElevation.hard(scheme.outline) : AppElevation.none,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : scheme.surfaceSunken,
                  // 多选=方块复选框、单选=圆形单选框（ADR-0004 D5）。
                  borderRadius: BorderRadius.circular(multi ? 8 : 999),
                  border: Border.all(
                    color: scheme.outline,
                    width: AppElevation.borderWidthSm,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  letter,
                  style: text.labelLarge?.copyWith(
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    this.text,
                    style: text.titleMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? scheme.semanticInfoFg
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: AppSpacing.md),
                  child: Icon(LucideIcons.checkCircle2,
                      color: scheme.primary, size: 24),
                ),
              if (figure != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: AppSpacing.md),
                  child: _OptionFigureThumb(
                    figure: figure!,
                    letter: letter,
                    onTap: onFigureTap,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选项行内图形缩略图（ADR-0089-04）：复用 [FigureThumbPainter] 画轮廓 + 初始轴，
/// 点图形打开对折演示弹窗。点图形**不**冒泡到整卡（[AppFocusableAction] 内层手势
/// 胜出），故不会顺带把选项选中。
class _OptionFigureThumb extends StatelessWidget {
  final FigureShape figure;
  final String letter;
  final VoidCallback? onTap;

  const _OptionFigureThumb({
    required this.figure,
    required this.letter,
    this.onTap,
  });

  void _openDemo(BuildContext context) {
    ReflectionSceneDialog.show(
      context,
      data: ReflectionSceneData(
        points: <Offset>[
          for (final v in figure.vertices) Offset(v.x, v.y),
        ],
        edges: figure.edges,
        figureLabel: cleanOptionText(figure.label),
      ),
      optionLabel: letter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    const size = 56.0;
    final thumb = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: app.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppBrutal.ink,
          width: AppElevation.borderWidthSm,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: FigureThumbPainter(
          points: figure.vertices
              .map((v) => Offset(v.x, v.y))
              .toList(growable: false),
          axisAngle: 90,
        ),
      ),
    );
    if (onTap == null) {
      return AppFocusableAction(
        onTap: () => _openDemo(context),
        semanticLabel: '播放${cleanOptionText(figure.label)}的对折演示',
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: _thumbWithBadge(thumb),
      );
    }
    return AppFocusableAction(
      onTap: onTap,
      semanticLabel: '播放${cleanOptionText(figure.label)}的对折演示',
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: _thumbWithBadge(thumb),
    );
  }

  Widget _thumbWithBadge(Widget thumb) => Stack(
        children: [
          thumb,
          Positioned(
            top: 3,
            right: 3,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppBrutal.blue,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(
                  color: AppBrutal.ink,
                  width: AppElevation.borderWidthHairline,
                ),
              ),
              child: const Icon(LucideIcons.play, size: 10, color: AppBrutal.onDark),
            ),
          ),
        ],
      );
}
