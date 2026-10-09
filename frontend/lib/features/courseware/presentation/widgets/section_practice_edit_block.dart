import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../domain/models/courseware_practice_block.dart';

/// 编辑环节时的「课堂练习」内容块（courseware-round-3 T06：去 kind 后的第四可选内容块）。
///
/// 与素材 / 场景并列，任何环节都能挂。配置项：题型 [CoursewarePracticeBlock.qtype]
/// + 题量 [CoursewarePracticeBlock.count] + 自由提示 [CoursewarePracticeBlock.hints]。
/// 无练习时是一颗「添加练习」按钮；有练习时展开三段配置 + 「移除练习」。
///
/// 抽成独立文件（ADR-0058 P4）：编辑弹窗已偏大，把练习子件独立避免再涨主文件行数。
class SectionPracticeEditBlock extends StatefulWidget {
  const SectionPracticeEditBlock({
    super.key,
    required this.practice,
    required this.onChanged,
  });

  final CoursewarePracticeBlock? practice;
  final ValueChanged<CoursewarePracticeBlock?> onChanged;

  @override
  State<SectionPracticeEditBlock> createState() =>
      _SectionPracticeEditBlockState();
}

class _SectionPracticeEditBlockState extends State<SectionPracticeEditBlock> {
  final TextEditingController _countCtl = TextEditingController();
  final TextEditingController _hintsCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncFrom(widget.practice);
  }

  @override
  void didUpdateWidget(covariant SectionPracticeEditBlock old) {
    super.didUpdateWidget(old);
    if (old.practice != widget.practice) _syncFrom(widget.practice);
  }

  /// 把当前练习配置同步进输入框：仅在文本不一致时才改写，避免每次按键后光标跳回开头。
  void _syncFrom(CoursewarePracticeBlock? p) {
    final countText = p == null ? '' : '${p.count}';
    if (_countCtl.text != countText) _countCtl.text = countText;
    final hintsText = p?.hints ?? '';
    if (_hintsCtl.text != hintsText) _hintsCtl.text = hintsText;
  }

  @override
  void dispose() {
    _countCtl.dispose();
    _hintsCtl.dispose();
    super.dispose();
  }

  static const List<String> _qtypes = ['choice', 'fill', 'calc', 'open'];
  static const List<String> _qtypeLabels = ['选择题', '填空题', '计算题', '应用题'];

  void _enable() => widget.onChanged(const CoursewarePracticeBlock());

  void _remove() => widget.onChanged(null);

  void _setQtype(String q) => widget.onChanged(
        (widget.practice ?? const CoursewarePracticeBlock()).copyWith(qtype: q),
      );

  void _setCount(String v) => widget.onChanged(
        (widget.practice ?? const CoursewarePracticeBlock())
            .copyWith(count: int.tryParse(v) ?? 3),
      );

  void _setHints(String v) => widget.onChanged(
        (widget.practice ?? const CoursewarePracticeBlock()).copyWith(hints: v),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('课堂练习', style: text.labelMedium),
            const Spacer(),
            if (widget.practice != null)
              AppTextAction(label: '移除练习', onPressed: _remove),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (widget.practice == null)
          AppPrimaryButton(
            label: '添加练习',
            fullWidth: false,
            onPressed: _enable,
          )
        else ...[
          AppPickerField<String>(
            label: '题型',
            values: _qtypes,
            labels: _qtypeLabels,
            value: widget.practice!.qtype,
            onChanged: _setQtype,
            placeholder: '请选择题型',
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: '题量',
            controller: _countCtl,
            keyboardType: TextInputType.number,
            onChanged: _setCount,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: '提示说明（可选）',
            controller: _hintsCtl,
            onChanged: _setHints,
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '练习环节由课堂助手现场出题，学生口头作答，教师点「对 / 错」；'
              '不建任务、不记录作答。',
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}
