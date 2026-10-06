import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/repositories/material_repository.dart';
import 'home_provider.dart';

/// 知识点管理状态（ADR-0055 §4 确认页）：先按「传过教材的范围」选择范围，
/// 再列出该范围内的知识点、勾选待审 / 批量确认转正。
///
/// 知识点是教师私有的——范围必须锁死 (subject, grade)，检索与出题也只是同范围
/// 内召回；这里沿用同一口径，避免把别家/别年级的点混进来。
///
/// **范围只取真实传过教材的那些**（ADR-0065）：下拉不再枚举 9 年级 × 3 学科，
/// 否则教师要在绝大多数空门里逐个试，还没法记清自己传过哪几个年级。
class KnowledgeManageState {
  final String subject;
  final int grade;
  /// 学期范围维度（ADR-0055 §4 补）：'' = 整学年/不限；'上学期' / '下学期'。
  /// 知识点与教师私有、锁死 (学科, 年级) 同一口径，再加学期避免把上下学期混在一起。
  final String semester;

  /// 可选范围——后端按教师名下教材聚合而来；空 = 一份教材都还没传。
  final List<KnowledgePointScope> scopes;

  /// 没识别出学科 / 年级、归不到任何范围的教材份数（要告诉教师，否则他会以为上传丢了）。
  final int unscopedCount;

  /// 该范围内的知识点（ADR-0065）：只有教材里涌现出来的那些，每条都必有 id。
  final List<KnowledgePointOption> items;

  /// 勾选待确认的名字集合。
  final Set<String> selectedNames;
  final bool loading;
  final String? notice;
  final String? error;

  const KnowledgeManageState({
    this.subject = '数学',
    this.grade = 1,
    this.semester = '',
    this.scopes = const [],
    this.unscopedCount = 0,
    this.items = const [],
    this.selectedNames = const {},
    this.loading = false,
    this.notice,
    this.error,
  });

  KnowledgeManageState copyWith({
    String? subject,
    int? grade,
    String? semester,
    List<KnowledgePointScope>? scopes,
    int? unscopedCount,
    List<KnowledgePointOption>? items,
    Set<String>? selectedNames,
    bool? loading,
    String? notice,
    bool clearNotice = false,
    String? error,
    bool clearError = false,
  }) =>
      KnowledgeManageState(
        subject: subject ?? this.subject,
        grade: grade ?? this.grade,
        semester: semester ?? this.semester,
        scopes: scopes ?? this.scopes,
        unscopedCount: unscopedCount ?? this.unscopedCount,
        items: items ?? this.items,
        selectedNames: selectedNames ?? this.selectedNames,
        loading: loading ?? this.loading,
        notice: clearNotice ? null : (notice ?? this.notice),
        error: clearError ? null : (error ?? this.error),
      );

  // ── 下拉选项：全部由 [scopes] 派生，不做全量枚举 ────────────────────

  /// 出现过的学科（去重、保持后端给的学科序）。
  List<String> get subjects {
    final out = <String>[];
    for (final s in scopes) {
      if (!out.contains(s.subject)) out.add(s.subject);
    }
    return out;
  }

  /// 某学科下出现过的年级。
  ///
  /// 按参数而不是取当前学科的 getter：下拉切换学科这一帧里，新学科的年级还没进
  /// state，级联的下一个下拉要当场算出候选。
  List<int> gradesOf(String subject) {
    final out = <int>[];
    for (final s in scopes) {
      if (s.subject == subject && !out.contains(s.grade)) out.add(s.grade);
    }
    return out..sort();
  }

  /// 当前学科下的年级。
  List<int> get grades => gradesOf(subject);

  /// 某 (学科, 年级) 下可选的学期；首个恒为「整学年」——并集两张学期表，教材跨
  /// 上下册时不必来回切。
  List<String> semestersOf(String subject, int grade) {
    final out = <String>[''];
    for (final s in scopes) {
      if (s.subject == subject &&
          s.grade == grade &&
          s.semester.isNotEmpty &&
          !out.contains(s.semester)) {
        out.add(s.semester);
      }
    }
    return out;
  }

  /// 当前 (学科, 年级) 下可选的学期。
  List<String> get semesters => semestersOf(subject, grade);

  /// 当前范围一共有几份教材。挂在标题旁，回答「为什么这里有知识点」。
  int get materialCountInScope => scopes
      .where((s) => s.subject == subject && s.grade == grade)
      .fold(0, (sum, s) => sum + s.materialCount);

  /// 待审条目数（pending）——确认后才参与掌握度统计。
  int get pendingCount =>
      items.where((e) => e.status == 'pending').length;

  /// 已勾选且**已落库**（有 id）的条目数——「删除选中」的真实可用数量。
  ///
  /// ADR-0066 起目录里不再有「骨架」那种 DB 里还不存在的条目，勾到的一定有 id；
  /// 但仍然按 id 计数：它对齐的是删除端点的语义（只认 id），哪天真混进无 id 的
  /// 条目，计数会先露馅而不是让静默少删。
  int get deletableSelectedCount =>
      items.where((e) => e.id != null && selectedNames.contains(e.name)).length;
}

