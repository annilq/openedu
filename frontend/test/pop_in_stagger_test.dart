import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/shared/widgets/app_motion.dart';

/// [PopIn] 错峰入场 + reduce-motion 单一事实源的守卫。
///
/// `app_motion.dart` 开头写着「所有元素共用同一条曲线会『齐步走』」——弹簧解决的
/// 是**不同量级元素**共用曲线的问题；但列表里连排的同级卡片用的是**同一条弹簧**，
/// 齐步起跳的问题原封不动。`PopIn.delay` 存在的唯一理由就是它（本条即 P2-1）。
///
/// **为什么必须守着**：把 `delay` 删掉之后卡片照样一张张正确显示（只是同时），
/// 截图完全看不出来，`flutter analyze` 也不会响。
void main() {
  testWidgets('delay 让同屏元素错峰，而不是齐步起跳', (tester) async {
    await tester.pumpWidget(_host([
      const PopIn(key: ValueKey('pop-a'), child: _Dot()),
      const PopIn(
        key: ValueKey('pop-b'),
        delay: Duration(milliseconds: _stepMs),
        child: _Dot(),
      ),
    ]));
    await tester.pump(const Duration(milliseconds: _stepMs ~/ 2));

    expect(_opacityOf(tester, 'pop-a'), greaterThan(0.0),
        reason: '没有 delay 的那个应当已经开始入场。');
    expect(_opacityOf(tester, 'pop-b'), 0.0,
        reason: '带 delay 的那个在延迟期内必须仍是隐形的——'
            '两个同时动就说明 delay 没生效，回到了「齐步走」。');

    await tester.pump(const Duration(milliseconds: _stepMs));
    await tester.pumpAndSettle();
  });

  testWidgets('延迟一过立刻起跳，不是永久隐身', (tester) async {
    await tester.pumpWidget(_host([
      const PopIn(
        key: ValueKey('pop-b'),
        delay: Duration(milliseconds: _stepMs),
        child: _Dot(),
      ),
    ]));
    expect(_opacityOf(tester, 'pop-b'), 0.0);

    // 必须显式走完延迟：`pumpAndSettle` 只按「还有没有下一帧」推进，
    // 悬挂的 Timer 不排帧，单靠它会直接退出、计时器永不触发。
    await tester.pump(const Duration(milliseconds: _stepMs));
    await tester.pumpAndSettle();

    expect(_opacityOf(tester, 'pop-b'), closeTo(1.0, 0.01),
        reason: '延迟结束后弹簧必须跑完——停在中途等于元素永久半透明。');
  });

  testWidgets('系统开启「减弱动态效果」时跳过延迟与入场', (tester) async {
    await tester.pumpWidget(_host(
      [
        const PopIn(
          key: ValueKey('pop-b'),
          delay: Duration(milliseconds: _stepMs),
          child: _Dot(),
        ),
      ],
      reduceMotion: true,
    ));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pop-b')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
      reason: 'reduce-motion 下 PopIn 应直接呈现最终态：既不等待 delay，也不套 Opacity。',
    );

    // 显式拆树 → dispose 里取消那份还没到点的 Timer，测试尾部不留悬挂计时器。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('reduce-motion 判据只有一处定义', () {
    // 两份实现迟早分叉，而分叉的表现是「按钮点不动」那类事故
    //（见 app_motion.dart 头注释记录的历史 bug）。判据的事实源只允许在本文件。
    const source = 'lib/shared/theme/app_theme.dart';
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = _rel(entity.path);
      if (path == source) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // 注释里提到它是允许的（多处注释正在解释「为什么要读它」）。
        if (_stripLineComment(lines[i]).contains('disableAnimations')) {
          offenders.add('$path:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'reduce-motion 判据（`MediaQuery.disableAnimations`）只许在 $source 里读一次，'
          '其它地方一律调 reducedMotionOf(context)。\n命中站点：\n${offenders.join('\n')}',
    );
  });
}

/// 错峰步长。刻意不引用调用点选的令牌值：测试要证明「错峰会生效」，
/// 而不是证明「调用点写的是 120ms」。
const int _stepMs = 200;

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 8, height: 8);
}

double _opacityOf(WidgetTester tester, String key) => tester
    .widget<Opacity>(find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(Opacity),
    ))
    .opacity;

/// 宿主：MediaQuery 必须放在 `CupertinoApp` **之内**——`pumpWidget` 的根之上
/// 没有 MediaQuery 祖先，在外面 `MediaQuery.of` 会直接抛。
Widget _host(List<Widget> children, {bool reduceMotion = false}) => CupertinoApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );

String _stripLineComment(String line) {
  final i = line.indexOf('//');
  return i < 0 ? line : line.substring(0, i);
}

String _rel(String path) {
  final norm = path.replaceAll(r'\', '/');
  final idx = norm.indexOf('lib/');
  return idx >= 0 ? norm.substring(idx) : norm;
}
