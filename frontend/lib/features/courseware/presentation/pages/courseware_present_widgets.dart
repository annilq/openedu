import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../domain/models/courseware_section.dart';
import '../../domain/models/courseware_section_kind.dart';
import '../widgets/courseware_script_view.dart';
import '../widgets/section_interactive_scene.dart';
import '../widgets/section_media_gallery.dart';

/// 主区：环节标题 + 话术提问卡 + 按 kind 分派的环节内容。
///
/// 话术**不折叠**（决策 15）：投影时教师屏 = 学生所见，做「仅教师可见」在单屏下
/// 物理上不可能；且「这些图形有什么共同点？」抛出去才是引导学生观察，藏起来反而
/// 没了教学动作。
class PresentStage extends StatelessWidget {
  const PresentStage({super.key, required this.section});

  final CoursewareSectionModel section;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            section.title,
            style: text.titleLarge?.copyWith(color: app.onSurface),
          ),
          if (section.displaySegments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildScriptCard(context, app, text),
          ],
          const SizedBox(height: AppSpacing.lg),
          Expanded(child: SingleChildScrollView(child: _buildBody(context))),
        ],
      ),
    );
  }

  Widget _buildScriptCard(
    BuildContext context,
    AppColors app,
    AppText text,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: app.outline,
          width: AppElevation.borderWidthHairline,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '提问',
            style: text.labelSmall?.copyWith(
              color: app.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs2),
          CoursewareScriptSegmentsView(
            segments: section.displaySegments,
            baseStyle: text.titleMedium?.copyWith(
              color: app.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 主区内容：**按填了什么渲染**，与 [CoursewareSectionModel.kind] 无关（内容块统一化）。
  ///
  /// - 有素材 → 图廊；有关联场景 → 交互演示；两者皆无 → 空态（只有话术）。
  /// - 未知 kind 且没有任何内容才给「暂不支持」降级提示，而不是白屏——课堂上白屏等于
  ///   「课件坏了」。
  Widget _buildBody(BuildContext context) {
    final materials = section.resolvedMaterials;
    final scene = section.resolvedScene;
    final hasMaterials = materials.isNotEmpty;
    final hasScene = scene != null;
    if (section.isUnknownKind && !hasMaterials && !hasScene) {
      return const AppEmptyState(
        icon: LucideIcons.circleAlert,
        title: '暂不支持的环节类型',
        message: '这份课件里有本版本还不认识的环节类型，这一段先用文字讲。',
      );
    }
    if (!hasMaterials && !hasScene) {
      // 交互探究环节却没配场景：给更贴切的指引，而不是笼统的「只有话术」。
      if (section.kind == CoursewareSectionKind.interactiveScene) {
        return const AppEmptyState(
          icon: LucideIcons.shapes,
          title: '这一环节还没有配置交互演示',
          message: '这一环节是交互演示，但还没有填入演示内容。回到课件编辑页打开'
              '场景编辑器，调好图形与对称轴后这里就会显示。',
        );
      }
      return const AppEmptyState(
        icon: LucideIcons.textSelect,
        title: '这一环节只有话术',
        message: '这一环节还没有关联素材或交互演示，只有教师话术。'
            '回到课件编辑页给它加上素材或场景。',
        steps: [
          '在课件编辑页打开这个环节',
          '点「添加素材」放进图片',
          '或点「关联知识点场景」选一份交互演示',
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasMaterials) ...[
          SectionMediaGallery(materials: materials),
          if (hasScene) const SizedBox(height: AppSpacing.lg),
        ],
        if (hasScene) SectionInteractiveScene(spec: scene),
      ],
    );
  }
}

/// 底部：上一步 / `2 / 4` / 下一步。
class PresentFooter extends StatelessWidget {
  const PresentFooter({
    super.key,
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Container(
      decoration: BoxDecoration(
        color: app.surfaceRaised,
        border: Border(
          top: BorderSide(
            color: app.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          AppPrimaryButton(
            label: '上一步',
            icon: LucideIcons.chevronLeft,
            fullWidth: false,
            height: AppControl.heightLgOf(context),
            onPressed: onPrev,
          ),
          Expanded(
            child: Center(
              child: Text(
                '${index + 1} / $total',
                style: text.titleSmall?.copyWith(color: app.onSurface),
              ),
            ),
          ),
          AppPrimaryButton(
            label: '下一步',
            icon: LucideIcons.chevronRight,
            fullWidth: false,
            height: AppControl.heightLgOf(context),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
