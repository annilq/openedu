import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';

/// 学科三重编码的**形状层**守卫（`.impeccable.md` §Design Principles 4）。
///
/// 规则：「色相 + 明度差 + 几何标记（数学■ / 语文● / 英语▲），**禁止仅靠颜色
/// 区分学科**」。语文 `#FF6B5A`(coral) 与英语 `#FFD43B`(yellow) 同属暖色系、
/// 明度接近，在红绿色盲下趋同——形状层就是为这两门课兜底的。
///
/// 形状层的出口是 `_TagChip`（`AppTags.subject` 内部）：它在 chip 上渲染
/// `SubjectMarkIcon(mark: key.mark)`。
///
/// **为什么必须守着**：把 `leading` 去掉或换成纯色点之后，颜色通道照旧工作，
/// 界面在正常色觉下**看不出任何异常**，`flutter analyze` 也不会响——只有这里会红。
void main() {
  testWidgets('学科 chip 带几何标记，且映射与 SubjectKey 一致', (tester) async {
    const expected = <SubjectKey, SubjectMark>{
      SubjectKey.math: SubjectMark.square,
      SubjectKey.chinese: SubjectMark.circle,
      SubjectKey.english: SubjectMark.triangle,
    };

    for (final entry in expected.entries) {
      await tester.pumpWidget(_host(AppTags.subject(entry.key)));

      final marks = find.byType(SubjectMarkIcon);
      expect(marks, findsOneWidget,
          reason: '${SubjectAccent.label(entry.key)} 的学科 chip 丢了几何标记——'
              '学科就只剩「颜色」一重编码，红绿色盲下语文/英语会趋同。');
      expect(tester.widget<SubjectMarkIcon>(marks).mark, entry.value,
          reason: '${SubjectAccent.label(entry.key)} 的几何标记映射错了。');
    }
  });

  test('学科 → 几何标记的映射是唯一事实源，UI 层不得自行 switch', () {
    // 这条断言的价值在于「加了新学科却忘了给形状」时会红。
    for (final key in SubjectKey.values) {
      expect(key.mark, isA<SubjectMark>(),
          reason: 'SubjectKey.$key 未登记几何标记（见 app_theme.dart 的 SubjectMarkOf）。');
    }
    expect(SubjectKey.math.mark, isNot(SubjectKey.chinese.mark));
    expect(SubjectKey.chinese.mark, isNot(SubjectKey.english.mark));
    expect(SubjectKey.math.mark, isNot(SubjectKey.english.mark));
  });
}

/// 最小宿主：必须显式传 `theme:`——`ShadApp.custom` 不传会退回 shadcn 默认主题，
/// 量到的浮层内边距/按钮高度都不是产品的值。
Widget _host(Widget child) => ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
      appBuilder: (_) => CupertinoApp(
        home: Center(child: child),
      ),
    );
