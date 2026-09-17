// 桌面窗口「地板」守卫（ADR-0045）。
//
// 为什么需要它：三份原生 runner（macOS / Windows / Linux）的值**改了 git 看不见**
// —— `frontend/.gitignore` 把整个平台目录忽略了。于是「地板不得高于紧凑断点」这条
// 不变量在仓库里**没有任何载体**：它可以被静默改回 800×600，而紧凑档（底栏 /
// 汉堡抽屉）会再次从桌面端消失——没有 diff、没有测试、没有任何提醒。2026-09-17
// 之前就是那个状态，且持续了不知道多久。
//
// 所以本文件是这条不变量的载体。它断言两件事：
//
//   1. **每个平台声明的窗口最小宽度 ≤ `AppLayout.compactMax`。**
//      地板高于断点 ⇒ 该平台上紧凑档**不可达** ⇒ 一条没人看过的分支。
//   2. **三个平台的地板值一致。**
//      落下一个平台时，「在桌面上验证手机布局」这件事就只在部分平台成立，
//      而且失败方式是静默的——你只是在那台机器上拖不动窗口，不会看到任何报错。
//
// ⚠️ 解析必须**先剥掉行注释**：三份文件的注释里都留着旧值（「想恢复旧行为：改回
// `NSSize(width: 800, height: 600)`」）。不剥注释就会把那句当成代码读出来，
// 守卫会变成「永远读到旧值」——比没有守卫更坏，因为它会给出一个貌似可信的绿灯。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';

/// 一份 runner 里的地板声明。`marker` 是**代码**里唯一的前缀，
/// 取它之后的头两个整数。
class _FloorDecl {
  final String platform;
  final String path;
  final String marker;

  const _FloorDecl({
    required this.platform,
    required this.path,
    required this.marker,
  });

  /// 剥掉 `//` 之后的行注释。这三份文件里没有含 `//` 的字符串字面量
  /// （无 URL），所以朴素切分是安全的；将来若有，这里会先失效——那时改成
  /// 按语言分词，不要退回「直接搜 marker」。
  String _stripLineComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i < 0 ? line : line.substring(0, i);
      })
      .join('\n');

  /// 返回 `(width, height)`；真读不到就抛，**绝不返回空**。
  /// 解析失败 = 代码换了写法、守卫瞎了 —— 必须红，不能静默通过。
  (int, int) parse() {
    final file = File(path);
    final src = _stripLineComments(file.readAsStringSync());
    final at = src.indexOf(marker);
    if (at < 0) {
      throw StateError(
        '$platform 的地板声明找不到了。\n'
        '  期望前缀：$marker\n'
        '  文件：$path\n'
        '如果你重写了这行（换 API、拆常量、改名），请同步更新本守卫的 marker；'
        '不要让它静默跳过——它是这条不变量在 git 里的唯一载体。',
      );
    }
    // 两个数之间的分隔符**不能假定是纯空白**：macOS 写的是
    // `NSSize(width: 320, height: 568)`，逗号与第二个数之间还夹着 `height: `。
    // 用 `\D+?`（非贪婪）而不是 `\s*`，并且必须非贪婪——贪婪会一路吞到文件里
    // 最后一串数字，读出一个貌似合理的错值。
    // 必须从 marker **末尾**往后切，不能从 marker 起点切：Windows 的 marker 里
    // `Win32Window` 自带一个 `32`，从起点切会把它当成宽度读出来（实测读到 32×320）。
    final m = RegExp(r'(\d+)\D+?(\d+)')
        .firstMatch(src.substring(at + marker.length));
    if (m == null) {
      throw StateError('$platform：在 `$marker` 之后没找到「宽, 高」两个整数（$path）');
    }
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }
}

const _decls = <_FloorDecl>[
  _FloorDecl(
    platform: 'macOS',
    path: 'macos/Runner/MainFlutterWindow.swift',
    marker: 'self.minSize = NSSize(width:',
  ),
  _FloorDecl(
    platform: 'Windows',
    path: 'windows/runner/main.cpp',
    marker: 'window.SetMinimumSize(Win32Window::Size(',
  ),
  _FloorDecl(
    platform: 'Linux',
    path: 'linux/runner/my_application.cc',
    marker: 'gtk_widget_set_size_request(GTK_WIDGET(window),',
  ),
];

void main() {
  // 三份文件都不在 ⇒ 平台目录没生成（fresh clone / 纯 CI）。跳过，
  // 但要**说出来**：静默跳过会让人以为「这条守卫生效了」。
  final present = _decls.where((d) => File(d.path).existsSync()).toList();
  if (present.isEmpty) {
    test('桌面窗口地板守卫（跳过）', () {
      markTestSkipped(
        '三份原生 runner 都不存在——平台目录未生成。'
        '这条不变量在本机无法校验；先跑 `flutter create .` 生成平台目录。',
      );
    });
    return;
  }

  for (final d in present) {
    test('${d.platform} 的窗口地板不得高于紧凑断点', () {
      final (width, height) = d.parse();

      expect(
        width,
        lessThanOrEqualTo(AppLayout.compactMax),
        reason: '${d.platform} 的地板宽 $width > compactMax ${AppLayout.compactMax}，'
            '该平台上的紧凑档（底栏 / 汉堡抽屉）将不可达 —— 等于在没人看过的地方跑。\n'
            '地板的作用是挡住**会坏掉的**尺寸，不是挡住**不喜欢的**尺寸（ADR-0045）。',
      );
      expect(
        height,
        greaterThanOrEqualTo(400),
        reason: '${d.platform} 的地板高 $height 太矮，连一屏基本内容都放不下。',
      );
    });
  }

  test('三平台地板一致', () {
    // 只有一个平台存在时（改平台工作流）无从比较，跳过但要出声。
    if (present.length < 2) {
      markTestSkipped('只找到 ${present.length} 份 runner，无法比较一致性。');
      return;
    }
    final parsed = {
      for (final d in present) d.platform: d.parse(),
    };
    final widths = parsed.values.map((v) => v.$1).toSet();
    final heights = parsed.values.map((v) => v.$2).toSet();

    expect(
      widths,
      hasLength(1),
      reason: '各平台地板宽不一致：$parsed。落下的那个平台上拖不出紧凑档，'
          '而且失败是静默的（只是拖不动，不报错）。',
    );
    expect(
      heights,
      hasLength(1),
      reason: '各平台地板高不一致：$parsed。',
    );
  });
}
