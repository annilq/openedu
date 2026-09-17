import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/presentation/resource.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../providers/home_notifier.dart';

/// 娃娃端首页：复习入口 + 今日任务列表 + 做题入口 + 打卡
/// v2 redesign：Banner 大圆角 24、Chip→AppTags、章节标题加左侧色条、
/// 空状态增加图标氛围、任务卡片 CTA 与内容间距更松。
class ChildHome extends ConsumerWidget {
  final UserModel user;
  final void Function(TaskModel task) onNavigateToPractice;
  final VoidCallback onNavigateToReview;
  final VoidCallback onNavigateToWrongQuestions;
  final VoidCallback onNavigateToTutor;

  const ChildHome({
    super.key,
    required this.user,
    required this.onNavigateToPractice,
    required this.onNavigateToReview,
    required this.onNavigateToWrongQuestions,
    required this.onNavigateToTutor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todayTasksNotifierProvider);
    final reviewState = ref.watch(dueReviewNotifierProvider);
    final dueCount =
        reviewState is DueReviewLoaded ? reviewState.items.length : 0;

    return CustomScrollView(
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            await ref.read(todayTasksNotifierProvider.notifier).load();
            await ref.read(dueReviewNotifierProvider.notifier).load();
          },
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl4),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.md),
                _ReviewBanner(
                  dueCount: dueCount,
                  onReview: onNavigateToReview,
                  onWrong: onNavigateToWrongQuestions,
                ),
                PopIn(
                  child: _TutorBanner(onTutor: onNavigateToTutor),
                ),
                const SectionTitle('今日任务',
                    padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md,
                        AppSpacing.lg, AppSpacing.md)),
                ...switch (state) {
                  ResourceIdle() || ResourceLoading() => const [
                      AppLoading.skeletonInline(skeletonLines: 2)
                    ],
                  ResourceError() => [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: AppError(
                          message: state.errorOrNull ?? '',
                          onRetry: () => ref
                              .read(todayTasksNotifierProvider.notifier)
                              .load(),
                        ),
                      ),
                    ],
                  ResourceLoaded() => (state.dataOrNull ?? const []).isEmpty
                      ? [
                          const Padding(
                            padding: EdgeInsets.only(top: AppSpacing.xl5),
                            // 空态是全站唯一的「没有内容」场景，视觉语言必须与
                            // 家长端一致（88 色块 + 标题 + 说明），否则同一个 App
                            // 里两套空态。娃娃端只多给一个 [tone]：撞色黄块提供
                            // 情绪价值，别的地方不加，一屏最多 3 个色相。
                            child: AppEmptyState(
                              icon: CupertinoIcons.sun_max,
                              tone: AppBrutal.yellow,
                              title: '今天还没有任务哦',
                              message: '等爸爸妈妈布置吧～',
                            ),
                          ),
                        ]
                      : (state.dataOrNull ?? const [])
                          // key 稳定 → PopIn 的 State 不重建，列表刷新时不会重放入场动画。
                          .map((t) => Padding(
                                key: ValueKey<String>(t.id),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg,
                                    vertical: AppSpacing.xs),
                                child: PopIn(
                                  // 左侧学科色条由 Row(stretch) 撑满卡片高度；
                                  // 卡片高度随内容，需 IntrinsicHeight 给 Row 有界高度。
                                  child: IntrinsicHeight(
                                    child: _TaskCard(
                                      task: t,
                                      onStart: () => onNavigateToPractice(t),
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                },
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 新粗野横幅：左侧撞色大块（约占横幅 28%，守住「色块 ≤ 卡片 40%」）+ 右侧纸面内容。
///
/// 撞色块不铺满整条：ADR-0044 定色块为强调件，横幅全填充会让首页两个 banner
/// 直接打架，且家长端同款组件在密集信息区不可读。
class _BrutalBanner extends StatelessWidget {
  final Color fill;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const _BrutalBanner({
    required this.fill,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Container(
      decoration: BoxDecoration(
        color: app.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.banner),
        border: Border.all(color: AppBrutal.ink, width: AppElevation.borderWidth),
        boxShadow: AppElevation.hard(),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(AppRadius.banner)),
                  // 与右半区之间的竖线：撞色块与纸底对比仅 1.38~3.4，必须描边。
                  border: Border(
                    right: BorderSide(
                        color: AppBrutal.ink, width: AppElevation.borderWidth),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 40, color: AppBrutal.ink),
              ),
            ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle,
                      style: text.bodyMedium
                          ?.copyWith(color: app.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// 方形图标按钮（次级入口）：纸底 + 墨黑描边，不与撞色 CTA 抢层级。
class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SquareIconButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: AppControl.heightOf(context),
          height: AppControl.heightOf(context),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: app.surfaceContainerLow,
            borderRadius:
                const BorderRadius.all(Radius.circular(AppRadius.button)),
            border: Border.all(
                color: AppBrutal.ink, width: AppElevation.borderWidth),
          ),
          child: Icon(icon, size: 20, color: app.onSurface),
        ),
      ),
    );
  }
}

