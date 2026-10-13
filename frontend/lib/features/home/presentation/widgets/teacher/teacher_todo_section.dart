import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/domain/models/task.dart';
import '../../../../../shared/presentation/resource.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../providers/teacher_todo_provider.dart';
import 'teacher_todo_cards.dart';

/// 待办卡片区：四态渲染（统一走 [Resource]）。
///
/// 进入即加载（概览页 build 里 `loadWhenIdle`），所以 Idle/Loading 几乎不闪现——
/// 只用一行骨架占位。Loaded 时铺三卡；Error 给重试，避免「待办」整块失踪让用户以为
/// 没有待办。单独成文件：它是概览页的一个独立区块（ADR-0058 P4，区块即一个文件）。
class TeacherTodoSection extends StatelessWidget {
  final Resource<TeacherTodoSummary> state;
  final void Function(int tab) onOpenList;
  final WidgetRef ref;
  const TeacherTodoSection({
    super.key,
    required this.state,
    required this.onOpenList,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    if (state.errorOrNull != null) {
      return AppError(
        message: state.errorOrNull!,
        onRetry: () => ref.read(teacherTodoProvider.notifier).load(),
      );
    }
    final loaded = state.dataOrNull;
    if (loaded == null) {
      // Idle（未加载）/ Loading 都还没有数据：骨架占位。
      return const AppLoading.skeletonInline(skeletonLines: 1);
    }
    return TeacherTodoCards(
      summary: loaded,
      onOpenList: onOpenList,
    );
  }
}
