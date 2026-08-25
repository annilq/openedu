import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../children/domain/providers/children_provider.dart';
import '../../../children/presentation/providers/children_notifier.dart';
import '../../../children/presentation/screens/add_child_screen.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../../../tutor/presentation/providers/tutor_notifier.dart';
import '../../../tutor/presentation/screens/tutor_quota_screen.dart';
import '../providers/home_notifier.dart';

/// 家长端首页：娃娃列表 + 生成任务表单 + 进度看板
/// v2 redesign：章节用 SectionTitle、统计卡片窄屏自动换行、
/// 掌握度颜色改用主题派生色（替换 Colors.*）、Chip 改用 AppTags 语义化。
class ParentDashboard extends ConsumerStatefulWidget {
  final UserModel user;
  final void Function(TaskModel task) onNavigateToPractice;

  const ParentDashboard({
    super.key,
    required this.user,
    required this.onNavigateToPractice,
  });

  @override
  ConsumerState<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends ConsumerState<ParentDashboard> {
  final _subjectCtrl = TextEditingController(text: '数学');
  final _kpCtrl = TextEditingController(text: '两位数加减法');
  final _countCtrl = TextEditingController(text: '5');
  String _selectedQtype = 'calc';
  String _selectedChildId = '';
  int _selectedGrade = 2;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _kpCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  void _generate() {
    final childrenState = ref.read(childrenNotifierProvider);
    if (childrenState is! ChildrenLoaded || childrenState.children.isEmpty) {
      AppToast.show(context, '请先创建娃娃账号');
      return;
    }
    if (_selectedChildId.isEmpty) {
      _selectedChildId = childrenState.children.first.id;
    }
    ref.read(taskGenNotifierProvider.notifier).generate(
          childId: _selectedChildId,
          subject: _subjectCtrl.text,
          grade: _selectedGrade,
          knowledgePoint: _kpCtrl.text,
          qtype: _selectedQtype,
          count: int.tryParse(_countCtrl.text) ?? 5,
        );
  }

  void _selectChild(String id, int grade) {
    // 重复点击已选中的娃娃时不重复拉取（避免无意义的并发加载闪动）
    if (id == _selectedChildId) return;
    setState(() {
      _selectedChildId = id;
      _selectedGrade = grade;
    });
    ref.read(progressNotifierProvider.notifier).load(id);
    ref.read(masteryNotifierProvider.notifier).load(id);
    ref.read(parentWrongQuestionsProvider.notifier).load(childId: id);
    ref.read(tutorLogsNotifierProvider.notifier).load(childId: id);
    ref.read(tutorQuotaNotifierProvider(id).notifier).load(childId: id);
    ref.read(tutorUsageNotifierProvider(id).notifier).load(childId: id);
  }

  /// 打开「添加娃娃」页；成功后 createChild 已自动刷新列表，
  /// 携带新用户 id 定向选中，方便立即布置任务。
  Future<void> _openAddChild() async {
    final newId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AddChildScreen()),
    );
    if (newId == null || !mounted) return;
    final childrenState = ref.read(childrenNotifierProvider);
    if (childrenState is ChildrenLoaded) {
      for (final c in childrenState.children) {
        if (c.id == newId) {
          _selectChild(c.id, c.grade ?? 2);
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final childrenState = ref.watch(childrenNotifierProvider);
    final genState = ref.watch(taskGenNotifierProvider);

    // 监听生成结果
    ref.listen<TaskGenState>(taskGenNotifierProvider, (prev, next) {
      if (next is TaskGenSuccess) {
        AppToast.show(context, '已生成 ${next.task.count} 道题，可见答案用于核查');
        ref.read(taskGenNotifierProvider.notifier).reset();
        if (_selectedChildId.isNotEmpty) {
          ref.read(progressNotifierProvider.notifier).load(_selectedChildId);
          ref.read(masteryNotifierProvider.notifier).load(_selectedChildId);
          ref.read(parentWrongQuestionsProvider.notifier)
              .load(childId: _selectedChildId);
        }
      }
      if (next is TaskGenError) {
        AppToast.error(context, next.message);
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl4),
      child: Center(
        // 大屏平板最大宽度 1080 居中，避免超宽屏拉伸
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // —— 娃娃列表 ——
              SectionTitle('我的娃娃'),
              _buildChildrenSection(childrenState),

              const SizedBox(height: AppSpacing.xl3),

              // —— 生成任务表单 ——
              SectionTitle('布置练习任务'),
              _buildGenForm(childrenState),

              if (genState is TaskGenLoading)
                const Padding(padding: EdgeInsets.all(AppSpacing.xl2), child: AppLoading()),

              const SizedBox(height: AppSpacing.xl3),

              // —— 进度看板 ——
              if (_selectedChildId.isNotEmpty) _buildProgressSection(),

              const SizedBox(height: AppSpacing.xl3),

              // —— 掌握度看板 ——
              if (_selectedChildId.isNotEmpty) _buildMasterySection(),

              const SizedBox(height: AppSpacing.xl3),

              // —— 错题本 ——
              if (_selectedChildId.isNotEmpty) _buildParentWrongSection(),

              const SizedBox(height: AppSpacing.xl3),

              // —— AI 答疑日志（家长可查，F-305）——
              if (_selectedChildId.isNotEmpty) _buildTutorLogsSection(),

              const SizedBox(height: AppSpacing.xl3),

              // —— AI 使用管控（T10，故事 23/26）——
              if (_selectedChildId.isNotEmpty) _buildTutorQuotaSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChildrenSection(ChildrenState state) {
    final scheme = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: switch (state) {
        ChildrenInitial() || ChildrenLoading() =>
          const AppLoading(message: '加载娃娃...'),
        ChildrenError() => AppError(
            message: state.message,
            onRetry: () => ref.read(childrenNotifierProvider.notifier).loadChildren(),
          ),
        ChildrenLoaded() => state.children.isEmpty
            ? AppCard(
                padding: const EdgeInsets.all(AppSpacing.xl3),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Icon(LucideIcons.userRound,
                          size: 28, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('还没有娃娃账号',
                              style: AppTheme.textOf(context).titleSmall),
                          const SizedBox(height: AppSpacing.xs),
                          Text('先创建一个娃娃账号吧～',
                              style: AppTheme.textOf(context).bodyMedium),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ShadButton(
                      onPressed: _openAddChild,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.plus, size: 18),
                          SizedBox(width: AppSpacing.xs),
                          Text('添加娃娃'),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  ...state.children.map((c) {
                    final isSelected = _selectedChildId == c.id;
                    return _ChildSelector(
                      name: c.displayName,
                      grade: c.grade ?? 0,
                      selected: isSelected,
                      onTap: () => _selectChild(c.id, c.grade ?? 2),
                    );
                  }),
                  _AddChildTile(onTap: _openAddChild),
                ],
              ),
      },
    );
  }

  Widget _buildGenForm(ChildrenState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppPickerField<String>(
              label: '题型',
              values: const ['calc', 'fill', 'choice', 'open'],
              labels: const ['计算题', '填空题', '选择题', '应用题'],
              value: _selectedQtype,
              onChanged: (v) => setState(() => _selectedQtype = v),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: '学科', controller: _subjectCtrl),
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: '知识点', controller: _kpCtrl),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: '题数',
                    controller: _countCtrl,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: AppPickerField<int>(
                    label: '年级',
                    values: List.generate(9, (i) => i + 1),
                    labels: List.generate(9, (i) => '${i + 1}年级'),
                    value: _selectedGrade,
                    onChanged: (v) => setState(() => _selectedGrade = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(label: '生成任务', onPressed: _generate),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    final progState = ref.watch(progressNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('学习进度'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: switch (progState) {
            ProgressInitial() || ProgressLoading() =>
              const AppLoading.skeletonInline(skeletonLines: 2),
            ProgressError() => AppError(message: progState.message),
            ProgressLoaded() => AppCard(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 窄屏 2 列，宽屏 4 列——响应式不拥挤
                    final wide = constraints.maxWidth >= 560;
                    return Wrap(
                      runSpacing: AppSpacing.xl2,
                      spacing: AppSpacing.md,
                      children: [
                        _StatCard(
                          label: '总题数',
                          value: '${progState.progress.total}',
                          wide: wide,
                          icon: LucideIcons.listOrdered,
                        ),
                        _StatCard(
                          label: '答对',
                          value: '${progState.progress.correct}',
                          wide: wide,
                          icon: LucideIcons.checkCircle2,
                        ),
                        _StatCard(
                          label: '正确率',
                          value: '${(progState.progress.accuracy * 100).round()}%',
                          wide: wide,
                          icon: LucideIcons.barChart3,
                          tone: _Tone.positive,
                        ),
                        _StatCard(
                          label: '连续打卡',
                          value: '${progState.progress.streakDays}天',
                          wide: wide,
                          icon: LucideIcons.flame,
                          tone: _Tone.warm,
                        ),
                      ],
                    );
                  },
                ),
              ),
          },
        ),
      ],
    );
  }

  // —— 掌握度看板 ——
  Widget _buildMasterySection() {
    final scheme = AppTheme.colorsOf(context);
    final state = ref.watch(masteryNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('知识点掌握度'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: switch (state) {
            MasteryInitial() || MasteryLoading() =>
              const AppLoading.skeletonInline(skeletonLines: 3),
            MasteryError() => AppError(message: state.message),
            MasteryLoaded() => state.mastery.items.isEmpty
                ? AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl3),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: scheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: Icon(LucideIcons.lightbulb,
                              size: 28, color: scheme.onTertiaryContainer),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('还没有作答记录',
                                  style:
                                      AppTheme.textOf(context).titleSmall),
                              const SizedBox(height: AppSpacing.xs),
                              Text('先布置任务吧～',
                                  style:
                                      AppTheme.textOf(context).bodyMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style:
                                      AppTheme.textOf(context).bodyLarge,
                                  children: [
                                    const TextSpan(text: '已掌握 '),
                                    TextSpan(
                                      text:
                                          '${state.mastery.masteredCount}',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          ' / ${state.mastery.totalKnowledgePoints} 个知识点',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        ...state.mastery.items
                            .map((m) => Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.md),
                                  child: _MasteryBar(item: m),
                                )),
                      ],
                    ),
                  ),
          },
        ),
      ],
    );
  }

  // —— 家长错题本 ——
  Widget _buildParentWrongSection() {
    final state = ref.watch(parentWrongQuestionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('错题本'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: switch (state) {
            WrongQuestionsInitial() || WrongQuestionsLoading() =>
              const AppLoading(message: '加载错题...'),
            WrongQuestionsError() => AppError(message: state.message),
            WrongQuestionsLoaded() => state.items.isEmpty
                ? AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl3),
                    child: Center(
                      child: Text('暂无错题，继续保持～',
                          style: AppTheme.textOf(context).bodyLarge),
                    ),
                  )
                : AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: state.items
                          .map((item) => _ParentWrongCard(item: item))
                          .toList(),
                    ),
                  ),
          },
        ),
      ],
    );
  }

  // —— AI 答疑日志（家长可查，F-305）——
  Widget _buildTutorLogsSection() {
    final state = ref.watch(tutorLogsNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('AI 答疑记录'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: switch (state) {
            TutorLogsInitial() || TutorLogsLoading() =>
              const AppLoading(message: '加载答疑记录...'),
            TutorLogsError() => AppError(message: state.message),
            TutorLogsLoaded() => state.logs.isEmpty
                ? AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl3),
                    child: Center(
                      child: Text('这个娃娃还没有问过 AI 老师',
                          style: AppTheme.textOf(context).bodyLarge),
                    ),
                  )
                : AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: state.logs
                          .map((log) => _TutorLogCard(log: log))
                          .toList(),
                    ),
                  ),
          },
        ),
      ],
    );
  }

  // —— AI 使用管控（T10，故事 23/26）——
  Widget _buildTutorQuotaSection() {
    final scheme = AppTheme.colorsOf(context);
    final quotaState = ref.watch(tutorQuotaNotifierProvider(_selectedChildId));
    final usageState = ref.watch(tutorUsageNotifierProvider(_selectedChildId));

    final childrenState = ref.read(childrenNotifierProvider);
    String childName = '';
    if (childrenState is ChildrenLoaded) {
      for (final c in childrenState.children) {
        if (c.id == _selectedChildId) childName = c.displayName;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('AI 使用管控',
            trailing: ShadButton.ghost(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TutorQuotaScreen(
                    childId: _selectedChildId,
                    childName: childName,
                  ),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.slidersHorizontal, size: 20),
                  SizedBox(width: AppSpacing.xs),
                  Text('设置'),
                ],
              ),
            )),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(LucideIcons.timer,
                          size: 24, color: scheme.onSecondaryContainer),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            switch (quotaState) {
                              TutorQuotaLoaded() =>
                                _quotaSummary(quotaState.quota),
                              TutorQuotaError() =>
                                '加载失败：${quotaState.message}',
                              _ => '加载中…',
                            },
                            style: AppTheme.textOf(context).bodyMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs2),
                          Text(
                            switch (usageState) {
                              TutorUsageLoaded() =>
                                _usageSummary(usageState.usage),
                              TutorUsageError() => '用量加载失败',
                              _ => '今日用量加载中…',
                            },
                            style: AppTheme.textOf(context).bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _quotaSummary(TutorQuotaModel quota) {
    final parts = <String>[];
    parts.add(quota.dailyAskLimit != null
        ? '每日提问上限 ${quota.dailyAskLimit} 次'
        : '每日提问按全局默认上限');
    parts.add(quota.dailyMinutesLimit != null
        ? '时长上限 ${quota.dailyMinutesLimit} 分钟'
        : '时长不限');
    parts.add(quota.allowedSubjects != null && quota.allowedSubjects!.isNotEmpty
        ? '仅允许 ${quota.allowedSubjects!.join('、')}'
        : '学科不限');
    return parts.join(' · ');
  }

  String _usageSummary(TutorUsageModel usage) {
    final minutes = (usage.usedSeconds / 60).toStringAsFixed(1);
    final asks = usage.askLimit != null
        ? '${usage.asksToday}/${usage.askLimit} 次'
        : '${usage.asksToday} 次';
    final time = usage.minutesLimit != null
        ? '$minutes/${usage.minutesLimit} 分钟'
        : '$minutes 分钟';
    return '今日已用：提问 $asks · 时长 $time';
  }
}

