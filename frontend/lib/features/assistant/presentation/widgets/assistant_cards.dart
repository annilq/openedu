import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/utils/question_labels.dart';
import '../../domain/assistant_card.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_tags.dart';

/// AI 消息里的结构化卡片（ADR-0042）：按 [AssistantCard.kind] 分派版式。
///
/// 四条版式覆盖全部种类：
/// - [AssistantCardKind.question] → 题目卡（学科/题型/难度 + 题干 + 选项 + 答案 + 解析 + 出题思路）
/// - [AssistantCardKind.progress] → 指标卡（答对 / 正确率 / 打卡）
/// - [AssistantCardKind.notice] → 提示卡（标题 + 文本）
/// - [AssistantCardKind.guide] → 引导卡（说明 + 受控跳转出口）
/// - 其余列表类 → 列表卡（标题 + 归属 + 明细行）
///
/// **降级不丢内容**：认不出的种类若带 `items` 走列表卡的「通用行」，否则走提示卡。
/// v1 只认 `{type, subject, stem}` 且 `stem` 为空即 `SizedBox.shrink()`——新卡片
/// 到了前端会整张静默消失。
///
/// 卡片在气泡**外侧**（见 [AssistantMessageList]）：卡片自带 surface 底与描边，
/// 套在气泡里是双层容器。
class AssistantCardTile extends StatelessWidget {
  final AssistantCard card;

  /// 卡片动作出口（目前只有引导卡的 [AssistantCard.actions] 会用）。
  ///
  /// 由页面注入而不是卡片自己去 `Navigator.push`：同一条卡片在家长端是 push 的
  /// 整页、在娃娃端是壳内页签，**怎么退、退到哪只有宿主知道**。
  /// 传 null（如只读回放）时按钮不渲染——点不动的按钮比没有按钮更糟。
  final void Function(AssistantCardAction action)? onAction;

  const AssistantCardTile({super.key, required this.card, this.onAction});

  @override
  Widget build(BuildContext context) {
    if (!card.hasContent) return const SizedBox.shrink();
    final Widget body = switch (card.kind) {
      // 题目卡左侧学科色条由 Row(stretch) 撑满卡片高度；卡片高度随内容，
      // 消息流内高度无界，须 IntrinsicHeight 给 Row 一个有界高度。
      AssistantCardKind.question =>
          IntrinsicHeight(child: _QuestionCard(card: card)),
      AssistantCardKind.progress => _StatsCard(card: card),
      AssistantCardKind.notice => _TextCard(card: card),
      AssistantCardKind.guide => _GuideCard(card: card, onAction: onAction),
      _ => card.items.isEmpty ? _TextCard(card: card) : _ListCard(card: card),
    };
    return _CardShell(child: body);
  }
}

/// 卡片的可复制纯文本（「复制」按钮用）。
///
/// 与视觉渲染共用 [_rowOf] / [_statsOf]，所以「复制到的内容」与「看到的卡片」
/// 不会各写一套而漂移。卡片是可见内容，不该出现「有卡片却复制不到」。
String cardPlainText(AssistantCard card) {
  final head = [card.title, card.subject].where((e) => e.isNotEmpty).join(' · ');
  final lines = <String>[if (head.isNotEmpty) '【$head】'];

  if (card.kind == AssistantCardKind.question) {
    // 题卡载荷没有 title/heading 可言，统一用「题目」当块首，字段行自己带全信息。
    return ['【题目】', ..._questionLines(card)].join('\n');
  }

  if (card.kind == AssistantCardKind.progress) {
    final stats = _statsOf(card).map((s) => '${s.$2} ${s.$1}').join(' · ');
    if (stats.isNotEmpty) lines.add(stats);
    if (card.text.isNotEmpty) lines.add(card.text);
    return lines.join('\n');
  }

  if (card.text.isNotEmpty) lines.add(card.text);
  for (var i = 0; i < card.items.length; i++) {
    final row = _rowOf(card.kind, card.items[i]);
    final tags = row.tags.map((t) => t.$1).join(' · ');
    lines.add('${i + 1}. ${row.primary}${tags.isEmpty ? '' : '（$tags）'}');
  }
  if (card.total > card.items.length) lines.add('…共 ${card.total} 条');
  return lines.join('\n');
}

// ───────────────────────── 卡片壳 ─────────────────────────

