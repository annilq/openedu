import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/domain/figures.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_buttons.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../../shared/widgets/scene_interpreter/reflection_scene_data.dart';
import '../../../../../shared/widgets/scene_interpreter/reflection_figure_gallery.dart';
import '../../../../../shared/widgets/scene_interpreter/reflection_scene_dialog.dart';
import '../../../domain/repositories/material_repository.dart'
    show SceneLibraryEntry;
import '../../../providers/knowledge_manage_provider.dart';
import 'scene_developer_guide.dart';
import 'scene_library_picker.dart';

/// 知识点交互讲解编辑器（ADR-0061）：家长为一个已落库知识点编写默认交互讲解模板。
///
/// 首版仅暴露 `reflection` 一种 kind（图形的运动·轴对称）——选图形 + 调默认对称轴
/// 参数，右侧/下方实时预览对折效果，保存后写入 [KnowledgePoint.scenes]。
/// 多 kind 时此处扩展「kind 选择」即可，渲染仍走 [SceneInterpreter]。
///
/// **未配置（[initialScenes] 为空）时本弹窗不渲染 reflection 编辑表单**：交互讲解
/// 模板是开发者实现的场景组件、不是家长在前端手配的，所以改弹开发者指引——以现有
/// `reflection` 组件为范本新建一个 kind（见 [SceneDeveloperGuide]），而非误导家长去把
/// 一个「平移」知识点配成轴对称模板。
///
/// **学期维度是「显示」而非「选择」**（ADR-0061 §J）：模板挂在**某个具体知识点**上，
/// 而知识点的学期在建行时就定了（唯一约束含 semester）。所以本弹窗不做学期切换
/// （那等于移动知识点、且会撞唯一约束），只把该知识点的**作用范围**显式摆出来——
/// 否则家长在「整学年」并集视图里点开一个上学期知识点，却完全看不出自己配的是
/// 上学期，讲解时命中哪个学期也无从预期。
class KnowledgePointSceneEditor extends ConsumerStatefulWidget {
  final String kpId;

  /// 该知识点的名字（弹窗标题要让人知道在配哪个点）。
  final String kpName;

  /// 作用范围：学科 / 年级 / 学期。'' = 整学年。
  final String subject;
  final int grade;
  final String semester;

  final List<Map<String, dynamic>>? initialScenes;

  /// 关闭/保存后的出口：经 [HomeScreen] 的单一 `_go(back)` 回落，而非裸
  /// `Navigator.pop`（弹窗态下 pop 只是关弹窗，页面态下 pop 会弹根栈 → 白屏，
  /// ADR-0059）。null = 仍当弹窗用（知识点行旧路径），回落 `Navigator.pop` 关弹窗。
  final VoidCallback? onBack;

  const KnowledgePointSceneEditor({
    super.key,
    required this.kpId,
    required this.kpName,
    required this.subject,
    required this.grade,
    required this.semester,
    this.initialScenes,
    this.onBack,
  });

  @override
  ConsumerState<KnowledgePointSceneEditor> createState() =>
      _KnowledgePointSceneEditorState();
}

