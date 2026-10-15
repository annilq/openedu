// cupertino.dart 已转出 widgets（`Text` / `Wrap` / `TextEditingController` 等），
// 不必再单独 import widgets。
import 'package:flutter/cupertino.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/utils/question_labels.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../domain/assistant_clarify.dart';

/// 单个槽位的取值控件（ADR-0095）：枚举 / 带范围 int / bool 出选项 chips，其余出输入框。
///
/// 澄清卡的「还差什么」与汇总卡的「修改」共用同一套控件——两份 chip 实现迟早漂移
/// （一边改视觉另一边没跟上）。控件只负责**取值**，不关心自己身在哪种卡里。
///
/// 无 Material 控件：可点区一律 [AppFocusableAction]，输入用 Cupertino 输入框。
class AssistantSlotInput extends StatelessWidget {
  final ClarifySlot slot;

  /// 把选定 / 输入的值当作一条用户消息发出（与 follow-up chips 同一条通路）。
  final void Function(String payload) onPrompt;

  const AssistantSlotInput({
    super.key,
    required this.slot,
    required this.onPrompt,
  });

  @override
  Widget build(BuildContext context) {
    if (slot.isEnum && slot.values.isNotEmpty) {
      return _chipWrap(
        slot.values,
        labelOf: (v) => _labelFor(slot.name, v),
        payloadOf: (v) => v,
      );
    }
    if (slot.isBool) {
      return _chipWrap(
        const <String>['是', '否'],
        labelOf: (v) => v,
        payloadOf: (v) => v,
      );
    }
    if (slot.isInt) {
      final options = _intOptions(slot);
      // 范围过大（>12 档）不铺 chips——那时点选比打字更难用，退回输入框。
      if (options.isNotEmpty) {
        return _chipWrap(
          options,
          labelOf: (v) => v,
          payloadOf: (v) => _intPayload(slot.name, v),
        );
      }
      return _FreeInput(onSubmit: onPrompt);
    }
    return _FreeInput(onSubmit: onPrompt);
  }

  Widget _chipWrap(
    List<String> values, {
    required String Function(String) labelOf,
    required String Function(String) payloadOf,
  }) =>
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final v in values)
            _SlotChip(
              label: labelOf(v),
              onTap: () => onPrompt(payloadOf(v)),
            ),
        ],
      );
}

/// int 槽的候选值：按 schema 的 min/max 铺开；范围过大返回空（改走输入框）。
List<String> _intOptions(ClarifySlot slot) {
  final lo = slot.min ?? 1;
  final hi = slot.max ?? 9;
  if (hi < lo || hi - lo > 11) return const <String>[];
  return <String>[for (var v = lo; v <= hi; v++) '$v'];
}

/// int 槽的回填文案。
///
/// 年级必须说成「3年级」：后端按「N年级」正则抽取，光发一个「3」抽不到。
/// 其余 int 槽（如数量）直接发数字即可。
String _intPayload(String name, String value) =>
    name == 'grade' ? '$value年级' : value;

/// 枚举码 → 中文展示名。
///
/// 题型 / 难度 / 学期文案一律走 `shared/utils/question_labels.dart`（frontend.md §4：
/// 枚举→文案只写一次）；未登记的槽（学科等中文枚举）直接用原值。
String _labelFor(String name, String value) => switch (name) {
      'qtype' => qtypeLabelFull(value),
      'difficulty' => difficultyLabel(value),
      'semester' => semesterLabel(value),
      _ => value,
    };

/// 自由输入（string 槽 / 超大范围 int）：Cupertino 输入框 + 发送。
class _FreeInput extends StatefulWidget {
  final void Function(String payload) onSubmit;

  const _FreeInput({required this.onSubmit});

  @override
  State<_FreeInput> createState() => _FreeInputState();
}

class _FreeInputState extends State<_FreeInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: CupertinoTextField(
              controller: _controller,
              placeholder: '请输入',
              placeholderStyle: TextStyle(color: scheme.onSurfaceVariant),
              style: TextStyle(color: scheme.onSurface),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs2),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _SlotChip(
          label: '发送',
          onTap: () {
            final v = _controller.text.trim();
            if (v.isNotEmpty) widget.onSubmit(v);
          },
        ),
      ],
    );
  }
}

/// 取值 chip：新粗野描边药丸（与 follow-up chips 同一套视觉），点击走焦点树。
class _SlotChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SlotChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppFocusableAction(
      onTap: onTap,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
        child: Text(
          label,
          style: text.labelMedium?.copyWith(color: scheme.onSurface),
        ),
      ),
    );
  }
}
