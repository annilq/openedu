import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../domain/models/courseware_section.dart';

/// 演示页的步骤条：环节横排，当前项实心高亮，可点直接跳（ADR-0067 §3.8）。
///
/// 教师点环节 2 是「切到这一环节」而不是「打开一个新页面」，所以切换发生在页内——
/// 步骤条只负责把「一共有几环节、现在在第几个」摊开，跳转由 [onSelect] 交回页面。
///
/// 选中语言只有一种（`.impeccable.md` §Interaction）：**无描边药丸 + `surfaceActive`
/// 填充**。不用带描边的卡片表示选中——那会在已经带描边的区域里再套一层盒子，把
/// 「选中」和「容器边界」混成同一种视觉。悬停是浅一档的 `surfaceHover`，由
/// [AppFocusableAction.hoverHighlight] 画在底层，会被选中项的自带底色盖住，
/// 两态天然分层。
class CoursewarePresentStepBar extends StatelessWidget {
  const CoursewarePresentStepBar({
    super.key,
    required this.sections,
    required this.index,
    required this.onSelect,
  });

  final List<CoursewareSectionModel> sections;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Container(
      decoration: BoxDecoration(
        color: app.surface,
        border: Border(
          bottom: BorderSide(
            color: app.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      // 环节多到一排放不下时横向滚动，而不是换行把主区挤没。
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              _buildChip(context, i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, int i) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final active = i == index;
    final section = sections[i];
    final title = section.title.isEmpty ? '第 ${i + 1} 环节' : section.title;
    return AppFocusableAction(
      onTap: () => onSelect(i),
      semanticLabel: '第 ${i + 1} 环节：$title',
      hoverHighlight: true,
      child: AnimatedContainer(
        // 隐式动画不自动尊重系统设置，必须显式归零（ADR-0044 原则 7）。
        duration: reducedMotionOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(minHeight: AppControl.heightSmOf(context)),
        decoration: BoxDecoration(
          color: active ? app.surfaceActive : const Color(0x00000000),
          borderRadius: BorderRadius.circular(AppRadius.chip),
          // 非选中才描边：选中是「无描边药丸」，靠填充表达。
          border: Border.all(
            color: active ? const Color(0x00000000) : app.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${i + 1}',
              style: text.labelMedium?.copyWith(
                color: active ? app.accent : app.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              title,
              style: text.labelMedium?.copyWith(
                color: app.onSurface,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