class _KnowledgePointSceneEditorState
    extends ConsumerState<KnowledgePointSceneEditor> {
  /// 当前选中的图形预设（家长面板仍是「挑预设 + 调轴」，ADR-0061 §O）。
  /// 儿童端拿到的 spec 里是**顶点**，不依赖这个预设是否还存在。
  late FigureShape _shape;
  bool _saving = false;

  /// 从内置场景库选中的场景（未配置知识点时的模板起点）。null = 还没选。
  ///
  /// 必须留住它：「未配置」的判定要跟着翻转，选了场景就该立刻给出对应的编辑
  /// 表单——否则点完「选这个」界面纹丝不动，会被当成按钮坏了。
  SceneLibraryEntry? _pickedScene;

  @override
  void initState() {
    super.initState();
    // 取首个 reflection 模板作初值；无则按首个预设（房子，竖轴）默认。
    final initialScene = widget.initialScenes?.firstWhere(
          (e) => e['kind'] == 'reflection',
          orElse: () => <String, dynamic>{},
        ) ??
        const <String, dynamic>{};
    final data = ReflectionSceneData.fromSpec(initialScene);
    // 新形 spec 只带顶点（无 figure key）→ 按顶点反查是哪个内置预设，回显选中态。
    _shape = _matchShapeByPoints(data.points) ?? kFigureShapes.first;
  }

  /// 选一个内置场景作模板起点。
  void _pickScene(SceneLibraryEntry entry) {
    setState(() {
      _pickedScene = entry;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 关闭出口：页面态走 [onBack]（回落 `back` 页），弹窗态回落 `Navigator.pop`。
  void _close() {
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// 由当前编辑态构造 SceneSpec（kind=reflection）。
  ///
  /// ADR-0083 决策 5：产出**纯几何** `{kind, points, edges}`——轴参数 / controls /
  /// 引导文案 / 标题由 kind 外壳提供，不再进 spec；「是否允许儿童拖轴」是渲染层的
  /// 展示关切（[ReflectionSceneData.showAxisControls]），也不是 spec 字段。
  Map<String, dynamic> _buildSpec() {
    final points = _shape.vertices
        .map((v) => <double>[v.x, v.y])
        .toList(growable: false);
    return buildReflectionSceneSpec(
      kind: _pickedScene?.kind ?? 'reflection',
      points: points,
      edges: closedEdges(points.length),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(knowledgeManageProvider.notifier)
          .saveScenes(widget.kpId, [_buildSpec()]);
      if (mounted) _close();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.show(context, '保存失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    // 未配置（initialScenes 为空）时，本弹窗不渲染 reflection 编辑表单——交互讲解
    // 模板是开发者实现的组件、不是家长在前端手配的，所以弹开发者指引（[SceneDeveloperGuide]），
    // 告诉开发者怎样以 reflection 组件为范本新建本知识点所需 kind，而非误导家长把
    // 「平移」类知识点配成轴对称模板。
    final hasScenes =
        widget.initialScenes != null && widget.initialScenes!.isNotEmpty;
    // 未配置**且**还没从内置场景库选定起点 → 不渲染参数表单（这条纪律不变）。
    final unconfigured = !hasScenes && _pickedScene == null;
    // 弹窗高度受屏高限制，而内容（标题 + 作用域条 + 图形选择 + 3 个轴滑块 +
    // 预览画布 + 说明 + 保存）最坏情况会超出——套一层滚动兜底，任何屏高/字号
    // 组合下都不会再出现 RenderFlex 溢出。
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 未配置时标题不再硬编码「轴对称」——否则「平移」类知识点点开
                  // 也显示成轴对称编辑器，造成「这是别的点」的错觉。
                  Text(
                    unconfigured
                        ? '交互讲解模板（未配置）'
                        : '交互讲解（${_pickedScene?.title ?? '轴对称'}）',
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.kpName,
                    style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            AppIconAction(
              icon: Icons.close,
              iconSize: 18,
              semanticLabel: '关闭',
              onPressed: _close,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _scopeBanner(context),
        const SizedBox(height: AppSpacing.md),
        if (unconfigured) ...[
          // 内置场景由后端下发（ADR-0073）：选一个即拿它登记的默认参数作模板
          // 起点，不必手填结构。清单拉不到时该部件自行隐身，不打扰编辑。
          SceneLibraryPicker(onPick: _pickScene),
          const SizedBox(height: AppSpacing.md),
          // 未配置 = 没有可渲染模板。交互讲解模板是开发者实现的组件，不是家长
          // 在前端手配的，所以这里给开发者看「怎样以 reflection 为范本新建 kind」
          // 的指引，而非渲染一份误导性的轴对称编辑表单。
          const SceneDeveloperGuide(),
        ]
        else ...[
          // 图形选择改为画廊（ADR-0061 §V，与题目选项同套组件）：11 个平面图形铺成
          // 网格，点一个即设为模板图形并弹真正的对折演示，下方滑块再微调它的默认
          // 对称轴。取代原下拉选择器——下拉里看不到图形长什么样，家长只能盲选。
          ReflectionFigureGallery(
            figures: kFigureShapes,
            selectedKey: _shape.key,
            optionLabels: const <String, String>{},
            hint: '点一个图形设为「默认讲解」并打开对折演示；'
                '儿童端可在演示里自己拖动对称轴去验证。',
            onOpen: (figure) {
              setState(() => _shape = figure);
              // 画廊只画缩略图，真正的可调演示在弹窗里（同一个 ReflectionSceneWidget）。
              // ADR-0083 后对称轴初值归 kind 外壳，面板不再各自持久化轴参数。
              ReflectionSceneDialog.show(
                context,
                data: ReflectionSceneData.fromSpec(_buildSpec())
                    .copyWith(figureLabel: figure.label),
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton(
                  label: _saving ? '保存中…' : '保存讲解',
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
        ],
      ),
    );
  }

  /// 作用范围条（ADR-0061 §J）：这个模板会作用在哪些题上。
  ///
  /// 之所以必须显式摆出来：模板的匹配规则是「先精确同学期 → 回落整学年」
  /// （见后端 `resolve_scene_spec_for_question`），家长不知道当前配的是哪个学期
  /// 的模板，就无法预期讲解时会不会命中。整学年模板额外说明它是**兜底**——
  /// 同学期有专属模板时轮不到它。
  Widget _scopeBanner(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    final isYearWide = widget.semester.isEmpty;
    final accent = isYearWide ? app.onSurfaceVariant : app.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        border: Border.all(color: accent, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('作用范围', style: text.labelMedium),
              AppTags.normal('${widget.grade}年级'),
              AppTags.normal(widget.subject),
              AppTags.normal(isYearWide ? '整学年' : widget.semester),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isYearWide
                ? '整学年兜底模板：仅当题目没有同学期的专属模板时才生效。'
                : '仅作用于此学期（${widget.semester}）的题目；'
                    '其他学期若有专属模板则不生效。',
            style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

}

/// 按顶点反查内置预设（新形 scene 只带顶点、无 figure key，用于回显选中态）。
///
/// 逐点比对（容差 1e-6）：顶点是权威几何，命中即认为「这条 scene 是这个预设」。
/// 命中不了返回 null（未知图形，属正常——用户可能在画板里画了库外图形）。
FigureShape? _matchShapeByPoints(List<Offset> points) {
  for (final f in kFigureShapes) {
    if (f.vertices.length != points.length) continue;
    var same = true;
    for (var i = 0; i < points.length; i++) {
      if ((f.vertices[i].x - points[i].dx).abs() > 1e-6 ||
          (f.vertices[i].y - points[i].dy).abs() > 1e-6) {
        same = false;
        break;
      }
    }
    if (same) return f;
  }
  return null;
}

