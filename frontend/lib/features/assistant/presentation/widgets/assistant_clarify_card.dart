// cupertino.dart 已转出 widgets（`Text` / `Wrap` / `TextEditingController` 等），
// 不必再单独 import widgets。
import 'package:flutter/cupertino.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../domain/assistant_clarify.dart';

/// 缺槽引导输入卡（ADR-0095）。
///
/// 后端在**普通** ASSISTANT_MESSAGE 帧的 `extra.clarify` 下发仍缺的必填槽（不新增
/// 事件类型），前端据此渲染可点选 / 可输入的引导卡：枚举与带范围的 int 出选项 chips，
/// 其余出输入框。选定后把值当作一条新的用户消息发出（复用 `onPrompt`），后端下一轮
/// 合并该槽继续——用户既不用猜措辞，也不必把整条需求重打一遍。
///
/// 全程无 Material 控件：可点区一律 [AppFocusableAction]，输入用 Cupertino 输入框
/// （根是 `ShadApp` + `CupertinoApp`，没有 Material 祖先）。
class AssistantClarifyCard extends StatelessWidget {
  final List<ClarifySlot> slots;

  /// 把选定/输入的值当作一条用户消息发出（与 follow-up chips 同一条通路）。
  final void Function(String payload) onPrompt;

  const AssistantClarifyCard({
    super.key,
    required this.slots,
    required this.onPrompt,
  });

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) return const SizedBox.shrink();
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.sm, AppSpacing.xl2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '还差这些信息：',
            style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final slot in slots) _SlotField(slot: slot, onPrompt: onPrompt),
        ],
      ),
    );
  }
}

/// 单个缺槽：话术 + 对应控件（chips 或输入框）。
class _SlotField extends StatelessWidget {
  final ClarifySlot slot;
  final void Function(String payload) onPrompt;

  const _SlotField({required this.slot, required this.onPrompt});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.prompt.isEmpty ? '请补充：${slot.name}' : slot.prompt,
            style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs2),
          _control(slot),
        ],
      ),
    );
  }

  Widget _control(ClarifySlot slot) {
    if (slot.isEnum && slot.values.isNotEmpty) {
      return _chipWrap(
        slot.values,
        labelOf: (v) => _labelFor(slot.name, v),
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
      return _FreeInput(slot: slot, onSubmit: onPrompt);
    }
    if (slot.isBool) {
      return _chipWrap(
        const <String>['是', '否'],
        labelOf: (v) => v,
        payloadOf: (v) => v,
      );
    }
    return _FreeInput(slot: slot, onSubmit: onPrompt);
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
            _ClarifyChip(
              label: labelOf(v),
              onTap: () => onPrompt(payloadOf(v)),
            ),
        ],
      );
}

/// int 槽的候选值：按 schema 的 [min]/[max] 铺开；范围过大返回空（改走输入框）。
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

/// 枚举码 → 中文展示名；未登记的槽直接用原值（学科等中文枚举天然可读）。
const _kEnumLabels = <String, Map<String, String>>{
  'qtype': <String, String>{
    'choice': '选择题',
    'fill': '填空题',
    'calc': '计算题',
    'open': '解答题',
  },
  'difficulty': <String, String>{
    'easy': '简单',
    'medium': '中等',
    'hard': '难',
  },
  'semester': <String, String>{'上': '上学期', '下': '下学期'},
};

String _labelFor(String name, String value) =>
    _kEnumLabels[name]?[value] ?? value;

/// 自由输入（string 槽 / 超大范围 int）：Cupertino 输入框 + 发送。
class _FreeInput extends StatefulWidget {
  final ClarifySlot slot;
  final void Function(String payload) onSubmit;

  const _FreeInput({required this.slot, required this.onSubmit});

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
        _ClarifyChip(
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

/// 引导卡 chip：新粗野描边药丸（与 follow-up chips 同一套视觉），点击走焦点树。
class _ClarifyChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ClarifyChip({required this.label, required this.onTap});

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
