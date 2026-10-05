import 'package:flutter/material.dart' show Icons, Slider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/domain/figures.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_buttons.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../../shared/widgets/scene_interpreter/reflection_scene_data.dart';
import '../../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';
import '../../../providers/knowledge_manage_provider.dart';

/// 知识点交互讲解编辑器（ADR-0061）：教师为一个已落库知识点编写默认交互讲解模板。
///
/// 首版仅暴露 `reflection` 一种 kind（图形的运动·轴对称）——选图形 + 调默认对称轴
/// 参数，右侧/下方实时预览对折效果，保存后写入 [KnowledgePoint.scenes]。
/// 多 kind 时此处扩展「kind 选择」即可，渲染仍走 [SceneInterpreter]。
///
/// **学期维度是「显示」而非「选择」**（ADR-0061 §J）：模板挂在**某个具体知识点**上，
/// 而知识点的学期在建行时就定了（唯一约束含 semester）。所以本弹窗不做学期切换
/// （那等于移动知识点、且会撞唯一约束），只把该知识点的**作用范围**显式摆出来——
/// 否则教师在「整学年」并集视图里点开一个上学期知识点，却完全看不出自己配的是
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

  const KnowledgePointSceneEditor({
    super.key,
    required this.kpId,
    required this.kpName,
    required this.subject,
    required this.grade,
    required this.semester,
    this.initialScenes,
  });

  @override
  ConsumerState<KnowledgePointSceneEditor> createState() =>
      _KnowledgePointSceneEditorState();
}

