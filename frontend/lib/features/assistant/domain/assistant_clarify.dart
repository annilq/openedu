import 'assistant_event.dart';

/// 缺槽引导输入卡的数据契约（ADR-0095）。
///
/// 后端在 **普通** ASSISTANT_MESSAGE 帧的 `extra.clarify.missing_slots` 下发「还缺哪
/// 些必填槽」（不新增事件类型），前端据此渲染可点选 / 可输入的引导卡——而不是让用户
/// 对着一句裸文本自己猜该补什么、该用什么措辞。
///
/// 槽位定义（含哪些必填、可选项、范围）由后端各 subagent 的 `input_schema` 唯一承载，
/// 前端不再另写一份选项表，避免两边漂移。
class ClarifySlot {
  final String name;

  /// 缺槽话术（后端 `input_schema` 的 `prompt`）。
  final String prompt;

  /// enum | int | bool | string（后端 `input_schema` 的 `type`）。
  final String type;

  /// enum 的可选项（`enum` / `enum_ref` 解析后的实际值）；非 enum 为空。
  final List<String> values;

  /// int 槽的取值下限（来自 schema 的 `min`）。
  final int? min;

  /// int 槽的取值上限（来自 schema 的 `max`）。
  final int? max;

  const ClarifySlot({
    required this.name,
    required this.prompt,
    required this.type,
    this.values = const <String>[],
    this.min,
    this.max,
  });

  bool get isEnum => type == 'enum';
  bool get isInt => type == 'int';
  bool get isBool => type == 'bool';

  factory ClarifySlot.fromJson(Map<String, dynamic> json) => ClarifySlot(
        name: (json['name'] as String?) ?? '',
        prompt: (json['prompt'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'string',
        values: ((json['enum'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .toList(),
        min: json['min'] as int?,
        max: json['max'] as int?,
      );

  /// 从事件帧的 `extra.clarify` 解析缺失槽列表；无澄清标记则空列表。
  ///
  /// 畸形帧（extra 不是 Map / missing_slots 不是 List / 槽缺 name）一律降级为空，
  /// 不抛、不造出无法操作的空气卡。
  static List<ClarifySlot> slotsOfEvent(AssistantEvent ev) {
    final clarify = ev.extra?['clarify'];
    if (clarify is! Map<String, dynamic>) return const <ClarifySlot>[];
    final raw = clarify['missing_slots'];
    if (raw is! List) return const <ClarifySlot>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ClarifySlot.fromJson)
        .where((s) => s.name.isNotEmpty)
        .toList();
  }
}
