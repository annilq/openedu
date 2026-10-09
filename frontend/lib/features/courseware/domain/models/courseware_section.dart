import 'courseware_practice_block.dart';

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
/// - [payload] 是旧 AI 起草数据的兜底容器（内嵌 items / 整份 SceneSpec），渲染交给各自组件。
/// - [materials] / [scene] / [practice] 是顶层可选内容块（环节内容块统一化，
///   courseware-round-3 T07 起为唯一事实）：任何环节都能挂素材与关联知识点场景。
///   旧 AI 起草数据仍走 [payload] 内嵌（items / 整份 SceneSpec），由
///   [resolvedMaterials] / [resolvedScene] 回退读取；新数据优先走顶层字段。
class CoursewareSectionModel {
  final String id;
  final String title;

  /// 教师话术 / 提问卡文案（首轮单串 legacy）。T02 之后新数据走 [scriptSegments]，
  /// 旧单串课件靠它向下兼容（见 [displaySegments] 回退）。
  final String script;

  /// 话术多段列表（T02）。空 = 退化读 [script]。
  final List<CoursewareScriptSegment> scriptSegments;

  /// 旧 AI 起草数据的兜底 JSON（保持 Map，不做多态建模——渲染交给各自组件）。
  final Map<String, dynamic> payload;

  /// 素材（内容块统一化）：任何环节都能挂。与 [payload]['items'] 并存过渡；
  /// 渲染优先走 [resolvedMaterials]。
  final List<CoursewareMaterialItem> materials;

  /// 关联的知识点交互场景（ADR-0061 SceneSpec，内容块统一化），任何环节都能挂。
  /// 与 [payload] 内嵌 SceneSpec（interactive_scene 旧结构）并存过渡；渲染优先走
  /// [resolvedScene]。
  final Map<String, dynamic>? scene;

  /// 课堂练习内容块（courseware-round-3 T06：去 kind 后的第四可选内容块）。
  /// 与 [materials] / [scene] 并列，任何环节都能挂。旧 AI 起草数据走 [payload]
  /// 里的 `qtype` 由 [_resolvePractice] 回退读取。
  final CoursewarePracticeBlock? practice;

  const CoursewareSectionModel({
    this.id = '',
    this.title = '',
    this.script = '',
    this.scriptSegments = const [],
    this.payload = const {},
    this.materials = const [],
    this.scene,
    this.practice,
  });

  /// 解析练习内容块：优先顶层 [practice]，否则回退旧 AI 起草的 [payload]['qtype']。
  static CoursewarePracticeBlock? _resolvePractice(Map<String, dynamic> json) {
    final top = json['practice'];
    if (top is Map) {
      return CoursewarePracticeBlock.fromJson(Map<String, dynamic>.from(top));
    }
    final payload = json['payload'];
    if (payload is Map && payload['qtype'] != null) {
      return CoursewarePracticeBlock.fromJson({
        'qtype': payload['qtype'],
        'count': payload['count'] ?? 3,
        'hints': payload['hints'] ?? '',
      });
    }
    return null;
  }

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
      practice: _resolvePractice(json),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'script': script,
        'script_segments': scriptSegments.map((s) => s.toJson()).toList(),
        'payload': payload,
        'materials': materials.map((m) => m.toJson()).toList(),
        'scene': scene,
        'practice': practice?.toJson(),
      };

  /// 哨兵：用于区分「没传该可选参数」与「显式传 null（要清空）」。
  /// [copyWith] 的可空字段（[scene]）用它对 null 敏感——传 null 即清空，
  /// 不传则保留原值（否则 `??` 会把 null 当成「未提供」而保留旧值，导致清除关联失效）。
  static const Object _unset = Object();

  CoursewareSectionModel copyWith({
    String? id,
    String? title,
    String? script,
    List<CoursewareScriptSegment>? scriptSegments,
    Map<String, dynamic>? payload,
    List<CoursewareMaterialItem>? materials,
    Object? scene = _unset,
    Object? practice = _unset,
  }) =>
      CoursewareSectionModel(
        id: id ?? this.id,
        title: title ?? this.title,
        script: script ?? this.script,
        scriptSegments: scriptSegments ?? this.scriptSegments,
        payload: payload ?? this.payload,
        materials: materials ?? this.materials,
        scene: identical(scene, _unset)
            ? this.scene
            : scene as Map<String, dynamic>?,
        practice: identical(practice, _unset)
            ? this.practice
            : practice as CoursewarePracticeBlock?,
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

  /// 关联场景：只取顶层 [scene]（教师在编辑器场景面板里**显式配置**的那一份）。
  ///
  /// 演示页严格「按配置显示」——只有教师真正关联过的场景才渲染；AI 起草或旧数据
  /// 内嵌在 [payload] 里的 SceneSpec 不再被当作场景渲染（那会让「我没配却显示了」）。
  /// 旧 payload-only 课件若想保留场景，需在编辑器里重新关联一次（落到顶层 [scene]）。
  Map<String, dynamic>? get resolvedScene => scene;
}
