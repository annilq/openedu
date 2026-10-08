import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_checkbox.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../providers/knowledge_manage_provider.dart';

/// 知识点目录里的一行：勾选 + 名称 + 状态 + 「课件」行内入口。
///
/// 从 [MaterialKnowledgeManageView] 拆出来是为守 ADR-0058 的 400 行上限——主视图把每行
/// 渲染内联会把文件推过线。行内的「课件」入口把整行对应的知识点抛给父级，由父级负责
/// push 课件编辑器（导航归一处，避免散落多处写 push）。
///
/// 讲解入口已不再出现在本行：经 ADR-0074 v4，知识点与场景的关联、标题编辑都收拢到
/// 场景库详情页（关联知识点 → 点开即编辑），本行只保留「课件」这一导航动作。
class KnowledgePointRow extends ConsumerWidget {
  const KnowledgePointRow({
    super.key,
    required this.kp,
    required this.km,
    required this.onOpenCourseware,
  });

  /// 元素的静态类型由 [knowledgeManageProvider] 暴露的 [KnowledgeManageState] 决定，
  /// 这里不显式 import `data/` 层（R4）。
  final dynamic kp;
  final dynamic km;
  final void Function(dynamic kp) onOpenCourseware;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final notifier = ref.read(knowledgeManageProvider.notifier);
    final selected = km.selectedNames.contains(kp.name);
    // 状态徽标：待审（secondary）/ 已转正（primary）。
    final (label, color) = switch (kp.status) {
      'pending' => ('待审', app.secondary),
      'curated' => ('已转正', app.primary),
      _ => ('', app.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          AppCheckbox(
            selected: selected,
            semanticLabel: selected ? '取消选择 ${kp.name}' : '选择 ${kp.name}',
            onTap: () => notifier.toggle(kp.name),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(kp.name)),
          const SizedBox(width: AppSpacing.sm),
          // 「整学年」并集视图下同屏混着上/下学期的点，光看名字分不出归属——
          // 学期徽标让教师点开前就知道这份讲解配给哪个学期。限定了学期时不画（冗余）。
          if (km.semester.isEmpty && kp.semester.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AppTags.normal(kp.semester),
            ),
          if (label.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color, width: 1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: text.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (kp.id != null) ...[
            const SizedBox(width: AppSpacing.sm),
            // 「课件」入口：打开同一知识点的课件编辑器 / 演示；导航归一处，由父级
            // push 课件编辑器（避免散落多处写 push，ADR-0059）。讲解入口已迁到场景库
            // 详情页（ADR-0074 v4：关联知识点后点开即可编辑，本行不再重复提供）。
            AppTextAction(
              label: '课件',
              onPressed: () => onOpenCourseware(kp),
            ),
          ],
        ],
      ),
    );
  }
}
