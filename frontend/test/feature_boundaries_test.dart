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
/// - R4 `presentation/` 不得 import 任何 `*/data/`：ViewModel 只认 Repository 接口，
///   直连 `NetworkService` / DataSource 会让缓存、重试、失效语义无处落。
/// - R5 `domain/` 不得 import 任何 `*/presentation/`：依赖必须朝内，domain 是最内层，
///   反向引用意味着「装配代码放错了层」。
///
/// R1/R2/R3 是二值断言（历史已清零，见 `docs/frontend-architecture-review.md`）。
/// R4/R5 用**棘轮**（ratchet）：存量违规记在 `_knownR4` / `_knownR5` 名单里，
/// 名单**只许变短不许变长**——
///   * 名单外出现新违规 → 红（防止新增）；
///   * 名单内某条已修好却忘了删 → 也红（防止名单永久化，逼着逐条收口）。
/// 两条都清零后，把名单与棘轮逻辑一并删掉，退化为普通二值断言。
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

  test('R4: presentation/ 不得 import */data/（棘轮：名单只许变短）', () {
    final actual = <String>{
      for (final ref in imports)
        if (_inLayer(ref.from, 'presentation') && _inLayer(ref.to, 'data'))
          '${ref.from} -> ${ref.to}',
    };
    _expectRatchet(
      actual: actual,
      known: _knownR4,
      rule: 'R4',
      why: 'ViewModel 只应依赖 Repository 接口。直连 NetworkService / DataSource '
          '会让缓存、重试、失效语义无处落，端点字符串也会泄漏到 UI 层。'
          '补 repository 后请从 _knownR4 删掉对应条目。',
    );
  });

  test('R5: domain/ 不得 import */presentation/（棘轮：名单只许变短）', () {
    final actual = <String>{
      for (final ref in imports)
        if (_inLayer(ref.from, 'domain') && _inLayer(ref.to, 'presentation'))
          '${ref.from} -> ${ref.to}',
    };
    _expectRatchet(
      actual: actual,
      known: _knownR5,
      rule: 'R5',
      why: 'domain 是最内层，依赖必须朝内。出现 domain -> presentation 意味着 '
          'DI 装配代码放错了层，应挪到 presentation/providers/。'
          '挪走后请从 _knownR5 删掉对应条目。',
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

/// R4 存量违规名单。**只许删不许加**：每修好一条，就从这里删一条。
/// R4 存量违规名单。**只许删不许加**。已清零（2026-09-15）：
/// 全部 feature 都补上了 repository 接口，presentation 不再直连 `data/`。
const _knownR4 = <String>{};
/// R5 存量违规名单。**只许删不许加**。已清零（2026-09-15）：
/// 两个 DI 装配文件从 `domain/providers/` 挪到了 feature 级的 `providers/`（组合根）。
const _knownR5 = <String>{};

/// 棘轮断言：两头都红。
///
/// - [actual] 里出现 [known] 之外的条目 → 红：**不许新增违规**。
/// - [known] 里出现 [actual] 之外的条目 → 红：**名单里的已修好了，请删条目**，
///   防止「先记进名单再说」变成永久豁免。
void _expectRatchet({
  required Set<String> actual,
  required Set<String> known,
  required String rule,
  required String why,
}) {
  final added = (actual.difference(known).toList()..sort()).join('\n');
  final stale = (known.difference(actual).toList()..sort()).join('\n');
  expect(
    added,
    isEmpty,
    reason: '$rule 出现名单外的新违规：\n$added\n\n$why',
  );
  expect(
    stale,
    isEmpty,
    reason: '$rule 名单内以下条目已不再违规——请从 _known$rule 中删除，'
        '别让豁免名单长期挂着：\n$stale',
  );
}

/// 相对 `lib/` 的路径是否位于 [layer] 层（路径中存在同名目录段）。
bool _inLayer(String libRelative, String layer) =>
    libRelative.split('/').contains(layer);

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
