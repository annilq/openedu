import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_buttons.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../providers/home_notifier.dart';

/// 出题表单底部「动作区」（从 `teacher_task_form_view.dart` 抽出，ADR-0058 P4）。
///
/// 审阅闸门（ADR-0056）：生成结束**不自动落库、不自动跳转**，停在生成页等教师拍板。
/// 三个出口各有明确语义：确认 = 落库为 draft 任务；重新生成 = 丢弃内存题卡重跑
/// （数据库里还没有任何行，不会产生第二份草稿）；放弃 = 回空闲态（同样无需删除调用）。
///
/// 并排按钮一律走 `Wrap`：窄栏（<700）下 `Row` + 固定宽会压缩 [ShadButton] 的内容盒
/// 导致 overflow（描边画在盒外，可见高 = 声明高 + 2×描边宽）。
Widget buildTaskFormActions({
  required TaskGenState genState,
  required VoidCallback onConfirm,
  required VoidCallback onRegenerate,
  required VoidCallback onDiscard,
  required VoidCallback onGenerate,
}) {
  // 生成结束、等待确认：优先于忙碌判定——此时不该隐藏按钮，反而必须给出口。
  if (genState is TaskGenReady) {
    return _ReviewGate(
      onConfirm: onConfirm,
      onRegenerate: onRegenerate,
      onDiscard: onDiscard,
    );
  }
  final busy =
      genState is TaskGenLoading ||
      (genState is TaskGenPreview && genState.streaming);
  final showSpinner =
      busy &&
      (genState is TaskGenPreview
          ? (genState.questions.isEmpty && genState.liveIndex < 0)
          : true);
  if (showSpinner) {
    final stage = genState is TaskGenPreview ? genState.stage : '';
    return AppLoading(message: stage.isEmpty ? '正在准备出题…' : stage);
  }
  if (busy) {
    // 题卡已在渲染：仅占位隐藏按钮，不显示 spinner。
    return const SizedBox.shrink();
  }
  return Row(
    children: [
      Expanded(child: AppPrimaryButton(label: '生成任务', onPressed: onGenerate)),
    ],
  );
}

class _ReviewGate extends StatelessWidget {
  const _ReviewGate({
    required this.onConfirm,
    required this.onRegenerate,
    required this.onDiscard,
  });

  final VoidCallback onConfirm;
  final VoidCallback onRegenerate;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppPrimaryButton(label: '确认并进入草稿', onPressed: onConfirm),
        ShadButton.outline(
          onPressed: onRegenerate,
          leading: const Icon(LucideIcons.rotateCw, size: 16),
          child: const Text('重新生成'),
        ),
        ShadButton.outline(
          onPressed: onDiscard,
          leading: const Icon(LucideIcons.x, size: 16),
          child: const Text('放弃'),
        ),
      ],
    );
  }
}
