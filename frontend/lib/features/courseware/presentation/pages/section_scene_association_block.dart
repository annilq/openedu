import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_loading.dart';

/// 「关联知识点场景」（统一表单，任意 kind 都能挂）。
///
/// 列出该知识点在「讲解」里已配置的交互演示模板（ADR-0061 SceneSpec），点一份即
/// 快照式复制进本节顶层 [CoursewareSectionModel.scene]；知识点没配 → 提示去知识点页
/// 配置；孤儿课件 → 直接不可用。
///
/// 从 [showCoursewareSectionEditDialog] 的编辑态中提取为独立无状态组件：所需数据
/// 全部由参数传入，不再直接读编辑页 state（ADR-0058 §4：一个文件只暴露一个公开物）。
class SectionSceneAssociationBlock extends StatelessWidget {
  const SectionSceneAssociationBlock({
    super.key,
    required this.knowledgePointId,
    required this.loading,
    required this.scenes,
    required this.hasScene,
    required this.onRetry,
    required this.onAssociate,
    required this.onClear,
  });

  final String? knowledgePointId;
  final bool loading;
  final List<Map<String, dynamic>>? scenes;
  final bool hasScene;
  final VoidCallback onRetry;
  final void Function(Map<String, dynamic>) onAssociate;
  final VoidCallback onClear;

  String _titleOf(Map<String, dynamic> spec) =>
      (spec['title'] as String?)?.isNotEmpty == true
          ? spec['title'] as String
          : ((spec['kind'] as String?)?.isNotEmpty == true
              ? spec['kind'] as String
              : '未命名模板');

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
            child: Text(
              '该知识点还没有配置交互讲解模板。请先到知识点页的「讲解」入口配置一份'
              '（如轴对称选图形 + 调对称轴），这里才能选到它。',
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
            ),
          )
        else
          ...[
            for (final spec in scenes!)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  onTap: () => onAssociate(spec),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_titleOf(spec), style: text.titleSmall),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                '类型：${spec['kind'] ?? '未知'}',
                                style: text.bodySmall
                                    ?.copyWith(color: app.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        AppTextAction(
                          label: '选用',
                          onPressed: () => onAssociate(spec),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (hasScene) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '本环节已关联交互演示。',
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