/// 卡片容器：`surfaceRaised` 底 + 1px `outline` 描边 + card 圆角（与 AppCard 同款面）。
/// 不设外边距——卡片之间的间距由调用方控制（首个卡片贴气泡，后续卡片留间距）。
class _CardShell extends StatelessWidget {
  final Widget child;

  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    // 新粗野卡片容器：2px 墨黑描边 + 无模糊硬阴影（ADR-0044），由 AppCard 统一定义。
    // 不设外边距——卡片之间的间距由调用方控制（气泡 Column 内已留 SizedBox）。
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        margin: EdgeInsets.zero,
        child: child,
      ),
    );
  }
}

/// 卡片**类别色**：按语义族归并，而不是「一种卡片一个色」。
///
/// 为什么归并：`.impeccable.md` §Design Principles 2 要求**单屏色相 ≤ 3**，
/// 而会话回放（ADR-0048）里同一屏会连续出现多种卡片——9 种 kind 各配一色必然越限。
///
/// | 族 | kind | 色 |
/// |---|---|---|
/// | 待办 / 复习（要做的事） | `taskList` · `dueReviewList` · `guide` | `cyan` |
/// | 错题 / 掌握（要看的问题） | `wrongQuestionList` · `masteryList` · `questionBankList` | `magenta` |
/// | 结构 / 对话（无行动压力） | `question` · `progress` · `notice` · `childList` · 未登记 | 中性灰 |
///
/// `guide` 归「待办」族：它是**要用户去做一件事**的卡（去布置任务），
/// 与任务列表同一语义，不该长得像一条中性说明。
///
/// 两个族色都是**亮块**，前景一律由 [AppBrutal.onColor] 判成墨黑——不得手写黑/白。
/// 返回 `null` 表示走中性底座（`surfaceSunken` + `onSurfaceVariant`）。
Color? _familyFillOf(String kind) => switch (kind) {
      AssistantCardKind.taskList ||
      AssistantCardKind.dueReviewList ||
      AssistantCardKind.guide =>
        AppBrutal.cyan,
      AssistantCardKind.wrongQuestionList ||
      AssistantCardKind.masteryList ||
      AssistantCardKind.questionBankList =>
        AppBrutal.magenta,
      _ => null,
    };

