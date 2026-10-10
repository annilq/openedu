part of 'scene_library_detail_view.dart';

/// 场景库「默认演示图形」配置区（ADR-0074 T03）。
///
/// 教师在这里挑一个图形设为该 kind 的默认：新关联的知识点按它初始化讲解图形，
/// **已关联的知识点不受影响**（绝不回写 `kp.scenes`，ADR-0073 快照不可变）。
/// 画廊复用 [ReflectionFigureGallery]，选中的那张卡标「默认讲解」徽标。
class _DefaultFigureSection extends ConsumerStatefulWidget {
  final String kind;
  final String? defaultFigureKey;

  const _DefaultFigureSection({
    required this.kind,
    this.defaultFigureKey,
  });

  @override
  ConsumerState<_DefaultFigureSection> createState() =>
      _DefaultFigureSectionState();
}

class _DefaultFigureSectionState extends ConsumerState<_DefaultFigureSection> {
  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('默认演示图形', style: text.titleSmall)),
            if (widget.defaultFigureKey != null)
              AppTextAction(
                label: '清除默认',
                onPressed: () => _set(null),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '新关联的知识点按此默认图形初始化讲解；已关联的知识点不受影响。',
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        // 图库**按需拉取**（ADR-0083 决策 7）：打开就 GET 一次、会话内复用、不落盘。
        FigureLibraryGallery(
          selectedKey: widget.defaultFigureKey,
          hint: '点一个图形设为该场景的默认演示图形',
          onOpen: (figure) => _set(figure.key),
        ),
      ],
    );
  }

  Future<void> _set(String? figureKey) async {
    try {
      await ref
          .read(materialRepositoryProvider)
          .saveSceneDefaultFigure(kind: widget.kind, figureKey: figureKey);
      // 刷新场景库清单，让画廊选中态与「清除默认」入口跟随新值。
      ref.invalidate(sceneLibraryProvider);
      if (!mounted) return;
      if (figureKey == null) {
        AppToast.show(context, '已清除默认图形');
      } else {
        AppToast.show(context, '已设为默认图形：${figureByKey(figureKey).label}');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '设置失败：$e');
    }
  }
}
