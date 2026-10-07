import 'courseware_section_kind.dart';

/// 话术段的重点级别（ADR-0067 第二轮 T02）：轻量富文本，不引入新渲染引擎。
enum CoursewareScriptEmphasis {
  none('none'),
  bold('bold'),
  highlight('highlight');

  const CoursewareScriptEmphasis(this.value);

  final String value;

  static CoursewareScriptEmphasis tryParse(String? raw) => switch (raw) {
        'bold' => CoursewareScriptEmphasis.bold,
        'highlight' => CoursewareScriptEmphasis.highlight,
        _ => CoursewareScriptEmphasis.none,
      };
}

/// 话术里的一段（T02）：一段提问卡文案 + 可选重点标注。
class CoursewareScriptSegment {
  const CoursewareScriptSegment({this.text = '', this.emphasis = CoursewareScriptEmphasis.none});

  final String text;
  final CoursewareScriptEmphasis emphasis;

  factory CoursewareScriptSegment.fromJson(Map<String, dynamic> json) =>
      CoursewareScriptSegment(
        text: json['text'] as String? ?? '',
        emphasis: CoursewareScriptEmphasis.tryParse(json['emphasis'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'emphasis': emphasis.value,
      };
}

/// 一个讲解环节（ADR-0067 §3.3）。
///
/// 与后端 `app/features/courseware/schemas.py::CoursewareSection` 逐字段对齐。
///
/// - [script] 是教师话术（「这些图形有什么共同点？」）。按决策 15，它**当提问卡
///   直接投给学生看**——投影时教师屏 = 学生所见，做「仅教师可见」在单屏下物理上
///   不可能，且课堂提问本来就该让学生看见。
/// - [payload] 按 [kind] 释义：
///   - `mediaGallery`: `{items: [{asset_id, caption}]}`
///   - `interactiveScene`: **直接是一份 ADR-0061 SceneSpec**（原样透传渲染器）
///   - `practice`: `{qtype, count}`
class CoursewareSectionModel {
  final String id;
  final CoursewareSectionKind? kind;
  final String title;

  /// 教师话术 / 提问卡文案（首轮单串 legacy）。T02 之后新数据走 [scriptSegments]，
  /// 旧单串课件靠它向下兼容（见 [displaySegments] 回退）。
  final String script;

  /// 话术多段列表（T02）。空 = 退化读 [script]。
  final List<CoursewareScriptSegment> scriptSegments;

  /// 按 kind 释义的原始 JSON（保持 Map，不做多态建模——渲染交给各自组件）。
  final Map<String, dynamic> payload;

  const CoursewareSectionModel({
    this.id = '',
    this.kind,
    this.title = '',
    this.script = '',
    this.scriptSegments = const [],
    this.payload = const {},
  });

  factory CoursewareSectionModel.fromJson(Map<String, dynamic> json) {
    final rawSegs = json['script_segments'];
    final segments = <CoursewareScriptSegment>[];
    if (rawSegs is List) {
      for (final e in rawSegs) {
        if (e is Map) segments.add(CoursewareScriptSegment.fromJson(e as Map<String, dynamic>));
      }
    }
    return CoursewareSectionModel(
      id: json['id'] as String? ?? '',
      kind: CoursewareSectionKind.tryParse(json['kind'] as String?),
      title: json['title'] as String? ?? '',
      script: json['script'] as String? ?? '',
      scriptSegments: segments,
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind?.value ?? '',
        'title': title,
        'script': script,
        'script_segments': scriptSegments.map((s) => s.toJson()).toList(),
        'payload': payload,
      };

  CoursewareSectionModel copyWith({
    String? id,
    CoursewareSectionKind? kind,
    String? title,
    String? script,
    List<CoursewareScriptSegment>? scriptSegments,
    Map<String, dynamic>? payload,
  }) =>
      CoursewareSectionModel(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        script: script ?? this.script,
        scriptSegments: scriptSegments ?? this.scriptSegments,
        payload: payload ?? this.payload,
      );

  /// 渲染用的话术段：有 [scriptSegments] 就用它；否则把 legacy 单串 [script]
  /// 包成一段，保证旧课件不空屏、不报错（向后兼容）。
  List<CoursewareScriptSegment> get displaySegments => scriptSegments.isNotEmpty
      ? scriptSegments
      : (script.isNotEmpty
          ? [CoursewareScriptSegment(text: script)]
          : const <CoursewareScriptSegment>[]);

  /// 未知 kind（后端新增了类型而前端还没登记）：渲染时给降级提示而不是白屏。
  bool get isUnknownKind => kind == null;
}
