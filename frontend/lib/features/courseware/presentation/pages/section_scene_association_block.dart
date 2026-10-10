import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/scene_interpreter/scene_shells.dart';

/// 「关联知识点场景」（统一表单，任意 kind 都能挂）。
///
/// 以一个 select（[AppPickerField]，基于 ShadSelect）列出该知识点在「讲解」里已配置的
/// 模板，选一份即快照式复制进本节顶层 [CoursewareSectionModel.scene]；知识点没配 →
/// 提示去知识点页配置（[onConfigure] 直达配置入口）；孤儿课件 → 直接不可用。
///
/// 选单的「当前值」用**列表下标**表达（[selectedIndex]）：场景模板是裸 dict、无稳定 id，
/// 单次弹窗内列表只拉取一次（重试会整体重拉），下标足以标识；重开已有课件时按内容深比较
/// 回填下标，找不到匹配（模板已改）则下标置 null、由 [hasScene] 提示已关联但源已失效。
class SectionSceneAssociationBlock extends StatelessWidget {
  const SectionSceneAssociationBlock({
    super.key,
    required this.knowledgePointId,
    required this.loading,
    required this.scenes,
    required this.selectedIndex,
    required this.hasScene,
    required this.onSelectedIndex,
    required this.onClear,
    required this.onRetry,
    required this.onConfigure,
  });

  final String? knowledgePointId;
  final bool loading;
  final List<Map<String, dynamic>>? scenes;
  final int? selectedIndex;
  final bool hasScene;
  final void Function(int) onSelectedIndex;
  final VoidCallback onClear;
  final VoidCallback onRetry;

  /// 知识点未配模板时，直达该知识点的「讲解」配置入口（见 [_SectionEditDialog]）。
  final VoidCallback onConfigure;

  /// 下拉项标签：标题取该 kind 的**外壳展示名**（ADR-0083 决策 5：SceneSpec 已无
  /// title），附 kind 便于区分；kind 也空则回退「未命名模板」。
  static String _labelOf(Map<String, dynamic> spec) {
    final kind = (spec['kind'] as String?)?.trim();
    if (kind != null && kind.isNotEmpty) {
      return '${shellFor(kind).title}（$kind）';
    }
    return '未命名模板';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('关联知识点场景', style: text.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '复用该知识点在「讲解」入口配置好的交互演示模板；选中即填入本环节。',
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (knowledgePointId == null)
          Text(
            '该课件的知识点已移除，无法关联场景。',
            style: text.bodySmall?.copyWith(color: app.error),
          )
        else if (loading)
          const Center(child: AppLoading())
        else if (scenes == null)
          Row(
            children: [
              Expanded(
                child: Text(
                  '读取知识点场景失败。',
                  style: text.bodySmall?.copyWith(color: app.error),
                ),
              ),
              AppTextAction(label: '重试', onPressed: onRetry),
            ],
          )
        else if (scenes!.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: app.secondary.withValues(alpha: 0.08),
              border: Border.all(color: app.secondary, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '该知识点还没有配置交互讲解模板。请先到知识点页的「讲解」入口配置一份'
                  '（如轴对称选图形 + 调对称轴），这里才能选到它。',
                  style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppTextAction(
                  label: '去知识点配置',
                  onPressed: onConfigure,
                ),
              ],
            ),
          )
        else
          ...[
            // 用 ValueKey(selectedIndex) 强制 remount：AppPickerField 基于 ShadSelect 的
            // initialValue（非受控），外部清选时若不重建，下拉显示不会回落到占位文案。
            AppPickerField<int>(
              key: Key('scene-sel-${selectedIndex ?? 'none'}'),
              label: '选择讲解模板',
              values: [for (var i = 0; i < scenes!.length; i++) i],
              labels: [for (final s in scenes!) _labelOf(s)],
              value: selectedIndex,
              placeholder: '未关联（点此选择）',
              onChanged: onSelectedIndex,
            ),
            if (hasScene) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      selectedIndex != null
                          ? '本环节已关联上方选中的交互演示。'
                          : '本环节已关联交互演示（但当前模板列表里找不到匹配项，'
                            '可能知识点模板已改动）。',
                      style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
                    ),
                  ),
                  AppTextAction(label: '清除关联', onPressed: onClear),
                ],
              ),
            ],
          ],
      ],
    );
  }
}