/// 卡头：类别色图标底座 + 标题 +（右对齐的）归属。
///
/// [kind] 决定底座的类别色（见 [_familyFillOf]）；未传或属结构族时退化为中性灰
/// 底座——与收敛前那个裸 15px 灰图标同强度，不额外抢眼。
class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subject;
  final String kind;

  const _CardHeader({
    required this.icon,
    required this.title,
    this.subject = '',
    this.kind = '',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final fill = _familyFillOf(kind);
    return Row(
      children: [
        // 图标底座 32×32 + 1.5px 墨黑描边，规格取自 `parent_question_card` 的题号徽标
        // （密集小色块档 [AppElevation.borderWidthSm]）。
        //
        // 收敛前是一个 15px 的裸灰图标：9 种卡片在会话回放里长得一模一样，5 种列表卡
        // 又共用同一个 `_ListCard` 版式，用户分不出「这是到期复习还是错题列表」。
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: fill ?? scheme.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: AppBrutal.ink,
              width: AppElevation.borderWidthSm,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 17,
            color: fill == null
                ? scheme.onSurfaceVariant
                : AppBrutal.onColor(fill),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
        if (subject.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────── 列表卡 ─────────────────────────

class _ListCard extends StatelessWidget {
  final AssistantCard card;

  const _ListCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final rows = card.items.map((i) => _rowOf(card.kind, i)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardHeader(
          icon: _iconOf(card.kind),
          title: card.title,
          subject: card.subject,
          kind: card.kind,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          Text(
            rows[i].primary,
            style: text.bodyMedium?.copyWith(color: scheme.onSurface),
          ),
          if (rows[i].tags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [for (final tag in rows[i].tags) _tagWidget(tag)],
            ),
          ],
        ],
        // 服务端只回前 N 条明细，截断了要说清楚（别让人以为就这几条）。
        if (card.total > rows.length) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '…共 ${card.total} 条',
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────── 指标卡（progress）─────────────────────────

class _StatsCard extends StatelessWidget {
  final AssistantCard card;

  const _StatsCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final stats = _statsOf(card);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardHeader(
          icon: _iconOf(card.kind),
          title: card.title,
          subject: card.subject,
          kind: card.kind,
        ),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xxl,
            runSpacing: AppSpacing.md,
            children: [
              for (final s in stats)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.$1,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    Text(
                      s.$2,
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
        if (card.text.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            card.text,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────── 提示卡（notice / 空结果 / 未知种类）─────────────────────────

class _TextCard extends StatelessWidget {
  final AssistantCard card;

  const _TextCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (card.title.isNotEmpty)
          _CardHeader(
            icon: _iconOf(card.kind),
            title: card.title,
            subject: card.subject,
            kind: card.kind,
          ),
        if (card.title.isNotEmpty && card.text.isNotEmpty)
          const SizedBox(height: AppSpacing.sm),
        if (card.text.isNotEmpty)
          Text(
            card.text,
            style: text.bodyMedium?.copyWith(
              // notice = 查询失败这类坏消息，用语义 error 前景，别和普通空结果同色。
              color: card.kind == AssistantCardKind.notice
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

// ───────────────────────── 引导卡（guide）─────────────────────────

/// 引导卡：一句「为什么不能」+ 一个（或几个）**受控跳转出口**。
///
/// 这张卡补的是这条链路上唯一真正断掉的一环：助手是只读的（不是缺陷，是边界），
/// 但「你不能做」不该是终点——用户需要下一步。在此之前后端只能回一句
/// 「请到『任务/作业』页面操作」，而卡片协议里**没有任何位置**能放那个入口，
/// 于是用户被告知去别处、却拿不到别处。
///
/// [onAction] 为 null 时不渲染出口：只读回放里没人接这个动作，
/// 给一个点不动的按钮比不给更糟（会让人以为界面坏了）。
class _GuideCard extends StatelessWidget {
  final AssistantCard card;
  final void Function(AssistantCardAction action)? onAction;

  const _GuideCard({required this.card, this.onAction});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    // 出口按「宿主给没给处理器」决定要不要画：给不出落点的按钮不如不画。
    final buttons = <Widget>[];
    final handler = onAction;
    if (handler != null) {
      for (final action in card.actions) {
        buttons.add(
          AppPrimaryButton(
            label: action.label,
            fullWidth: false,
            onPressed: () => handler(action),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardHeader(
          icon: _iconOf(card.kind),
          title: card.title,
          subject: card.subject,
          kind: card.kind,
        ),
        if (card.text.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            card.text,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.5,
            ),
          ),
        ],
        if (buttons.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          // 并排按钮一律 Wrap：ShadButton 放进会压缩它的容器（Row/Expanded）
          // 会 RenderFlex overflowed——卡片在消息流里宽度有限，尤其容易撞上。
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: buttons,
          ),
        ],
      ],
    );
  }
}

// ───────────────────────── 题目卡（question）─────────────────────────

class _QuestionCard extends StatelessWidget {
  final AssistantCard card;

  const _QuestionCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final raw = card.rawPayload;
    final subject = _s(raw['subject']);
    final grade = _i(raw['grade']);
    final qtype = _s(raw['qtype']);
    final difficulty = _s(raw['difficulty']);
    final stem = _s(raw['stem']);
    final options = raw['options'] is List
        ? (raw['options'] as List).map(_s).where((o) => o.isNotEmpty).toList()
        : const <String>[];
    final answer = _s(raw['answer']);
    final explanation = _s(raw['explanation']);
    final reasoning = _s(raw['reasoning']);

    // 题目卡学科编码：左侧学科色条 + 学科 chip（chip 自带几何标记，见下方 Wrap）。
    final subjectKey = SubjectAccent.fromName(subject);
    final hasSubject = subject.isNotEmpty;
    final subjectColor = hasSubject
        ? SubjectAccent.forContext(subjectKey, context).accent
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasSubject)
          Container(
            width: 6,
            margin: const EdgeInsets.only(right: AppSpacing.md),
            decoration: BoxDecoration(
              color: subjectColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardHeader(icon: LucideIcons.sparkles, title: '题目'),
              const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            if (subject.isNotEmpty)
              AppTags.subject(SubjectAccent.fromName(subject), label: subject),
            if (grade > 0) AppTags.normal('$grade 年级'),
            if (qtype.isNotEmpty) AppTags.normal(qtypeLabel(qtype)),
            if (difficulty.isNotEmpty)
              AppTags.normal(difficultyLabel(difficulty)),
          ],
        ),
        if (stem.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            stem,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.5,
            ),
          ),
        ],
        if (options.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${String.fromCharCode(65 + i)}.',
                    style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      options[i],
                      style: text.bodySmall?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (answer.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.checkCircle2,
                  size: 15, color: scheme.semanticPositiveFg),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '答案：$answer',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.semanticPositiveFg,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (explanation.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '解析：$explanation',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (reasoning.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _ReasoningDisclosure(reasoning: reasoning),
        ],
      ],
            ),
          ),
        ],
      );
  }
}

/// 出题思路折叠块：默认收起（正题优先），点开看 AI 为什么出这道题（ADR-0017）。
///
/// 用折叠而非弹层：卡片在消息流里，弹层会打断阅读；也避免与 [CupertinoButton]
/// 的 sheet 依赖。收起态给一句提示，不隐藏「有思路可看」这件事。
class _ReasoningDisclosure extends StatefulWidget {
  final String reasoning;

  const _ReasoningDisclosure({required this.reasoning});

  @override
  State<_ReasoningDisclosure> createState() => _ReasoningDisclosureState();
}

class _ReasoningDisclosureState extends State<_ReasoningDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 不用 InkWell：App 根是 CupertinoApp/ShadApp，子树无 Material 祖先。
        // 也不留裸 GestureDetector——它不进焦点树，桌面端 Tab 跳不过来、Enter
        // 点不动，而 `flutter analyze` 照不出来（ADR-0046）。标题文字本身可读，
        // 故不另传 semanticLabel。
        AppFocusableAction(
          onTap: () => setState(() => _open = !_open),
          hoverHighlight: true,
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '出题思路',
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              // 固定 chevronDown + turns 旋转，取代原先 `_open ? chevronUp :
              // chevronDown` 的硬切换：硬切换没有过渡，箭头会「跳」一下。
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: _openDuration(context),
                child: Icon(LucideIcons.chevronDown,
                    size: 14, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // 展开/收起走高度过渡，不再是 `if (_open)` 的瞬时增删。
        AnimatedSize(
          duration: _openDuration(context),
          curve: AppCurves.state,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: scheme.surfaceSunken,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Text(
                      widget.reasoning,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// 折叠过渡时长：隐式动画**不自动尊重** reduce-motion，必须显式归零（ADR-0044）。
Duration _openDuration(BuildContext context) =>
    reducedMotionOf(context) ? Duration.zero : AppMotion.state;

// ───────────────────────── 明细行投影（视觉 + 复制共用一份）─────────────────────────

enum _Tone { normal, info, success, warning, subject }

typedef _Row = ({String primary, List<(String, _Tone)> tags});

/// 一条明细 → 主行 + 标签。未知种类走「通用行」：不丢内容，宁可朴素。
_Row _rowOf(String kind, Map<String, dynamic> item) {
  final subject = _s(item['subject']);
  switch (kind) {
    case AssistantCardKind.taskList:
      final count = _i(item['question_count']);
      final status = _s(item['status']);
      return (
        primary: _s(item['title']),
        tags: [
          (statusLabel(status), _statusTone(status)),
          if (count > 0) ('$count 题', _Tone.info),
        ],
      );
    case AssistantCardKind.wrongQuestionList:
      return (
        primary: _s(item['stem']),
        tags: [
          if (subject.isNotEmpty) (subject, _Tone.subject),
          ('错过 ${_i(item['wrong_count'])} 次', _Tone.warning),
        ],
      );
    case AssistantCardKind.dueReviewList:
      return (
        primary: _s(item['stem']),
        tags: [
          if (subject.isNotEmpty) (subject, _Tone.subject),
          ('复习阶段 ${_i(item['review_stage'])}', _Tone.info),
        ],
      );
    case AssistantCardKind.masteryList:
      final level = _s(item['level']);
      final wrong = _i(item['active_wrong']);
      return (
        primary: _s(item['knowledge_point']),
        tags: [
          if (subject.isNotEmpty) (subject, _Tone.subject),
          ('${_trimZero(_d(item['score']))} 分', _Tone.normal),
          if (level.isNotEmpty) (level, _Tone.info),
          if (wrong > 0) ('错题 $wrong', _Tone.warning),
        ],
      );
    case AssistantCardKind.questionBankList:
      final kp = _s(item['knowledge_point']);
      final usage = _i(item['usage_count']);
      final diff = _i(item['difficulty']);
      return (
        primary: _s(item['stem']),
        tags: [
          if (subject.isNotEmpty) (subject, _Tone.subject),
          if (kp.isNotEmpty) (kp, _Tone.info),
          if (diff > 0) ('难度 $diff', _Tone.normal),
          if (usage > 0) ('复用 $usage 次', _Tone.success),
        ],
      );
    default:
      final primary = _firstOf(item, const ['stem', 'title', 'name', 'knowledge_point']);
      final rest = item.entries
          .where((e) => e.value is String || e.value is num)
          .where((e) => _s(e.value).isNotEmpty && _s(e.value) != primary)
          .map((e) => '${e.key}: ${_s(e.value)}')
          .take(3);
      return (primary: primary, tags: [for (final r in rest) (r, _Tone.normal)]);
  }
}

List<(String, String)> _statsOf(AssistantCard card) {
  final stats = card.stats;
  final total = _i(stats['total']);
  final correct = _i(stats['correct']);
  final accuracy = _d(stats['accuracy']);
  final streak = _i(stats['streak_days']);
  final checkin = _i(stats['checkin_days']);
  return [
    ('$correct/$total', '答对'),
    ('${(accuracy * 100).round()}%', '正确率'),
    ('$streak 天', '连续打卡'),
    if (checkin > 0) ('$checkin 天', '累计打卡'),
  ];
}

/// 题目卡的纯文本行（复制用）：题干 / 选项 / 答案 / 解析 / 出题思路。
List<String> _questionLines(AssistantCard card) {
  final raw = card.rawPayload;
  final lines = <String>[
    if (_s(raw['subject']).isNotEmpty ||
        _s(raw['qtype']).isNotEmpty ||
        _s(raw['difficulty']).isNotEmpty)
      [
        _s(raw['subject']),
        if (_i(raw['grade']) > 0) '${_i(raw['grade'])} 年级',
        if (_s(raw['qtype']).isNotEmpty) qtypeLabel(_s(raw['qtype'])),
        if (_s(raw['difficulty']).isNotEmpty) difficultyLabel(_s(raw['difficulty'])),
      ].where((e) => e.isNotEmpty).join(' · '),
    if (_s(raw['stem']).isNotEmpty) _s(raw['stem']),
  ];
  if (raw['options'] is List) {
    final options = (raw['options'] as List).map(_s).where((o) => o.isNotEmpty).toList();
    for (var i = 0; i < options.length; i++) {
      lines.add('${String.fromCharCode(65 + i)}. ${options[i]}');
    }
  }
  if (_s(raw['answer']).isNotEmpty) lines.add('答案：${_s(raw['answer'])}');
  if (_s(raw['explanation']).isNotEmpty) lines.add('解析：${_s(raw['explanation'])}');
  if (_s(raw['reasoning']).isNotEmpty) lines.add('出题思路：${_s(raw['reasoning'])}');
  return lines;
}

Widget _tagWidget((String, _Tone) tag) => switch (tag.$2) {
      _Tone.info => AppTags.info(tag.$1),
      _Tone.success => AppTags.success(tag.$1),
      _Tone.warning => AppTags.warning(tag.$1),
      _Tone.subject => AppTags.subject(
          SubjectAccent.fromName(tag.$1),
          label: tag.$1,
        ),
      _Tone.normal => AppTags.normal(tag.$1),
    };

IconData _iconOf(String kind) => switch (kind) {
      AssistantCardKind.question => LucideIcons.sparkles,
      AssistantCardKind.taskList => LucideIcons.listChecks,
      AssistantCardKind.wrongQuestionList => LucideIcons.bookOpen,
      AssistantCardKind.dueReviewList => LucideIcons.calendarClock,
      AssistantCardKind.masteryList => LucideIcons.target,
      AssistantCardKind.childList => LucideIcons.user,
      AssistantCardKind.progress => LucideIcons.barChart3,
      AssistantCardKind.questionBankList => LucideIcons.library,
      AssistantCardKind.guide => LucideIcons.cornerDownRight,
      _ => LucideIcons.info,
    };

_Tone _statusTone(String status) => switch (status) {
      'done' => _Tone.success,
      'assigned' => _Tone.info,
      _ => _Tone.normal,
    };

String _s(Object? v) => v == null ? '' : '$v'.trim();

int _i(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(_s(v)) ?? 0;
}

double _d(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse(_s(v)) ?? 0;
}

/// `72.0` → `72`，`72.5` → `72.5`（分数是小数，但整数别显示成 `72.0`）。
String _trimZero(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

String _firstOf(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final v = _s(item[key]);
    if (v.isNotEmpty) return v;
  }
  return '';
}