class _KnowledgePointSceneEditorState
    extends ConsumerState<KnowledgePointSceneEditor> {
  /// 预览画布的最大宽度。场景画布是**边长 = 宽度**的正方形（ADR-0061 §O），
  /// 不压窄就会在高 DPI / 大字号 / 短屏下把弹窗顶出屏幕（实测溢出 306px）。
  static const double _previewMaxWidth = 300;

  /// 当前选中的图形预设（教师面板仍是「挑预设 + 调轴」，ADR-0061 §O）。
  /// 学生端拿到的 spec 里是**顶点**，不依赖这个预设是否还存在。
  late FigureShape _shape;
  late double _axisAngle;
  late double _axisX;
  late double _axisY;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 取首个 reflection 模板作初值；无则按首个预设（房子，竖轴）默认。
    final data = ReflectionSceneData.fromSpec(
      widget.initialScenes?.firstWhere(
            (e) => e['kind'] == 'reflection',
            orElse: () => <String, dynamic>{},
          ) ??
          const <String, dynamic>{},
    );
    _shape = figureByKey(
      kFigureShapes
          .where((f) => f.label == data.figureLabel)
          .map((f) => f.key)
          .firstOrNull,
    );
    _axisAngle = data.axisAngle;
    _axisX = data.axisX;
    _axisY = data.axisY;
  }

  /// 由当前编辑态构造 ADR-0061 SceneSpec（kind=reflection）。
  ///
  /// **同时下发 `points`（顶点）与 `figure`（预设 key）**：顶点是权威（学生端
  /// 纯顶点驱动渲染，ADR-0061 §O），预设 key 供本面板下次打开时回显。
  ///
  /// [editable] 必须**按用途分两处**（ADR-0061 §O/①A）：
  /// - **保存**时传 `true` —— 学生端要能自己旋转 / 平移对称轴去验证每个选项
  ///   是否轴对称，写 false 会把轴控件整个藏掉，等于掐掉最核心的动手环节；
  /// - **本面板预览**传 `false` —— 面板上方已经有 3 个同样的轴滑块了，预览再
  ///   画一遍是纯重复，还会把弹窗撑爆（实测 536 宽弹窗溢出 306px）。
  Map<String, dynamic> _buildSpec({required bool editable}) => {
        'kind': 'reflection',
        'title': '图形的运动（轴对称）',
        'inputs': [
          {
            'key': 'axisAngle',
            'label': '对称轴角度',
            'value': _axisAngle,
            'min': 0,
            'max': 180,
            'step': 1,
            'unit': '度',
          },
          {
            'key': 'axisX',
            'label': '对称轴水平',
            'value': _axisX,
            'min': 0.3,
            'max': 0.7,
            'step': 0.01,
            'unit': '比例',
          },
          {
            'key': 'axisY',
            'label': '对称轴垂直',
            'value': _axisY,
            'min': 0.3,
            'max': 0.7,
            'step': 0.01,
            'unit': '比例',
          },
          {'key': 'figure', 'label': '图形', 'value': _shape.key},
          {
            'key': 'points',
            'label': '顶点',
            'value': _shape.vertices
                .map((v) => [v.x, v.y])
                .toList(growable: false),
          },
        ],
        'controls': {'play': true, 'pause': true, 'scrub': true, 'speed': true},
        'narrative': '这是一个轴对称图形，中间虚线是它的对称轴。点击播放对折，'
            '两侧完全重合就是轴对称图形；旋转或平移对称轴偏离真正对称线则不会重合。',
        'outputs': {'isAxisymmetric': true},
        'editable': editable,
      };

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(knowledgeManageProvider.notifier)
          .saveScenes(widget.kpId, [_buildSpec(editable: true)]);
      if (mounted) Navigator.of(context).pop();
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
                  Text('交互讲解（轴对称）', style: text.titleMedium),
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
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _scopeBanner(context),
        const SizedBox(height: AppSpacing.md),
        AppPickerField<String>(
          label: '图形',
          // 选项来自图形顶点库（ADR-0061 §O 单一事实源），不再硬编码字符串。
          values: kFigureShapes.map((f) => f.key).toList(growable: false),
          labels: [
            for (final f in kFigureShapes)
              // 括号里补一句默认轴/对称性，帮教师理解「为什么箭头是横轴」。
              '${f.label}（${f.defaultAxisAngle == 0 ? '横轴' : '竖轴'}）',
          ],
          value: _shape.key,
          onChanged: (v) {
            setState(() {
              _shape = figureByKey(v);
              // 换图形时轴角度跟随该图形的默认轴（否则从房子切到箭头会停在竖轴、
              // 一开始就不重合，学生以为是错的）。
              _axisAngle = _shape.defaultAxisAngle;
            });
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _slider('对称轴角度', _axisAngle, 0, 180, 1, (v) => setState(() => _axisAngle = v),
            '${_axisAngle.round()}°'),
        _slider('对称轴水平', _axisX, 0.3, 0.7, 0.01, (v) => setState(() => _axisX = v),
            _axisX.toStringAsFixed(2)),
        _slider('对称轴垂直', _axisY, 0.3, 0.7, 0.01, (v) => setState(() => _axisY = v),
            _axisY.toStringAsFixed(2)),
        const SizedBox(height: AppSpacing.sm),
        Text('实时预览（点播放看对折效果）', style: text.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        // 预览不重复轴滑块（面板上方已有），并压窄画布——场景画布是
        // 「边长 = 宽度」的正方形，不压窄会连带把弹窗顶出屏幕。
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _previewMaxWidth),
            child: SceneInterpreter(
              kind: 'reflection',
              spec: _buildSpec(editable: false),
            ),
          ),
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
      ),
    );
  }

  /// 作用范围条（ADR-0061 §J）：这个模板会作用在哪些题上。
  ///
  /// 之所以必须显式摆出来：模板的匹配规则是「先精确同学期 → 回落整学年」
  /// （见后端 `resolve_scene_spec_for_question`），教师不知道当前配的是哪个学期
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

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChanged,
    String display,
  ) {
    final t = AppTheme.textOf(context);
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label, style: t.labelSmall)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 48, child: Text(display, style: t.labelSmall)),
      ],
    );
  }
}