/// 复习错题横幅（撞色 = cyan，亮块配墨黑字 7.94:1）。
class _ReviewBanner extends StatelessWidget {
  final int dueCount;
  final VoidCallback onReview;
  final VoidCallback onWrong;

  const _ReviewBanner({
    required this.dueCount,
    required this.onReview,
    required this.onWrong,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
      child: _BrutalBanner(
        fill: AppBrutal.cyan,
        icon: CupertinoIcons.refresh,
        title: '复习错题',
        subtitle: dueCount > 0 ? '今天有 $dueCount 道题要复习' : '今天没有要复习的题',
        actions: [
          _SquareIconButton(
              icon: CupertinoIcons.book, tooltip: '错题本', onTap: onWrong),
          AppBrutalButton(
            label: '去复习',
            fill: AppBrutal.cyan,
            onPressed: onReview,
            icon: CupertinoIcons.arrow_right,
          ),
        ],
      ),
    );
  }
}

/// AI 老师横幅（撞色 = yellow，亮块配墨黑字 13.25:1）。
class _TutorBanner extends StatelessWidget {
  final VoidCallback onTutor;
  const _TutorBanner({required this.onTutor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      child: _BrutalBanner(
        fill: AppBrutal.yellow,
        icon: CupertinoIcons.sparkles,
        title: '问 AI 老师',
        subtitle: '遇到不懂的题，随时来问～',
        actions: [
          AppBrutalButton(
            label: '去提问',
            fill: AppBrutal.yellow,
            onPressed: onTutor,
            icon: CupertinoIcons.arrow_right,
          ),
        ],
      ),
    );
  }
}

/// 「已完成」标记：实心柠檬绿 pill + 墨黑描边（撞色强调件，非语义淡底）。
class _DonePill extends StatelessWidget {
  const _DonePill();

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: AppBrutal.lime,
        borderRadius:
            const BorderRadius.all(Radius.circular(AppRadius.chip)),
        border: Border.all(
            color: AppBrutal.ink, width: AppElevation.borderWidthSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.check_mark,
              size: 12, color: AppBrutal.ink),
          const SizedBox(width: 4),
          Text('已完成',
              style: text.labelSmall?.copyWith(
                  color: AppBrutal.ink, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// 今日任务卡片：左侧 6px 学科色条 + 学科 chip（三重编码）+ 学科色 CTA。
///
/// 列表行**禁止整行彩色填充**（ADR-0044）：一屏多个任务卡时，整行撞色会让
/// 标题与标签全部糊掉。学科身份由色条 + chip 承担，够辨识也够克制。
class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onStart;

  const _TaskCard({required this.task, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == 'done';
    final text = AppTheme.textOf(context);
    // 学科/年级/知识点已下沉到题（ADR-0004），从首题取展示值。
    final q0 = task.questions.isNotEmpty ? task.questions.first : null;
    final subjectKey = SubjectAccent.fromName(q0?.subject);
    final subjectColor = SubjectAccent.forContext(subjectKey, context).accent;

    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: subjectColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(task.title,
                              style: text.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        if (isDone) const _DonePill(),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        // 学科 chip 自带色 + 几何标记（数学■ / 语文● / 英语▲），
                        // 不依赖颜色单独区分学科。
                        AppTags.subject(subjectKey),
                        if (q0 != null && q0.grade > 0)
                          AppTags.normal('${q0.grade}年级'),
                        if (q0 != null) AppTags.info(q0.knowledgePoint),
                        AppTags.normal('${task.questions.length}题'),
                      ],
                    ),
                    if (!isDone) ...[
                      const SizedBox(height: AppSpacing.xl),
                      // CTA 用学科色：不新增色相，前景由 AppBrutal.onColor 判定
                      //（数学蓝→白字，语文珊瑚 / 英语黄→墨黑字）。
                      AppBrutalButton(
                        label: '开始做题',
                        fill: subjectColor,
                        onPressed: onStart,
                        fullWidth: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
