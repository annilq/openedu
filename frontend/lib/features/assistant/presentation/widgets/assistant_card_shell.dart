import 'package:flutter/widgets.dart';

import '../../../../shared/widgets/app_card.dart';

/// 卡片容器：`surfaceRaised` 底 + 墨黑描边 + card 圆角（与 [AppCard] 同款面）。
///
/// 不设外边距——卡片之间的间距由调用方控制（首个卡片贴气泡，后续卡片留间距）。
class AssistantCardShell extends StatelessWidget {
  final Widget child;

  const AssistantCardShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // 新粗野卡片容器：2px 墨黑描边 + 无模糊硬阴影（ADR-0044），由 AppCard 统一定义。
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        margin: EdgeInsets.zero,
        child: child,
      ),
    );
  }
}
