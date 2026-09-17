import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 键盘可达性静态守卫（ADR-0046）。
///
/// 「任何可点区域都必须进焦点树」——裸 `GestureDetector` 不进焦点树：桌面端
/// Tab 跳不过去、Enter 点不动，**而 `flutter analyze` 照不出来**（它不是类型错误，
/// 是运行时语义缺失）。所以这条规则只能静态扫。
///
/// 范围限定 `lib/features/`。`shared/` 下有两处**合法**的 `GestureDetector`，
/// 它们正是焦点树的实现本身，业务层不得自建第三处：
///   * `shared/theme/app_theme.dart::_AppFocusableActionState` —— 唯一入口，
///     在其上封出 `AppIconAction` / `AppTextAction` / `AppPrimaryButton` 等；
///   * `shared/widgets/app_motion.dart::_PressScaleState` —— 按压微交互，且它在
///     reduce-motion 分支里**保留手势**（见该文件头注释记录的历史 bug：
///     曾经直接 `return child`，把 `GestureDetector` 一起丢掉，按钮点不动）。
///
/// 为什么整层禁止而不留例外：一旦存在「这里可以破例」的判断空间，
/// 下一个人就会照抄那处破例——本仓的 7 处违规正是这样长出来的。
void main() {
  test('lib/features 下不得出现可执行的 GestureDetector（ADR-0046）', () {
    final featuresDir = Directory('lib/features');
    expect(featuresDir.existsSync(), isTrue,
        reason: '请在 frontend/ 目录下运行（flutter test 的 CWD 应为 frontend/）');

    final offenders = <String>[];
    for (final entity in featuresDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // 注释里提到它是**允许**的：本仓多处注释在解释「为什么不用它」。
        if (!_stripLineComment(lines[i]).contains('GestureDetector')) continue;
        offenders.add('${_rel(entity.path)}:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '裸 GestureDetector 不在焦点树里：Tab 跳不过去、Enter 点不动。'
          '改用 `shared/` 里的既有入口——\n'
          '  可点区域      → AppFocusableAction(hoverHighlight: true)\n'
          '  图标按钮      → AppIconAction\n'
          '  文字行内操作  → AppTextAction\n'
          '  按压微交互    → PressScale\n'
          '命中站点：\n${offenders.join('\n')}',
    );
  });
}

/// 去掉行尾 `//` 注释，避免「注释里提到 GestureDetector」被误判为违规。
String _stripLineComment(String line) {
  final i = line.indexOf('//');
  return i < 0 ? line : line.substring(0, i);
}

String _rel(String path) {
  final norm = path.replaceAll(r'\', '/');
  final idx = norm.indexOf('lib/');
  return idx >= 0 ? norm.substring(idx + 4) : norm;
}