class KnowledgeManageNotifier extends StateNotifier<KnowledgeManageState> {
  KnowledgeManageNotifier(this._repo) : super(const KnowledgeManageState());

  final MaterialRepository _repo;

  /// 入口：拉范围清单，并把当前范围**校正**到还存在的那一档。
  ///
  /// 校正这一步不能省：教师可能在资料库删掉了「5 年级语文」最后一份教材，此时
  /// 旧状态还停在 5 年级语文，照它去查只会得到空列表，页面看起来像「加载失败了」。
  Future<void> loadScopes() async {
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      final res = await _repo.getKnowledgePointScopes();
      final (subject, grade, semester) = _fallbackScope(res.scopes);
      state = state.copyWith(
        scopes: res.scopes,
        unscopedCount: res.unscopedCount,
        subject: subject,
        grade: grade,
        semester: semester,
        selectedNames: const {},
      );
      if (res.scopes.isEmpty) {
        // 一份教材都没有：整页走空态，不需要再打目录接口（必然为空）。
        state = state.copyWith(items: const [], loading: false);
        return;
      }
      await load();
    } catch (e) {
      state = state.copyWith(loading: false, error: '加载失败：$e');
    }
  }

  /// 当前范围失效时落到哪：仍有效就原样返回，否则取第一个可选范围。
  (String, int, String) _fallbackScope(List<KnowledgePointScope> scopes) {
    final stillValid = scopes.any(
      (s) => s.subject == state.subject && s.grade == state.grade,
    );
    if (stillValid) {
      final semesters = [
        for (final s in scopes)
          if (s.subject == state.subject && s.grade == state.grade) s.semester,
      ];
      return (
        state.subject,
        state.grade,
        semesters.contains(state.semester) ? state.semester : '',
      );
    }
    if (scopes.isEmpty) return (state.subject, state.grade, state.semester);
    final first = scopes.first;
    return (first.subject, first.grade, '');
  }

  /// 只拉当前范围的知识点目录（范围清单不变）。
  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      final dir = await _repo.getKnowledgePointDirectory(
        subject: state.subject,
        grade: state.grade,
        semester: state.semester,
      );
      state = state.copyWith(
        items: dir.items,
        loading: false,
        // 目录来源说明（ADR-0061 §L）走notice 通道，与操作反馈不混。
        notice: dir.notice.isEmpty ? null : dir.notice,
        clearNotice: dir.notice.isEmpty,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '加载失败：$e');
    }
  }

  /// 切换 (学科, 年级, 学期) 范围：重置勾选并重新拉目录。
  void setScope(String subject, int grade, String semester) {
    if (subject == state.subject &&
        grade == state.grade &&
        semester == state.semester) {
      return;
    }
    state = state.copyWith(
      subject: subject,
      grade: grade,
      semester: semester,
      selectedNames: const {},
    );
    load();
  }

  void toggle(String name) {
    final set = Set<String>.from(state.selectedNames);
    if (set.contains(name)) {
      set.remove(name);
    } else {
      set.add(name);
    }
    state = state.copyWith(selectedNames: set);
  }

  Future<void> confirmSelected() async {
    if (state.selectedNames.isEmpty) return;
    final n = state.selectedNames.length;
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      await _repo.confirmKnowledgePoints(
        subject: state.subject,
        grade: state.grade,
        semester: state.semester,
        names: state.selectedNames.toList(),
      );
      await load();
      state = state.copyWith(
        loading: false,
        selectedNames: const {},
        notice: '已确认 $n 个知识点',
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '确认失败：$e');
    }
  }

  /// 批量删除勾选的知识点（多选删除）。
  ///
  /// ADR-0066 起目录条目一律来自教材、必有 id；这里仍按 id 过滤——它对齐的是删除
  /// 端点的语义（只认 id），哪天真混进无 id 的条目时行为是可预期的。
  Future<void> deleteSelected() async {
    final ids = state.items
        .where((e) => e.id != null && state.selectedNames.contains(e.name))
        .map((e) => e.id!)
        .toList();
    if (ids.isEmpty) return;
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      final removed = await _repo.deleteKnowledgePoints(ids);
      await load();
      state = state.copyWith(
        loading: false,
        selectedNames: const {},
        notice: '已删除 $removed 个知识点',
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '删除失败：$e');
    }
  }

  void consumeNotice() => state = state.copyWith(clearNotice: true);

  /// 为知识点保存交互讲解模板（ADR-0061）：覆盖式写入 scenes，保存后刷新列表。
  Future<void> saveScenes(
    String kpId,
    List<Map<String, dynamic>> scenes,
  ) async {
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      await _repo.updateKnowledgePointScenes(kpId: kpId, scenes: scenes);
      await load();
      state = state.copyWith(loading: false, notice: '已保存交互讲解模板');
    } catch (e) {
      state = state.copyWith(loading: false, error: '保存失败：$e');
    }
  }
}

final knowledgeManageProvider =
    StateNotifierProvider<KnowledgeManageNotifier, KnowledgeManageState>(
  (ref) => KnowledgeManageNotifier(ref.watch(materialRepositoryProvider)),
);
