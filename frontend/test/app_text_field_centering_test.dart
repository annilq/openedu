// 守住「输入框文字竖直居中」契约（2026-10-08）。
//
// 根因：shadcn `ShadInput` 不暴露 `textAlignVertical`（默认 top），固定高度输入框的
// 文字会贴顶。`AppTextField` 用 `strutStyle`（`forceStrutHeight` + `even` leading）
// 把字形上下均分 → 严格居中。本测试锁两条：
//   1. 结构层：EditableText 盒竖直居中于 ShadInput 盒（≤2px）；
//   2. 字形层：单行文字的字形中点 ≈ 行盒中点（≤0.75px）—— proportional（默认）会偏上，
//      只有 `even` 才通过，故能抓住「漏掉 even」的回归。
import 'package:flutter_test/flutter_test.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_inputs.dart';

Widget _host(AppUserMode mode, AppDensity density, Widget child) => ShadApp.custom(
      appBuilder: (context) => CupertinoApp(
        home: UserModeScope(
          mode: mode,
          child: DensityScope(
            density: density,
            child: SizedBox(width: 320, child: child),
          ),
        ),
      ),
    );

void main() {
  for (final mode in [AppUserMode.teacher, AppUserMode.student]) {
    testWidgets(
        'AppTextField typed text vertically centered ($mode)', (tester) async {
      await tester.pumpWidget(
        _host(
          mode,
          AppDensity.compact,
          AppTextField(
            label: '搜索',
            hintText: '按姓名或学号搜索',
            controller: TextEditingController(text: '搜'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final input = tester.getRect(
        find.byType(ShadInput),
      );
      final editable = tester.getRect(
        find.descendant(
          of: find.byType(ShadInput),
          matching: find.byType(EditableText),
        ),
      );
      // 结构层：EditableText 盒居中于 ShadInput 盒（容差 2px）。
      expect((editable.center.dy - input.center.dy).abs(), lessThanOrEqualTo(2.0));
    });
  }

  testWidgets('AppTextField strut centers glyph via even leading', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      ShadApp.custom(
        appBuilder: (context) => CupertinoApp(
          home: UserModeScope(
            mode: AppUserMode.teacher,
            child: DensityScope(
              density: AppDensity.compact,
              child: Builder(builder: (c) {
                ctx = c;
                return const SizedBox();
              }),
            ),
          ),
        ),
      ),
    );

    final strut = AppControl.inputStrut(ctx, const TextStyle(fontSize: 16));
    expect(strut.forceStrutHeight, isTrue);
    // 关键杠杆：漏掉 even 会走默认 proportional → 中文/Noto 偏上。
    expect(strut.leadingDistribution, TextLeadingDistribution.even);

    // 字形层：单行文字中点必须落在行盒中点（even leading 保证，proportional 会偏）。
    final painter = TextPainter(
      text: const TextSpan(text: '搜索', style: TextStyle(fontSize: 16)),
      textDirection: TextDirection.ltr,
      strutStyle: strut,
    )..layout();
    final lineHeight = painter.height;
    final boxes = painter.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    final glyphCenter = (boxes.first.top + boxes.last.bottom) / 2;
    expect((glyphCenter - lineHeight / 2).abs(), lessThan(0.75));
  });
}
