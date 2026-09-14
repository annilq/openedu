import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 前端分层不变量（ADR-0037）——静态扫描，不启动 widget 树。
///
/// 与后端 `backend/tests/ai/test_layering_invariants.py` 对称：把「目录即契约」
/// 固化成 CI 断言，越界直接红，而不是靠 review 时的自觉。
///
/// 规则来源：`docs/adr/0037-frontend-feature-boundaries.md`。
///
/// - R1 `shared/` 不得 import `features/`：依赖单向 `main/ → features/* → shared/*`。
///   历史反例：`shared/widgets/app_model_selector.dart` 曾 import `features/tutor/...`。
/// - R2 除 `home/` 外，feature 不得横向 import 其他 feature。
///   `features/home/presentation/` 是展示层组合根，装配各 feature 页面（唯一豁免）。
/// - R3 `App*` 前缀类只定义在 `shared/widgets/`：该前缀 = 通用设计系统组件；
///   一旦订阅某个 feature 的 provider，就必须落回该 feature（如 `ModelSelector`）。
void main() {
  final imports = _collectImports();

  test('R1: shared/ 不得 import features/（依赖单向，禁止倒置）', () {
    final offenders = [
      for (final ref in imports)
        if (ref.from.startsWith('shared/') && ref.to.startsWith('features/'))
          '${ref.from}  ->  ${ref.to}',
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'shared/ 是跨 feature 基础层、被所有 feature 依赖，反向引用会成环。'
          '把组件归位到它所属的 feature，或改为参数注入（见 ADR-0037）。\n'
          '${offenders.join('\n')}',
    );
  });

  test('R2: 除 home 外，feature 不得横向 import 其他 feature', () {
    final offenders = [
      for (final ref in imports)
        if (_featureOf(ref.from) != null &&
            _featureOf(ref.to) != null &&
            _featureOf(ref.from) != _featureOf(ref.to) &&
            _featureOf(ref.from) != 'home')
          '${_featureOf(ref.from)} -> ${_featureOf(ref.to)}  (${ref.from})',
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'feature 之间横向依赖会引发循环依赖（后端同规则见 ADR-0027）。'
          '需要跨 feature 复用时，把能力下沉 shared/ 或经 home 装配。\n'
          '${offenders.join('\n')}',
    );
  });

  test('R3: features/ 下不得定义 App* 前缀类', () {
    final classRe = RegExp(r'^class\s+(App[A-Z]\w*)');
    final offenders = <String>[];
    for (final file in _dartFiles('lib/features')) {
      for (final line in File(file).readAsLinesSync()) {
        final m = classRe.firstMatch(line);
        if (m != null) offenders.add('$file: ${m.group(1)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '`App*` 前缀保留给 shared/widgets 的通用设计系统组件；'
          'feature 内的组件用领域名（如 ModelSelector）。\n'
          '${offenders.join('\n')}',
    );
  });
}

/// 一条包内相对 import：`from` / `to` 均为相对 `lib/` 的 POSIX 路径。
class _ImportRef {
  final String from;
  final String to;
  const _ImportRef(this.from, this.to);
}

final _importRe = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''');

List<_ImportRef> _collectImports() {
  final refs = <_ImportRef>[];
  for (final file in _dartFiles('lib')) {
    final from = file.substring('lib/'.length);
    for (final line in File(file).readAsLinesSync()) {
      final m = _importRe.firstMatch(line);
      if (m == null) continue;
      final to = _resolve(from, m.group(1)!);
      if (to != null) refs.add(_ImportRef(from, to));
    }
  }
  return refs;
}

/// 解析包内相对 import 为相对 `lib/` 的 POSIX 路径；非相对 import 返回 null。
///
/// `..` 超出 `lib/` 根时做**截断**而非丢弃：Dart 分析器就是这么干的——实测
/// `lib/shared/widgets/x.dart` 里写 `../../../features/...`（多一级）仍能解析到
/// `lib/features/...`。若本函数改为「逃出即丢弃」，一条层数写错的
/// `shared → features` 违规就会既编译通过、又被本扫描漏掉，R1 形同虚设。
String? _resolve(String fromRelToLib, String import) {
  if (!import.startsWith('.')) return null;
  final slash = fromRelToLib.lastIndexOf('/');
  final base = slash < 0 ? '' : fromRelToLib.substring(0, slash);
  final segments = <String>[];
  for (final seg in '$base/$import'.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(seg);
  }
  return segments.isEmpty ? null : segments.join('/');
}

/// 相对 lib/ 路径所在的 feature 名；不在 `features/` 下返回 null。
String? _featureOf(String libRelative) =>
    RegExp(r'^features/([^/]+)/').firstMatch(libRelative)?.group(1);

List<String> _dartFiles(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) {
    fail('找不到目录 `$root`——本测试假定工作目录为 frontend/。');
  }
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .toList()
    ..sort();
}
