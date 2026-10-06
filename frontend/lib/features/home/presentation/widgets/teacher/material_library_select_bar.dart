import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_dialog.dart';
import '../../../../../shared/widgets/app_select_strip.dart';
import '../../../../materials/providers/material_library_provider.dart';

/// 资料列表的多选操作条（多选删除入口）。
///
/// 单独成文件的两个原因：
/// 1. 资料库页本身已经逼近 ADR-0058 的 400 行上限，多选的「状态 + 确认弹窗 +
///    文案」再塞进去就必然超限；
/// 2. 它是一块自洽的 UI——自己读 provider 的勾选状态、自己走删除，外部只需把它
///    放在列表上方，不需要反向传一堆回调。
///
/// **为什么组合 [AppSelectStrip] 而不是重写**：全站的多选语言（「多选」入口 /
/// 「已选 N 项」/「全选」）已经在那里收口过了，这里再手写一份就会出现第二种
/// 「全选」按钮。删除按钮是本页特有的，才在这里追加。
class MaterialLibrarySelectBar extends ConsumerWidget {
  const MaterialLibrarySelectBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = AppTheme.colorsOf(context);
    final state = ref.watch(materialLibraryNotifierProvider);
    final count = state.selectedMaterialIds.length;
    final notifier = ref.read(materialLibraryNotifierProvider.notifier);

    return Row(
      children: [
        Expanded(
          child: AppSelectStrip(
            selecting: state.selecting,
            selectedCount: count,
            totalCount: state.materials.length,
            onEnterSelecting: notifier.enterSelecting,
            onToggleSelectAll: notifier.toggleSelectAllMaterials,
            hintText: '勾选要删除的资料',
          ),
        ),
        if (state.selecting) ...[
          AppTextAction(label: '取消', onPressed: notifier.exitSelecting),
          AppTextAction(
            label: count > 0 ? '删除（$count）' : '删除',
            color: app.error,
            semanticLabel: count > 0 ? '删除选中的 $count 份资料' : '删除选中的资料',
            onPressed: count == 0 ? null : () => _confirmDelete(context, ref, count),
          ),
        ],
      ],
    );
  }

  /// 删除前必须说清**连带影响**：除了资料本身，还会顺带清理「只由这些资料产生、
  /// 且教师从未确认过」的知识点。不说明的话，教师删完发现知识点管理里少了一片，
  /// 会当成数据丢了。已确认的知识点不会被带走——那条也要讲清楚，否则教师以为
  /// 删了资料知识点还在是 bug。
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final ok = await AppDialog.confirm(
      context,
      title: const Text('删除资料'),
      content: Text(
        '确认删除这 $count 份资料？资料与其切片会一并删除，不可恢复。\n\n'
        '同时会自动清理「只由这些资料产生、且你未确认过」的知识点；'
        '你已经确认过的知识点不受影响，需要删除请到「知识点管理」里手动删。',
      ),
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true) return;
    await ref
        .read(materialLibraryNotifierProvider.notifier)
        .bulkDeleteMaterials();
  }
}
