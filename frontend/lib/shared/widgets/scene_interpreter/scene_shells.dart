/// 场景**交互外壳**（ADR-0083 决策 4）：按 kind 统一给定交互参数与引导文案。
///
/// 为什么要有它：`SceneSpec` 已瘦成纯几何 `{kind, points, edges}`（决策 5），
/// 而「对称轴初值多少、要不要播放条、引导语说什么」是**按 kind 统一**的交互部分，
/// 不属于任何一条具体场景。它们收进这里（后端 `scene_templates.SCENE_LIBRARY`
/// 的同构镜像）——渲染时按 `spec['kind']` 取外壳，运行时**零几何依赖**。
///
/// 与后端外壳的关系：后端下发 `defaults`（编辑器预填用，含 `axisAngle` 等）时优先
/// 采信；纯运行时 spec 不带这些字段，则回落到本文件的默认值。两处取值由
/// [SceneShell.fromSource] 统一，避免「编辑器一套、播放一套」再次镜像漂移。
library;

/// 一种场景类型的交互外壳。
class SceneShell {
  /// 场景类型（稳定契约，与后端 `_KIND` 双登记）。
  final String kind;

  /// 展示名（场景库清单 / 编辑器 / 课件选择器的标签；SceneSpec 已无 title）。
  final String title;

  /// 对称轴角度初值（度）。
  final double axisAngle;

  /// 对称轴水平 / 垂直位置（归一化 0..1）。
  final double axisX;
  final double axisY;

  /// 播放 / 暂停是否显示。
  final bool controlsPlay;

  /// 对折进度是否可拖动。
  final bool controlsScrub;

  /// 引导文案（中性：不报「有几条」这类答案）。
  final String narrative;

  const SceneShell({
    required this.kind,
    required this.title,
    this.axisAngle = 90,
    this.axisX = 0.5,
    this.axisY = 0.5,
    this.controlsPlay = true,
    this.controlsScrub = true,
    this.narrative = '',
  });

  /// 从 spec / 外壳 map 解析外壳：**显式字段优先，缺省回落该 kind 的默认外壳**。
  ///
  /// 这样两种来源都对：编辑器传后端 `defaults`（含 axisAngle 等）→ 用后端的值；
  /// 运行时传纯几何 spec（无这些字段）→ 用本文件默认值。
  static SceneShell fromSource(String? kind, Map<String, dynamic> source) {
    final base = shellFor(kind);
    final controls = source['controls'];
    final controlsMap = controls is Map ? controls : null;
    return SceneShell(
      kind: base.kind,
      title: (source['title'] as String?) ?? base.title,
      axisAngle: (source['axisAngle'] as num?)?.toDouble() ?? base.axisAngle,
      axisX: (source['axisX'] as num?)?.toDouble() ?? base.axisX,
      axisY: (source['axisY'] as num?)?.toDouble() ?? base.axisY,
      controlsPlay: (controlsMap?['play'] as bool?) ?? base.controlsPlay,
      controlsScrub: (controlsMap?['scrub'] as bool?) ?? base.controlsScrub,
      narrative: (source['narrative'] as String?) ?? base.narrative,
    );
  }
}

/// 各 kind 的默认交互外壳（与后端 `scene_templates.SCENE_LIBRARY` 同构）。
const Map<String, SceneShell> kSceneShells = <String, SceneShell>{
  'reflection': SceneShell(
    kind: 'reflection',
    title: '轴对称演示',
    axisAngle: 90,
    axisX: 0.5,
    axisY: 0.5,
    controlsPlay: true,
    controlsScrub: true,
    narrative: '点播放看沿对称轴对折后两侧能否完全重合；'
        '也可以自己旋转、平移对称轴，找出所有能重合的角度。',
  ),
};

/// 取某 kind 的外壳；未知 kind 回落 reflection（渲染层的「永不空」安全网）。
SceneShell shellFor(String? kind) =>
    kSceneShells[kind] ?? kSceneShells['reflection']!;
