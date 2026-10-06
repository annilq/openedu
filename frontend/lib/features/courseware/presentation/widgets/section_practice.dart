import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_courseware_context.dart';
import 'package:kids_learn/features/assistant/presentation/provider/assistant_notifier.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_message_list.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../domain/models/courseware.dart';
import '../../domain/models/courseware_section.dart';

/// `practice` 课堂练习环节（ADR-0067 §3.6）。
///
/// 学生口头回答，教师只在本地点击「对 / 错」；本组件不调用任务、作答、错题或
/// 掌握度能力。出题与答错提示都复用 [assistantNotifierProvider] 和
/// [AssistantMessageList]，经唯一的 `POST /assistant/chat` 通道完成。
class SectionPractice extends ConsumerStatefulWidget {
  const SectionPractice({
    super.key,
    required this.courseware,
    required this.section,
  });

  final CoursewareModel courseware;
  final CoursewareSectionModel section;

  @override
  ConsumerState<SectionPractice> createState() => _SectionPracticeState();
}

class _SectionPracticeState extends ConsumerState<SectionPractice> {
  bool _started = false;
  bool _hasQuestion = false;
  bool _correct = false;
  int _hintLevel = 0;
  String? _fallback;

  AssistantCoursewareContext get _context => AssistantCoursewareContext(
    coursewareId: widget.courseware.id,
    sectionId: widget.section.id,
    knowledgePoint: widget.courseware.kpName,
    subject: widget.courseware.subject,
    grade: widget.courseware.grade,
    semester: widget.courseware.semester,
  );

  Future<void> _requestQuestion() async {
    final qtype = '${widget.section.payload['qtype'] ?? '题目'}';
    setState(() {
      _started = true;
      _hasQuestion = false;
      _correct = false;
      _hintLevel = 0;
      _fallback = null;
    });
    final notifier = ref.read(assistantNotifierProvider.notifier);
    notifier.reset();
    await notifier.send('请为当前课堂练习出一道 $qtype 题，只展示题目。', courseware: _context);
    if (!mounted) return;
    final next = ref.read(assistantNotifierProvider);
    final text = _answerText(next);
    setState(() {
      _fallback = _failureOf(next, text);
      _hasQuestion =
          _fallback == null &&
          text.isNotEmpty &&
          !text.contains('未配置模型') &&
          !text.contains('暂无可用的 AI 引擎');
    });
  }

  Future<void> _requestHint() async {
    final level = (_hintLevel + 1).clamp(1, 3);
    setState(() {
      _hintLevel = level;
      _fallback = null;
    });
    await ref
        .read(assistantNotifierProvider.notifier)
        .send(
          '学生刚才口头回答错了，请给第 $level 级提示帮助他继续思考，不要直接说答案。',
          courseware: _context,
        );
    if (!mounted) return;
    final next = ref.read(assistantNotifierProvider);
    final text = _answerText(next);
    setState(() => _fallback = _failureOf(next, text));
  }

  void _markCorrect() => setState(() {
    _correct = true;
    _fallback = null;
  });

  String _answerText(AssistantState state) {
    if (state is! AssistantActive) return '';
    return state.messages
        .where((message) => message.role == 'ai' && !message.thinking)
        .map((message) => message.text)
        .where((text) => text.trim().isNotEmpty)
        .join('\n');
  }

