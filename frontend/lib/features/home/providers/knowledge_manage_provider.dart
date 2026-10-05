import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/repositories/material_repository.dart';
import 'home_provider.dart';

/// 知识点管理状态（ADR-0055 §4 确认页）：按 (subject, grade) 取目录、勾选待审 /
/// 骨架条目、批量确认转正。
///
/// 知识点是家长私有的——范围必须锁死 (subject, grade)，检索与出题也只是同范围
/// 内召回；这里沿用同一口径，避免把别家/别年级的点混进来。
class KnowledgeManageState {
  final String subject;
  final int grade;
  /// 学期范围维度（ADR-0055 §4 补）：'' = 整学年/不限；'上学期' / '下学期'。
  /// 知识点与家长私有、锁死 (学科, 年级) 同一口径，再加学期避免把上下学期混在一起。
  final String semester;

  /// 该范围内全部知识点：涌现（emerged，含待审 pending）+ 骨架兜底（skeleton，
  /// 后端标记为 curated 但 id 为 null——确认时才落库）。
  final List<KnowledgePointOption> items;

  /// 勾选待确认的名字集合（骨架条目也可勾选，确认即落库）。
  final Set<String> selectedNames;
  final bool loading;
  final String? notice;
  final String? error;

  const KnowledgeManageState({
    this.subject = '数学',
    this.grade = 1,
    this.semester = '',
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
        items: items ?? this.items,
        selectedNames: selectedNames ?? this.selectedNames,
        loading: loading ?? this.loading,
        notice: clearNotice ? null : (notice ?? this.notice),
        error: clearError ? null : (error ?? this.error),
      );

  /// 待审条目数（pending）——确认后才参与掌握度统计。
  int get pendingCount =>
      items.where((e) => e.status == 'pending').length;
}

class KnowledgeManageNotifier extends StateNotifier<KnowledgeManageState> {
  KnowledgeManageNotifier(this._repo) : super(const KnowledgeManageState());

  final MaterialRepository _repo;

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
