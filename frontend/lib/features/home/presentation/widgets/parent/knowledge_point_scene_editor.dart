import 'package:flutter/material.dart' show Icons, Slider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_buttons.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../../shared/widgets/scene_interpreter/reflection_scene.dart';
import '../../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';
import '../../../providers/knowledge_manage_provider.dart';

/// 知识点交互讲解编辑器（ADR-0061）：教师为一个已落库知识点编写默认交互讲解模板。
///
/// 首版仅暴露 `reflection` 一种 kind（图形的运动·轴对称）——选图形 + 调默认对称轴
/// 参数，右侧/下方实时预览对折效果，保存后写入 [KnowledgePoint.scenes]。
/// 多 kind 时此处扩展「kind 选择」即可，渲染仍走 [SceneInterpreter]。
class KnowledgePointSceneEditor extends ConsumerStatefulWidget {
  final String kpId;
  final List<Map<String, dynamic>>? initialScenes;

  const KnowledgePointSceneEditor({
    super.key,
    required this.kpId,
    this.initialScenes,
  });

  @override
  ConsumerState<KnowledgePointSceneEditor> createState() =>
      _KnowledgePointSceneEditorState();
}

class _KnowledgePointSceneEditorState
    extends ConsumerState<KnowledgePointSceneEditor> {
  late ReflectionFigure _figure;
  late double _axisAngle;
  late double _axisX;
  late double _axisY;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 取首个 reflection 模板作初值；无则按 house 默认（竖轴）。
    final data = ReflectionSceneData.fromSpec(
      widget.initialScenes?.firstWhere(
            (e) => e['kind'] == 'reflection',
            orElse: () => <String, dynamic>{},
          ) ??
          const <String, dynamic>{},
    );
    _figure = data.figure;
    _axisAngle = data.axisAngle;
    _axisX = data.axisX;
    _axisY = data.axisY;
  }

  /// 由当前编辑态构造 ADR-0061 SceneSpec（kind=reflection）。
  /// 预览用 `editable:false`——默认参数由外层滑块控制，预览仅负责播放对折看效果。
  Map<String, dynamic> _buildSpec() => {
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
          {'key': 'figure', 'label': '图形', 'value': _figure.name},
        ],
        'controls': {'play': true, 'pause': true, 'scrub': true, 'speed': true},
        'narrative': '这是一个轴对称图形，中间虚线是它的对称轴。点击播放对折，'
            '两侧完全重合就是轴对称图形；旋转或平移对称轴偏离真正对称线则不会重合。',
        'outputs': {'isAxisymmetric': true},
        'editable': false,
      };

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(knowledgeManageProvider.notifier)
          .saveScenes(widget.kpId, [_buildSpec()]);
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('交互讲解（轴对称）', style: text.titleMedium),
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
        AppPickerField<String>(
          label: '图形',
          values: const ['house', 'kite', 'arrow', 'para'],
          labels: const [
            '房子（竖轴）',
            '风筝（竖轴）',
            '箭头（横轴）',
            '平行四边形（非对称）',
          ],
          value: _figure.name,
          onChanged: (v) {
            setState(() {
              _figure = ReflectionFigureX.fromName(v);
              _axisAngle = _figure.defaultAxisAngle;
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
        SceneInterpreter(kind: 'reflection', spec: _buildSpec()),
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
