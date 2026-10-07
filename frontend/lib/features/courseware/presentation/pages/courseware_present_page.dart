import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_pushed_page.dart';
import '../../domain/models/courseware.dart';
import '../../domain/models/courseware_section.dart';
import '../../domain/models/courseware_section_kind.dart';
import '../../providers/courseware_provider.dart';
import '../widgets/courseware_present_step_bar.dart';
import '../widgets/courseware_script_view.dart';
import '../widgets/section_interactive_scene.dart';
import '../widgets/section_media_gallery.dart';
import '../../../assistant/domain/assistant_courseware_context.dart';
import '../../../assistant/presentation/screens/assistant_chat_page.dart';
import '../../../assistant/presentation/widgets/floating_assistant.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

/// 讲课演示页（ADR-0067 §6 切片 4b）。
///
/// 教室里的形态：**push 出去的全屏页，不带侧栏 / 底栏**（§3.8）——备课要编辑入口，
/// 讲课要零干扰，两者诉求相反，靠 push 出去这一层隔开。
///
/// 自上而下四区（§3.8）：
/// - **头部**：课件标题 + `学科 · 年级 · 学期` + 右侧「退出演示」；
/// - **步骤条**：环节横排，当前项实心高亮，可点直接跳；
/// - **主区**：环节标题 + 话术提问卡 + 按 kind 分派的环节内容（唯一可变区）；
/// - **底部**：上一步 / `2 / 4` / 下一步。
///
/// ⚠️ 布局只按**可用宽度**取档（[LayoutBuilder]），不写死分辨率：投影常见
/// 1920×1080 / 1366×768 与平板 1024×768 走的是同一套判定，只是落在不同的档上
/// （§3.7 要求首轮补大尺寸验证，别让课件成为第一个在投影下溢出的页面）。
class CoursewarePresentPage extends ConsumerStatefulWidget {
  const CoursewarePresentPage({
    super.key,
    required this.coursewareId,
  });

  /// 课件 id。数据一律走 [coursewareDetailProvider]（R4：presentation 不碰 `data/`）。
  final String coursewareId;

  @override
  ConsumerState<CoursewarePresentPage> createState() =>
      _CoursewarePresentPageState();
}

