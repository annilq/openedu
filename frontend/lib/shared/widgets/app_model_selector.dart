import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_inputs.dart';
import '../../features/tutor/presentation/providers/models_notifier.dart';

/// 可选 AI 模型的统一选择器（App* 语义组件，跨特性复用）。
///
/// - 选项首项为「默认（后端自动）」，值为 null（以空串 '' 在 picker 中表示）。
/// - 数据来自 [modelsNotifierProvider]（GET /models，仅家长可见自定义模型）。
/// - 未加载时自动触发一次拉取；调用方也可在 initState 预加载。
class AppModelSelector extends ConsumerWidget {
  final String? selected; // 模型 id；null = 默认（后端自动）
  final ValueChanged<String?> onChanged;
  final String label;

  const AppModelSelector({
    super.key,
    this.selected,
    required this.onChanged,
    this.label = 'AI 模型',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(modelsNotifierProvider);

    // 未加载过则自动拉取一次（POST/GET 拦截器已注入鉴权）。
    if (state is ModelsInitial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(modelsNotifierProvider.notifier).load();
      });
    }

    final values = <String>[''];
    final labels = <String>['默认（后端自动）'];
    if (state is ModelsLoaded) {
      for (final m in state.resp.builtin) {
        values.add(m.id);
        labels.add('${m.label}（内置）');
      }
      for (final m in state.resp.custom) {
        values.add(m.id);
        labels.add(m.isDefault ? '${m.label}（默认）' : m.label);
      }
    }

    final current = selected ?? '';
    return AppPickerField<String>(
      label: label,
      values: values,
      labels: labels,
      value: current,
      onChanged: (v) => onChanged(v.isEmpty ? null : v),
    );
  }
}