// =====================================================================
// 私有组件
// =====================================================================

/// 娃娃选择器：替代 ChoiceChip 单 Pills 样式——有头像感、选中态突出 2px 主色描边。
class _ChildSelector extends StatelessWidget {
  final String name;
  final int grade;
  final bool selected;
  final VoidCallback onTap;
  const _ChildSelector({
    required this.name,
    required this.grade,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: selected
              ? Border.all(color: scheme.primary, width: 2)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarSquircle(
              name: name,
              size: 40,
              bg: selected ? scheme.primary : scheme.surfaceSunken,
              fg: selected
                  ? scheme.onPrimary
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: AppTheme.textOf(context).labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        )),
                const SizedBox(height: 2),
                Text(grade > 0 ? '$grade年级' : '未设置',
                    style: AppTheme.textOf(context).labelSmall?.copyWith(
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 「＋ 添加娃娃」入口块，样式与 _ChildSelector 对齐（虚线语义的加号卡片）。
class _AddChildTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddChildTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          color: scheme.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.plusCircle,
                size: 22, color: scheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Text('添加娃娃', style: AppTheme.textOf(context).bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// 家长端统计卡片：宽屏 4 列 / 窄屏 2 列自适应。
enum _Tone { neutral, positive, warm, alert }

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool wide;
  final IconData icon;
  final _Tone tone;
  const _StatCard({
    required this.label,
    required this.value,
    required this.wide,
    required this.icon,
    this.tone = _Tone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final (bg, fg) = switch (tone) {
      _Tone.positive => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer
        ),
      _Tone.warm => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _Tone.alert => (scheme.errorContainer, scheme.onErrorContainer),
      _Tone.neutral => (
          scheme.surfaceSunken,
          scheme.onSurface
        ),
    };
    return Container(
      width: wide ? null : 160, // 窄屏固定 2 列对齐
      constraints: wide
          ? BoxConstraints(
              minWidth: 140,
              maxWidth: (MediaQuery.of(context).size.width -
                      AppSpacing.xl2 * 2 -
                      AppSpacing.lg * 2 -
                      AppSpacing.md * 3) /
                  4,
            )
          : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: scheme.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(value,
              style: AppTheme.textOf(context).headlineMedium?.copyWith(
                    color: scheme.onSurface,
                    fontFamily: 'HarmonyOS_Sans_SC',
                    // tabular figures 防统计数字抖动
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: AppTheme.textOf(context).bodySmall),
        ],
      ),
    );
  }
}

/// 掌握度进度条：用主题派生色替换硬编码 Colors.*。
class _MasteryBar extends StatelessWidget {
  final KnowledgeMasteryModel item;
  const _MasteryBar({required this.item});

  /// 映射到植物绿/暖橙/珊瑚的语义色，取色走传入的 [scheme]，保证亮/暗模式一致。
  (_MasteryLevel, Color, Color) _mappingOf(AppColors scheme) {
    switch (item.level) {
      case '已掌握':
        return (
          _MasteryLevel.mastered,
          scheme.primary,
          scheme.tertiaryContainer,
        );
      case '较扎实':
        return (
          _MasteryLevel.solid,
          scheme.tertiary,
          scheme.primaryContainer,
        );
      case '巩固中':
        return (
          _MasteryLevel.learning,
          scheme.primary,
          scheme.surfaceSunken,
        );
      case '薄弱':
        return (
          _MasteryLevel.weak,
          scheme.secondary,
          scheme.secondaryContainer,
        );
      case '待加强':
        return (
          _MasteryLevel.needWork,
          scheme.error, // Gentle Coral
          scheme.errorContainer,
        );
      default:
        return (
          _MasteryLevel.unknown,
          scheme.onSurfaceVariant,
          scheme.surfaceSunken,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final (_, fgColor, _) = _mappingOf(scheme);
    final bgColor = scheme.surfaceSunken;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${item.subject} · ${item.knowledgePoint}',
                  style: AppTheme.textOf(context).bodyMedium),
            ),
            const SizedBox(width: AppSpacing.md),
            Text('${item.score.round()}分',
                style: AppTheme.textOf(context).bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
            const SizedBox(width: AppSpacing.md),
            AppBadge.infoChip(item.level),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppProgressBar(
          value: (item.score / 100).clamp(0.0, 1.0),
          height: 10,
          color: fgColor,
          trackColor: bgColor,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          item.activeWrong > 0
              ? '正确率 ${(item.accuracy * 100).round()}% · 有 ${item.activeWrong} 题待复习'
              : '正确率 ${(item.accuracy * 100).round()}% · 无待复习错题',
          style: AppTheme.textOf(context).bodySmall,
        ),
      ],
    );
  }
}

enum _MasteryLevel { mastered, solid, learning, weak, needWork, unknown }

/// 家长端错题条目：标准答案用 tertiary（植物绿变体格）替代 Colors.green。
class _ParentWrongCard extends StatelessWidget {
  final WrongQuestionModel item;
  const _ParentWrongCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.stem, style: AppTheme.textOf(context).bodyLarge),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppTags.normal(item.knowledgePoint),
              AppTags.warning('错过 ${item.wrongCount} 次'),
              AppTags.info('复习阶段 ${item.reviewStage}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.checkCircle2,
                    size: 20, color: scheme.onTertiaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '标准答案：${item.answer ?? '—'}',
                    style: AppTheme.textOf(context).bodyMedium?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (item.explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text('解析：${item.explanation}',
                  style: AppTheme.textOf(context).bodyMedium),
            ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            height: 1,
            color: scheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}

/// AI 答疑日志条目：拦截/正常 Badge 改为 AppBadge，移除硬编码橙/绿。
class _TutorLogCard extends StatelessWidget {
  final TutorLogModel log;
  const _TutorLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: AppSpacing.sm, top: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.circleHelp,
                    size: 18, color: scheme.onPrimaryContainer),
              ),
              Expanded(
                child: Text('问：${log.question}',
                    style: AppTheme.textOf(context).bodyMedium),
              ),
              const SizedBox(width: AppSpacing.md),
              log.blocked
                  ? AppBadge.warningChip('已拦截')
                  : AppBadge.successChip('正常'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: AppSpacing.sm, top: 2),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.sparkles,
                    size: 18, color: scheme.onSecondaryContainer),
              ),
              Expanded(
                child: Text('答：${log.answer}',
                    style: AppTheme.textOf(context).bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        )),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            height: 1,
            color: scheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}
