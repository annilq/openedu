// 复现「改了学期后知识点 options 不变」的**真实症状**（ADR-0061 §L）。
//
// 已排除的可能（先测后判）：
//   ✅ provider 层：family key 含学期 → 三次请求/三份不同数据（task_semester_options_test）
//   ✅ 视图层：编辑器收到的 knowledgePointOptions 确实换了（task_form_semester_switch_test）
//   ❌ 剩下唯一可疑点：**已打开的 ShadSelect 下拉**。
//
// 机制（shadcn_ui 0.56.3 `ShadSelect`）：
//   - 选中值存在 `ShadSelectController`（State 内，`initState` 用 `initialValue` 播种）；
//   - `didUpdateWidget` **只在 `initialValue` 变化时**同步 controller；
//   - 下拉列表在 `_ShadSelectState.build` 里读`widget.options`——但它被包在
//     `ShadPopover` 的 child 里，**首次打开后就被缓存**，父级换options 不再重建它。
//   而 `AppPickerField` 没给 `ShadSelect` 传 key，父级重建时按位置复用同一个 State。
//
// 症状即：学期切了 → 目录数据变了 → 但**下拉里还是旧学期那一串**。
// 本测试钉住「换学期后新选项必须可达」，修复前它红、修复后绿。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_inputs.dart';

Widget _wrap(Widget child) {
  return ShadApp.custom(
    theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
    appBuilder: (context) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 900, height: 700, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('换 options 后下拉必须列出新项（ShadSelect 不得缓存旧列表）',
      (tester) async {
    var options = const ['上册A', '上册B', '上册C'];
    String? picked;

    await tester.pumpWidget(_wrap(
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: AppPickerField<String>(
                label: '知识点',
                values: options,
                labels: options,
                value: null,
                onChanged: (v) => picked = v,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 模拟「先切到上学期并打开下拉看一眼」
    await tester.tap(find.byType(ShadSelect<String>));
    await tester.pumpAndSettle();
    expect(find.text('上册A'), findsOneWidget);

    // 关掉下拉，父级把 options 换成下学期
    await tester.tapAt(const Offset(10, 10)); // 点空白关闭
    await tester.pumpAndSettle();

    options = const ['下册X', '下册Y'];
    await tester.pumpWidget(_wrap(
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: AppPickerField<String>(
                label: '知识点',
                values: options,
                labels: options,
                value: null,
                onChanged: (v) => picked = v,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 再次打开下拉：应当看到下学期的新项
    await tester.tap(find.byType(ShadSelect<String>));
    await tester.pumpAndSettle();

    expect(find.text('下册X'), findsOneWidget,
        reason: '下拉应列出换学期后的新项');
    expect(find.text('上册A'), findsNothing,
        reason: '旧学期的项不该还留在下拉里');
  });
}
