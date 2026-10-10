import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/figures.dart';
import '../../domain/providers/figure_library_provider.dart';
import '../../theme/app_theme.dart';
import '../app_actions.dart';

import 'reflection_figure_gallery.dart';

// =====================================================================
// §图库画廊（ADR-0083 决策 7）
//
// **创作 UI 的画廊**：打开即按需拉一次图库（会话内一次性、不落盘），拉取中给占位、
// 失败给可重试的提示，成功后渲染哑组件 [ReflectionFigureGallery]。
//
// 为什么单独一层而不是让 [ReflectionFigureGallery] 自己取数：画廊是**哑组件**
// （只吃一个图形列表，不认识 provider），这样它能在纯几何、显式子集（课件 curated）
// 等语境里复用，也便于测试直接构造。取数是「跨 feature 的共享数据」这个关切，
// 落在这里最薄。
//
// 哪些画廊用它：场景库「默认演示图形」配置区、知识点交互讲解编辑器（创作 UI）。
// 运行时的选项组画廊（`SceneOptionGroup`）**不走这层**——它必须零图库依赖
// （题库 / 错题 / AI 讲解的观感一字不变，见 ticket 05 说明）。
// =====================================================================

/// 打开时按需拉图库的图形画廊（创作 UI 用）。
class FigureLibraryGallery extends ConsumerWidget {
  /// 点开某个图形。
  final void Function(FigureShape figure) onOpen;

  /// 图形 key → 选项标号（「A」「B」…）。创作 UI 一般为空。
  final Map<String, String> optionLabels;

  /// 当前选中的图形 key（编辑器高亮「现在配的是哪张」）。
  final String? selectedKey;

  /// 网格上方的一句话说明。
  final String? hint;

  /// 是否按传入顺序渲染（见 [ReflectionFigureGallery.preserveOrder]）。
  final bool preserveOrder;

  /// 是否画 play 角标（见 [ReflectionFigureGallery.showPlayBadge]）。
  final bool showPlayBadge;

  const FigureLibraryGallery({
    super.key,
    required this.onOpen,
    this.optionLabels = const <String, String>{},
    this.selectedKey,
    this.hint,
    this.preserveOrder = false,
    this.showPlayBadge = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    final async = ref.watch(figureLibraryProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: Text('正在读取图形库…')),
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('图形库读取失败', style: text.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '图形库需要连接服务才能读取。请检查网络后重试（$e）',
            style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextAction(
            label: '重试',
            onPressed: () => ref.invalidate(figureLibraryProvider),
          ),
        ],
      ),
      data: (figures) {
        if (figures.isEmpty) {
          return Text(
            '图形库是空的。可以在画板上画一个图形存进去。',
            style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
          );
        }
        return ReflectionFigureGallery(
          figures: figures,
          optionLabels: optionLabels,
          selectedKey: selectedKey,
          hint: hint,
          preserveOrder: preserveOrder,
          showPlayBadge: showPlayBadge,
          onOpen: onOpen,
        );
      },
    );
  }
}
