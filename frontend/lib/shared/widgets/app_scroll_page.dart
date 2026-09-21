import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_content_frame.dart';

/// 家长端「滚动内容页」骨架：`SingleChildScrollView` + 宽度收口 + 纵向分区。
///
/// 收口前这 14 行在 **7 个页面里一字不差地抄了 7 遍**（overview / task_form /
/// tutor_logs / model_management / child_mastery / task_review / wrong_questions）。
/// 它是 ADR-0058「Rule of Two」最典型的一例：第二次抄就该收口，结果抄到第七次。
///
/// 为什么连 padding 一起收进来而不是留参数：这 7 处**连数值都一样**
/// （`lg / md / lg / xl2` + `topLeft` + `stretch`）。抽组件时给 3 个可调参数
/// 等于把「本该统一的版式」重新开放成「每处可微调」——那是把收口又退回去。
/// 需要不同版式的页面（如练习页通栏）继续自己写，不要给本组件加开关。
///
/// ⚠️ 只管**纵向滚动的整页**；列表型页面（分页 / 懒加载）走
/// `AppPagingCardList` 那套脚手架，不要用它包——会退化成非懒加载。
class AppScrollPage extends StatelessWidget {
  /// 纵向分区；已自带 `stretch` 与宽度收口，调用点不要再套一层 `AppContentFrame`。
  final List<Widget> children;

  const AppScrollPage({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
      child: AppContentFrame(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
