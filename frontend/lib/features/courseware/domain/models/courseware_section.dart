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

/// 一个讲解环节附带的素材引用（内容块统一化）：asset_id + 说明。
///
/// 不是模型字段——只是 [CoursewareSectionModel.materials] 的解析产物。
class CoursewareMaterialItem {
  const CoursewareMaterialItem({required this.assetId, this.caption = ''});

  final String assetId;
  final String caption;

  factory CoursewareMaterialItem.fromJson(Map<String, dynamic> json) =>
      CoursewareMaterialItem(
        assetId: json['asset_id'] as String? ?? '',
        caption: json['caption'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'asset_id': assetId,
        'caption': caption,
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
/// - [materials] / [scene] 是与 [kind] **解耦**的顶层可选字段（环节内容块统一化）：
///   任何 [kind] 的环节都能挂素材与关联知识点场景。旧 AI 起草数据仍走 [payload]
///   内嵌（items / 整份 SceneSpec），由 [resolvedMaterials] / [resolvedScene] 回退
///   读取；新数据优先走顶层字段。
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

  /// 素材（内容块统一化）：任何 kind 都能挂。与 [payload]['items'] 并存过渡；
  /// 渲染优先走 [resolvedMaterials]。
  final List<CoursewareMaterialItem> materials;

  /// 关联的知识点交互场景（ADR-0061 SceneSpec，内容块统一化），任何 kind 都能挂。
  /// 与 [payload] 内嵌 SceneSpec（interactive_scene 旧结构）并存过渡；渲染优先走
  /// [resolvedScene]。
  final Map<String, dynamic>? scene;

  const CoursewareSectionModel({
    this.id = '',
    this.kind,
    this.title = '',
    this.script = '',
    this.scriptSegments = const [],
    this.payload = const {},
    this.materials = const [],
    this.scene,
  });

  factory CoursewareSectionModel.fromJson(Map<String, dynamic> json) {
    final rawSegs = json['script_segments'];
    final segments = <CoursewareScriptSegment>[];
    if (rawSegs is List) {
      for (final e in rawSegs) {
        if (e is Map) segments.add(CoursewareScriptSegment.fromJson(e as Map<String, dynamic>));
      }
    }
    final rawMaterials = json['materials'];
    final materials = <CoursewareMaterialItem>[];
    if (rawMaterials is List) {
      for (final e in rawMaterials) {
        if (e is Map) materials.add(CoursewareMaterialItem.fromJson(e as Map<String, dynamic>));
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
      materials: materials,
      scene: json['scene'] is Map
          ? Map<String, dynamic>.from(json['scene'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind?.value ?? '',
        'title': title,
        'script': script,
        'script_segments': scriptSegments.map((s) => s.toJson()).toList(),
        'payload': payload,
        'materials': materials.map((m) => m.toJson()).toList(),
        'scene': scene,
      };

  /// 哨兵：用于区分「没传该可选参数」与「显式传 null（要清空）」。
  /// [copyWith] 的可空字段（[kind] / [scene]）用它对 null 敏感——传 null 即清空，
  /// 不传则保留原值（否则 `??` 会把 null 当成「未提供」而保留旧值，导致清除关联失效）。
  static const Object _unset = Object();

  CoursewareSectionModel copyWith({
    String? id,
    Object? kind = _unset,
    String? title,
    String? script,
    List<CoursewareScriptSegment>? scriptSegments,
    Map<String, dynamic>? payload,
    List<CoursewareMaterialItem>? materials,
    Object? scene = _unset,
  }) =>
      CoursewareSectionModel(
        id: id ?? this.id,
        kind: identical(kind, _unset)
            ? this.kind
            : kind as CoursewareSectionKind?,
        title: title ?? this.title,
        script: script ?? this.script,
        scriptSegments: scriptSegments ?? this.scriptSegments,
        payload: payload ?? this.payload,
        materials: materials ?? this.materials,
        scene: identical(scene, _unset)
            ? this.scene
            : scene as Map<String, dynamic>?,
      );

  /// 渲染用的话术段：有 [scriptSegments] 就用它；否则把 legacy 单串 [script]
  /// 包成一段，保证旧课件不空屏、不报错（向后兼容）。
  List<CoursewareScriptSegment> get displaySegments => scriptSegments.isNotEmpty
      ? scriptSegments
      : (script.isNotEmpty
          ? [CoursewareScriptSegment(text: script)]
          : const <CoursewareScriptSegment>[]);

  /// 解析 payload['items']（兼容旧 AI 起草数据，media_gallery 把素材塞进 payload）。
  List<CoursewareMaterialItem> get _payloadMaterials {
    final raw = payload['items'];
    if (raw is! List) return const <CoursewareMaterialItem>[];
    return <CoursewareMaterialItem>[
      for (final e in raw)
        if (e is Map) CoursewareMaterialItem.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// 素材：优先顶层 [materials]，否则回退 payload['items']（旧数据）。
  List<CoursewareMaterialItem> get resolvedMaterials =>
      materials.isNotEmpty ? materials : _payloadMaterials;

  /// 关联场景：优先顶层 [scene]，否则旧 interactiveScene 数据整份 payload 即
  /// SceneSpec（向后兼容）；其余情况无场景返回 null。
  Map<String, dynamic>? get resolvedScene {
    if (scene != null) return scene;
    if (kind == CoursewareSectionKind.interactiveScene && payload.isNotEmpty) {
      return payload;
    }
    return null;
  }

  /// 未知 kind（后端新增了类型而前端还没登记）：渲染时给降级提示而不是白屏。
  bool get isUnknownKind => kind == null;
}
