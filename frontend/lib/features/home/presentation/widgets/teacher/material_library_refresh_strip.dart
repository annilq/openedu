import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';

/// 资料库列表上方的「刷新中」行内提示：小转圈 + 文案。
///
/// 存在的理由：上传 / 向量化 / 删除 / 移动每个动作都会经历一段
/// `state.loading`，旧视图此时把整块列表换成居中转圈——已上传的资料集体从
/// 屏上消失，页面像坏了一样（用户实测：上传时页面空白 loading、已上传列表
/// 不显示）。现在列表常驻，只用这条轻量提示交代「在刷新」。
///
/// 仅用于「有内容可保留」时的刷新态；首屏空列表走整块 [AppLoading]。
class MaterialLibraryRefreshStrip extends StatelessWidget {
  const MaterialLibraryRefreshStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(LucideIcons.loaderCircle, size: 14, color: app.onSurfaceVariant)
              .animate(onPlay: (c) => c.repeat())
              .rotate(
                begin: 0,
                end: 1,
                duration: const Duration(milliseconds: 900),
                curve: Curves.linear,
              ),
          const SizedBox(width: AppSpacing.sm),
          Text('正在刷新…',
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
        ],
      ),
    );
  }
}