class _CoursewarePresentPageState
    extends ConsumerState<CoursewarePresentPage> {
  /// 当前环节下标。切换是**页内状态**而不是 push 新路由（§3.8 纪律 3）：
  /// push 会丢掉「现在讲到第几环节」，返回时还要重新找。
  int _index = 0;

  // T06：键盘 / 翻页笔翻页。独立 focusNode，挂载后抢焦点，与 AppPushedPage 的
  // Esc Shortcuts 并存（Esc 由祖先 Shortcuts 拦截，方向键 / 空格落到本节点）。
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 首帧后抢焦点：AppPushedPage 自带 autofocus 焦点节点，须主动覆盖才能收到方向键。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// 右键 = 下一步；左键 = 上一步。与底部按钮完全等价，供翻页笔 / 键盘遥控。
  KeyEventResult _onKeyEvent(KeyEvent event, int index, int total) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if ({
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.space,
    }.contains(event.logicalKey)) {
      if (index < total - 1) setState(() => _index = index + 1);
      return KeyEventResult.handled;
    }
    if ({
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowUp,
    }.contains(event.logicalKey)) {
      if (index > 0) setState(() => _index = index - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// T06：字号随可用宽度升档（守 1080 居中列，不破坏切片 8「不溢出」结论）。
  static double fontScaleFor(double width) {
    if (width >= 1600) return 1.2;
    if (width >= 1280) return 1.1;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final async = ref.watch(coursewareDetailProvider(widget.coursewareId));
    return switch (async) {
      AsyncData(:final value) => value == null
          ? AppPushedPage(
              background: app.surface,
              child: const Center(
                child: AppEmptyState(
                  icon: LucideIcons.fileWarning,
                  title: '这份课件已经不存在了',
                  message: '它可能已被删除。回到知识点列表重新打开一份课件。',
                ),
              ),
            )
          : _buildPresent(app, value),
      AsyncError(:final error) => AppPushedPage(
          background: app.surface,
          child: Center(
            child: AppError(
              message: '课件加载失败：$error',
              onRetry: () => ref.invalidate(
                coursewareDetailProvider(widget.coursewareId),
              ),
            ),
          ),
        ),
      _ => AppPushedPage(
          background: app.surface,
          child: const Center(child: AppLoading()),
        ),
    };
  }

  Widget _buildPresent(AppColors app, CoursewareModel courseware) {
    if (courseware.isEmpty) {
      return AppPushedPage(
        background: app.surface,
        child: const Center(
          child: AppEmptyState(
            icon: LucideIcons.layoutGrid,
            title: '这份课件还没有环节',
            message: '课件是一串讲解环节，现在一个都没有。'
                '回到课件编辑页用 AI 起草，或手动加第一个环节。',
            steps: [
              '在课件编辑页点「AI 起草」生成环节草稿',
              '调顺序、改标题、换素材',
              '回到演示页逐环节投给学生',
            ],
          ),
        ),
      );
    }
    // 环节数可能因外部改动而变短，切页前先把下标夹回合法区间。
    final index = _index.clamp(0, courseware.sections.length - 1);
    return AppPushedPage(
      background: app.surface,
      child: SafeArea(
        // T06：键盘 / 翻页笔翻页（与底部按钮翻页等价并存）。
        child: KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: (e) => _onKeyEvent(e, index, courseware.sections.length),
          // T06：字号随可用宽度升档，守 AppContentFrame 的 1080 居中列。
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                fontScaleFor(MediaQuery.sizeOf(context).width),
              ),
            ),
            child: Column(
              children: [
                _buildHeader(context, courseware),
                CoursewarePresentStepBar(
                  sections: courseware.sections,
                  index: index,
                  onSelect: (i) => setState(() => _index = i),
                ),
                // T06：环节切换轻过渡；reduced-motion 下退化为瞬时（不破坏可读性）。
                //
                // 主区叠一个浮动的「问 AI 老师」入口（ADR-0072 L2）：讲课现场随时就
                // 当前知识点提问 / 求讲解。浮球落在主区内、footer 之上——不压住底部
                // 上一步 / 下一步，也不压住顶栏。复用同一 [AssistantLauncher] 与
                // [AssistantChatPage]，只是额外带上 [AssistantCoursewareContext] 聚焦。
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: reducedMotionOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: _PresentStage(
                            key: ValueKey(index),
                            section: courseware.sections[index],
                          ),
                        ),
                      ),
                      Positioned(
                        right: AppSpacing.lg,
                        bottom: AppSpacing.lg,
                        child: AssistantLauncher(
                          onTap: () => _openAssistant(context, courseware),
                        ),
                      ),
                    ],
                  ),
                ),
                _PresentFooter(
                  index: index,
                  total: courseware.sections.length,
                  onPrev: index > 0
                      ? () => setState(() => _index = index - 1)
                      : null,
                  onNext: index < courseware.sections.length - 1
                      ? () => setState(() => _index = index + 1)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, CoursewareModel courseware) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final meta = [
      if (courseware.subject != null && courseware.subject!.isNotEmpty)
        courseware.subject!,
      if (courseware.grade != null) '${courseware.grade}年级',
      if (courseware.semester != null && courseware.semester!.isNotEmpty)
        courseware.semester!,
    ].join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: app.surfaceRaised,
        border: Border(
          bottom: BorderSide(
            color: app.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  courseware.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineLarge?.copyWith(color: app.onSurface),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs2),
                  Text(
                    meta,
                    style: text.bodySmall?.copyWith(
                      color: app.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppTextAction(
            label: '退出演示',
            semanticLabel: '退出演示',
            // maybePop 而非 pop：本页可能在只剩一条路由的 Navigator 里被直接当
            // home 挂载，pop 会弹掉根栈（整个 App）并撞 _history 断言。
            // 与 [AppPushedPage] 内部 `leave()` 落到同一个调用，Esc 走的是同一条路。
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  /// 从讲课现场直接进助手并聚焦当前知识点（ADR-0072 L2）。
  ///
  /// 复用全局同一 [AssistantChatPage]，只额外带上 [AssistantCoursewareContext]：
  /// 知识点 id 精确聚焦（无同名漂移），name / 学科 / 年级 / 学期作兼容与展示。
  /// 教师端形态（[isTeacher] = true）——讲课是教师的动作。
  void _openAssistant(BuildContext context, CoursewareModel courseware) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => AssistantChatPage(
          showBack: true,
          isTeacher: true,
          coursewareContext: AssistantCoursewareContext(
            coursewareId: courseware.id,
            knowledgePointId: courseware.knowledgePointId,
            knowledgePoint: courseware.kpName.isNotEmpty ? courseware.kpName : null,
            subject: courseware.subject,
            grade: courseware.grade,
            semester: courseware.semester,
          ),
        ),
      ),
    );
  }
}

/// 主区：环节标题 + 话术提问卡 + 按 kind 分派的环节内容。
///
/// 话术**不折叠**（决策 15）：投影时教师屏 = 学生所见，做「仅教师可见」在单屏下
/// 物理上不可能；且「这些图形有什么共同点？」抛出去才是引导学生观察，藏起来反而
/// 没了教学动作。
class _PresentStage extends StatelessWidget {
  const _PresentStage({super.key, required this.section});

  final CoursewareSectionModel section;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            section.title,
            style: text.titleLarge?.copyWith(color: app.onSurface),
          ),
          if (section.displaySegments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildScriptCard(context, app, text),
          ],
          const SizedBox(height: AppSpacing.lg),
          Expanded(child: SingleChildScrollView(child: _buildBody(context))),
        ],
      ),
    );
  }

  Widget _buildScriptCard(
    BuildContext context,
    AppColors app,
    AppText text,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: app.outline,
          width: AppElevation.borderWidthHairline,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '提问',
            style: text.labelSmall?.copyWith(
              color: app.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs2),
          CoursewareScriptSegmentsView(
            segments: section.displaySegments,
            baseStyle: text.titleMedium?.copyWith(
              color: app.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (section.kind) {
      CoursewareSectionKind.mediaGallery =>
        SectionMediaGallery(section: section),
      CoursewareSectionKind.interactiveScene =>
        SectionInteractiveScene(section: section),
      // practice 由 D 线交付（切片 7）；null = 后端先登记了前端还没枚举的新类型。
      // 两者都给降级提示而不是白屏——课堂上白屏等于「课件坏了」。
      CoursewareSectionKind.practice || null => AppEmptyState(
          icon: LucideIcons.circleAlert,
          title: section.isUnknownKind ? '暂不支持的环节类型' : '课堂练习还没接入',
          message: section.isUnknownKind
              ? '这份课件里有本版本还不认识的环节类型，这一段先用文字讲。'
              : '课堂练习走助手「课件练习」上下文，还没接进演示页，这一段先用文字讲。',
        ),
    };
  }
}

/// 底部：上一步 / `2 / 4` / 下一步。
class _PresentFooter extends StatelessWidget {
  const _PresentFooter({
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Container(
      decoration: BoxDecoration(
        color: app.surfaceRaised,
        border: Border(
          top: BorderSide(
            color: app.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          AppPrimaryButton(
            label: '上一步',
            icon: LucideIcons.chevronLeft,
            fullWidth: false,
            height: AppControl.heightLgOf(context),
            onPressed: onPrev,
          ),
          Expanded(
            child: Center(
              child: Text(
                '${index + 1} / $total',
                style: text.titleSmall?.copyWith(color: app.onSurface),
              ),
            ),
          ),
          AppPrimaryButton(
            label: '下一步',
            icon: LucideIcons.chevronRight,
            fullWidth: false,
            height: AppControl.heightLgOf(context),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