  String? _failureOf(AssistantState state, String text) {
    if (state is AssistantActive && state.error) {
      return '课堂练习请求失败，请检查网络或模型配置后重试。';
    }
    if (text.isEmpty) {
      return '课堂练习请求失败，助手没有返回内容，请重试。';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantNotifierProvider);
    final streaming = state is AssistantActive && state.streaming;
    final messages =
        state is AssistantActive
            ? state.messages
                .where((message) => message.role == 'ai')
                .toList(growable: false)
            : const <AssistantMessage>[];
    return LayoutBuilder(
      builder:
          (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _QuestionPrompt(script: widget.section.script),
              const SizedBox(height: AppSpacing.lg),
              if (!_started)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _PracticeAction(
                    key: const ValueKey('courseware-practice-generate'),
                    label: '出题',
                    icon: LucideIcons.sparkles,
                    onPressed: streaming ? null : _requestQuestion,
                  ),
                ),
              if (_started) ...[
                _messageArea(constraints, messages),
                if (_fallback != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _PracticeNotice(message: _fallback!, error: true),
                ],
                const SizedBox(height: AppSpacing.lg),
                _actions(streaming),
              ],
            ],
          ),
    );
  }

  Widget _messageArea(
    BoxConstraints constraints,
    List<AssistantMessage> messages,
  ) {
    final list = AssistantMessageList(
      messages: messages,
      maxBubbleWidthFactor: 1,
    );
    if (constraints.hasBoundedHeight) return Expanded(child: list);
    return SizedBox(height: AppLayout.contentNarrow, child: list);
  }

  Widget _actions(bool streaming) {
    if (_correct) {
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const _PracticeNotice(message: '回答正确，可以继续下一题。'),
          _PracticeAction(
            label: '再出一题',
            icon: LucideIcons.refreshCw,
            onPressed: streaming ? null : _requestQuestion,
          ),
        ],
      );
    }
    if (!_hasQuestion) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _PracticeAction(
          label: '重新出题',
          icon: LucideIcons.refreshCw,
          onPressed: streaming ? null : _requestQuestion,
        ),
      );
    }
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        _PracticeAction(
          key: const ValueKey('courseware-practice-correct'),
          label: '对',
          icon: LucideIcons.check,
          fill: AppTheme.colorsOf(context).semanticPositive,
          foreground: AppTheme.colorsOf(context).semanticPositiveFg,
          onPressed: streaming ? null : _markCorrect,
        ),
        _PracticeAction(
          key: const ValueKey('courseware-practice-wrong'),
          label: _hintLevel == 0 ? '错' : '再提示一级',
          icon: LucideIcons.x,
          fill: AppTheme.colorsOf(context).semanticError,
          foreground: AppTheme.colorsOf(context).semanticErrorFg,
          onPressed: streaming ? null : _requestHint,
        ),
      ],
    );
  }
}

class _QuestionPrompt extends StatelessWidget {
  const _QuestionPrompt({required this.script});

  final String script;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppCard(
      margin: EdgeInsets.zero,
      color: app.semanticInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '课堂提问',
            style: text.labelSmall?.copyWith(color: app.semanticInfoFg),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            script.isEmpty ? '请根据下面的练习向学生提问。' : script,
            style: text.titleLarge?.copyWith(color: app.semanticInfoFg),
          ),
        ],
      ),
    );
  }
}

class _PracticeAction extends StatelessWidget {
  const _PracticeAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.fill,
    this.foreground,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? fill;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final background = fill ?? app.cta;
    final color = foreground ?? app.onCta;
    return AppFocusableAction(
      onTap: onPressed,
      enabled: onPressed != null,
      semanticLabel: label,
      hoverHighlight: true,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          constraints: BoxConstraints(
            minWidth: AppLayout.tapTarget * 2,
            minHeight: AppControl.heightLgOf(context),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: app.outline,
              width: AppElevation.borderWidth,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: AppSpacing.xl, color: color),
              const SizedBox(width: AppSpacing.sm),
              Text(label, style: text.labelLarge?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeNotice extends StatelessWidget {
  const _PracticeNotice({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: error ? app.semanticError : app.semanticPositive,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: app.outline,
          width: AppElevation.borderWidthHairline,
        ),
      ),
      child: Text(
        message,
        style: AppTheme.textOf(context).bodyMedium?.copyWith(
          color: error ? app.semanticErrorFg : app.semanticPositiveFg,
        ),
      ),
    );
  }
}
