import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_quiz_result_card.dart';

/// 做题完成页：全对时背景彩带 + PopIn 入场。
/// checkin（打卡 + reset + onDone）逻辑由调用方持有，经 [onCheckin] 回调。
class PracticeDoneView extends StatelessWidget {
  final int correct;
  final int total;
  final VoidCallback onCheckin;

  const PracticeDoneView({
    super.key,
    required this.correct,
    required this.total,
    required this.onCheckin,
  });

  @override
  Widget build(BuildContext context) {
    final perfect = correct == total;
    final accuracy = total > 0 ? (correct / total * 100).round() : 0;
    return AppQuizResultCard(
      correct: correct,
      total: total,
      title: perfect ? '全部答对！' : '完成练习',
      subtitle: '$correct / $total 正确 · 正确率 $accuracy%',
      trailing: AppPrimaryButton(
        label: '完成打卡',
        icon: LucideIcons.checkCircle2,
        onPressed: onCheckin,
        height: 52,
        fullWidth: false,
      ),
      overlay: perfect ? const ConfettiBurst() : null,
      animate: true,
    );
  }
}
