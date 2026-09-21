import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/question_labels.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_motion.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../../shared/widgets/stream_reasoning_panel.dart';
import '../../providers/home_notifier.dart';

/// 生成预览区：题卡逐张浮现 + 流式推理面板 + 少题警示。
///
/// [TaskGenPreview]（流式/落库中）与 [TaskGenReady]（待确认）**共用同一套渲染**——
/// 后者只是「不再有流式推理区」的同构形态，故本区块直接吃 [TaskGenState]，
/// 由它自己把两种状态归一成同一组字段：这份同构判断属于预览，不该漏到表单里。
class TaskPreviewSection extends StatelessWidget {
  final TaskGenState state;

  const TaskPreviewSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final List<QuestionPreview> questions;
    final bool streaming;
    final List<String> failures;
    final int liveIndex;
    final String liveLabel;
    final String liveReasoning;
    final bool awaitingConfirm = state is TaskGenReady;
    // 取到局部变量才谈得上类型提升：`state` 是字段，Dart 不会为它做 promotion。
    final current = state;
    if (current is TaskGenPreview) {
      questions = current.questions;
      streaming = current.streaming;
      failures = current.failures;
      liveIndex = current.liveIndex;
      liveLabel = current.liveLabel;
      liveReasoning = current.liveReasoning;
    } else {
      final r = current as TaskGenReady;
      questions = r.questions;
      streaming = false;
      failures = r.failures;
      liveIndex = -1;
      liveLabel = '';
      liveReasoning = '';
    }
    final status = streaming
        ? '生成中…'
        : awaitingConfirm
            ? '待确认'
            : '已完成';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '预览（${questions.length} 题 · $status）',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        // 边界文案（ADR-0056）：思路不落库是设计，但若不说清楚，进入草稿页后
        // 「思路不见了」会被当成 bug 再报一次。行为与文案互相印证。
        if (questions.any((q) => q.reasoning.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '出题思路仅在生成过程中展示，确认后不会随任务保存。',
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        // 有单题失败：醒目提示「少题」，避免家长以为题已出齐。
        if (failures.isNotEmpty)
          _FailureBanner(
            text: '有 ${failures.length} 道题生成失败：${failures.join('；')}',
          ),
        // 生成中：当前题的内联推理区（题卡到达后折叠，见 _PreviewCard 的 info icon）。
        if (streaming && liveIndex >= 0)
          StreamReasoningPanel(
            index: liveIndex + 1,
            label: liveLabel,
            reasoning: liveReasoning,
            streaming: streaming,
          ),
        // key 用序号（列表只追加）→ PopIn 的 State 不重建，已在屏上的题卡
        // 不会因下一张到达而重放弹簧入场。
        ...questions.asMap().entries.map(
              (e) => PopIn(
                key: ValueKey<int>(e.key),
                child: _PreviewCard(index: e.key + 1, q: e.value),
              ),
            ),
      ],
    );
  }
}

/// 弹出「AI 出题思路」面板（ADR-0017）：纯前端交互，展示该题 reasoning，不编辑、不落库。
void _showReasoningSheet(BuildContext context, String reasoning) {
  final text = AppTheme.textOf(context);
  showCupertinoModalPopup(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: const Text('AI 出题思路'),
      message: SizedBox(
        height: 240,
        child: SingleChildScrollView(
          child: Text(
            reasoning,
            style: text.bodyMedium,
          ),
        ),
      ),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 少题警示条：出题过程中有单题失败时展示，避免家长误以为题已出齐。
///
/// 新粗野化：红色改走 `AppBrutal.red` 实心（深块，只能配白字 5.56:1），
/// 2px 墨黑描边 + 硬阴影——警示必须是全屏最强的视觉层级。
class _FailureBanner extends StatelessWidget {
  final String text;
  const _FailureBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final textStyle = AppTheme.textOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppBrutal.red,
        borderRadius: BorderRadius.circular(AppRadius.bubble),
        border: Border.all(
            color: AppBrutal.ink, width: AppElevation.borderWidth),
        boxShadow: AppElevation.hard(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 18, color: AppBrutal.onDark),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: textStyle.bodySmall?.copyWith(
                color: AppBrutal.onDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 流式预览题卡（票据 08）：对应后端 `question` 事件，逐张浮现。
class _PreviewCard extends StatelessWidget {
  final int index;
  final QuestionPreview q;

  const _PreviewCard({required this.index, required this.q});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final options = q.options;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.bubble),
        border: Border.all(
            color: AppBrutal.ink, width: AppElevation.borderWidth),
        boxShadow: AppElevation.hard(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 题号用 violet（深块 → 白字 5.55:1），与学科 chip 的色相错开。
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppBrutal.violet,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(
                      color: AppBrutal.ink,
                      width: AppElevation.borderWidthSm),
                ),
                child: Text('第 $index 题',
                    style: text.labelSmall?.copyWith(
                        color: AppBrutal.onDark,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: AppSpacing.sm),
              // 学科走三重编码 chip（色 + 几何标记 + 文字），不再只靠纯文本。
              AppTags.subject(SubjectAccent.fromName(q.subject)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${q.grade}年级 · ${qtypeLabel(q.qtype)} · ${difficultyLabel(q.difficulty)}',
                  textAlign: TextAlign.end,
                  style: text.labelSmall?.copyWith(color: app.onSurfaceVariant),
                ),
              ),
              // 出题推理：卡片右上角 info icon，点击展开「AI 出题思路」（ADR-0017）。
              if (q.reasoning.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                AppIconAction(
                  icon: LucideIcons.info,
                  semanticLabel: '查看 AI 出题思路',
                  color: app.onSurfaceVariant,
                  onPressed: () => _showReasoningSheet(context, q.reasoning),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(q.stem, style: text.bodyMedium),
          if (options != null && options.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ...options.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${String.fromCharCode(65 + e.key)}. ${e.value}',
                      style: text.bodySmall,
                    ),
                  ),
                ),
          ],
          if (q.answer != null && q.answer!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('答案：${q.answer}',
                style: text.bodySmall?.copyWith(color: app.primary)),
          ],
          if (q.explanation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('解析：${q.explanation}',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
