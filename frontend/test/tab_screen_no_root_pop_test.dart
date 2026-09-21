import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 壳内页签（**非 push 路由**）不得直接 `Navigator.pop` —— 静态守卫。
///
/// 线上事故：娃娃端复习页是导航空壳 `IndexedStack` 里的一个页签，底下没有可 pop
/// 的路由。页内的 `Navigator.of(context).pop()` 弹的是**根导航栈的最后一条路由**
/// （整个 App）：点一下白屏，下一次重建撞 `NavigatorState.build` 的
/// `assert(_history.isNotEmpty)`。
///
/// 为什么不能靠 `flutter analyze`：弹错栈不是类型错误，是**运行时语义**——跟
/// 「裸 GestureDetector 不进焦点树」同一类洞，只能静态扫。
///
/// 白名单是**挂载方式**而不是「文件清单」：列的是「由壳常驻挂载、从不被 push 的
/// 页面」。push 出来的整页（`assistant_chat_page` / `export_preview_page` /
/// `practice_screen`）不在此列——它们真的在路由栈上，pop 是对的。
const _tabMountedScreens = <String>[
  // 娃娃端底部导航的五个页签（home_screen 的 IndexedStack）
  'lib/features/home/presentation/widgets/child_home.dart',
  'lib/features/review/presentation/screens/review_screen.dart',
  'lib/features/review/presentation/widgets/review_empty_view.dart',
  'lib/features/review/presentation/screens/wrong_questions_screen.dart',
  'lib/features/home/presentation/screens/child_mastery_screen.dart',
];

void main() {
  test('壳内页签不得直接 pop 根导航栈（白屏 + _history 断言）', () {
    final offenders = <String>[];
    for (final rel in _tabMountedScreens) {
      final file = File(rel);
      expect(file.existsSync(), isTrue,
          reason: '请在 frontend/ 目录下运行（flutter test 的 CWD）: $rel');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = _stripLineComment(lines[i]);
        // maybePop 在根栈只剩一条路由时是 no-op，是合规退路。
        if (!code.contains('.pop(') || code.contains('maybePop')) continue;
        offenders.add('$rel:${i + 1}: ${code.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '这些页面挂在壳的页签里，不在路由栈上——pop 会弹掉根路由（整个 App）。\n'
          '改成由组合根注入出口回调（如 `ReviewScreen.onExit`），'
          '或在没有可 pop 路由时用 `Navigator.maybePop`。\n'
          '${offenders.join('\n')}',
    );
  });
}

/// 去掉行注释后再判：本仓多处注释在解释「为什么不能用 pop」，那不算违规。
String _stripLineComment(String line) {
  final i = line.indexOf('//');
  return i < 0 ? line : line.substring(0, i);
}
