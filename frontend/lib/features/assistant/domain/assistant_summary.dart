import 'assistant_clarify.dart';
import 'assistant_event.dart';

/// 「已确认规格」汇总帧里的一个槽（ADR-0095）。
///
/// 与澄清槽**同构**：[ClarifySlot] 承载 name / type / enum / min / max，本类只补上
/// 汇总才有的「中文标签 + 当前值」。前端因此能用同一套取值控件渲染「修改」，
/// 不必为汇总再写一份 chips（两份实现迟早漂移）。
///
/// 后端在普通 ASSISTANT_MESSAGE 帧的 `extra.summary` 下发它（同样不新增事件类型），
/// 目的是让用户在生成**前**看得见自己被默认填了什么、并能改（US5）。
class SummarySlot {
  /// 槽位形状（与澄清槽共用，供取值控件复用）。
  final ClarifySlot slot;

  /// 中文标签（科目 / 年级 / 题型…）。
  final String label;

  /// 原始值（int / String / bool）。
  final Object? value;

  /// 值的中文可读文案（英文码已翻译；空值为「（未指定）」）。
  final String valueLabel;

  const SummarySlot({
    required this.slot,
    this.label = '',
    this.value,
    this.valueLabel = '',
  });

  /// 是否提供「修改」入口。
  ///
  /// bool 槽一律不给：后端按关键词抽取（如「多选」），而 chips 只能回传「是 / 否」，
  /// 既定位不到具体槽、也无法表达 False——开了就是点了没反应的死路。
  bool get canEdit => !slot.isBool;

  factory SummarySlot.fromJson(Map<String, dynamic> json) => SummarySlot(
        slot: ClarifySlot.fromJson(json),
        label: (json['label'] as String?) ?? '',
        value: json['value'],
        valueLabel: (json['value_label'] as String?) ?? '',
      );

  /// 从事件帧的 `extra.summary` 解析汇总槽列表；无汇总标记则空列表。
  ///
  /// 与澄清帧同样宽容：畸形帧一律降级为空，不抛、不造出空卡片。
  static List<SummarySlot> slotsOfEvent(AssistantEvent ev) {
    final summary = ev.extra?['summary'];
    if (summary is! Map<String, dynamic>) return const <SummarySlot>[];
    final raw = summary['slots'];
    if (raw is! List) return const <SummarySlot>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(SummarySlot.fromJson)
        .where((s) => s.slot.name.isNotEmpty)
        .toList();
  }
}
