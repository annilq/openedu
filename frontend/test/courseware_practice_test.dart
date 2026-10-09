import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/domain/models/assistant_courseware_context.dart';
import 'package:kids_learn/features/assistant/domain/assistant_event.dart';
import 'package:kids_learn/features/assistant/domain/assistant_requests.dart';
import 'package:kids_learn/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:kids_learn/features/assistant/providers/assistant_provider.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_section.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_section_kind.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_practice_block.dart';
import 'package:kids_learn/features/courseware/presentation/widgets/section_practice.dart';
import 'package:kids_learn/features/courseware/presentation/widgets/section_practice_edit_block.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

class _RecordingAssistant extends Fake implements AssistantRepository {
  _RecordingAssistant({this.fail = false, this.unconfigured = false});

  final bool fail;
  final bool unconfigured;
  final List<AssistantChatReq> requests = [];

  @override
  Stream<AssistantEvent> chat(AssistantChatReq req) {
    requests.add(req);
    if (fail) return Stream.error(Exception('连接中断'));
    final text =
        unconfigured
            ? '未配置模型，无法生成课堂练习。请在「模型管理」中添加模型并设为默认后重试。'
            : requests.length == 1
            ? '下面哪个图形是轴对称图形？\nA. 平行四边形\nB. 正方形'
            : '先观察图形沿一条直线对折后，两侧能否完全重合。';
    return Stream.fromIterable([
      AssistantEvent(
        eventType: AssistantEventType.assistantMessage,
        text: text,
      ),
      AssistantEvent(
        eventType: AssistantEventType.done,
        sessionId: 'courseware-session',
      ),
    ]);
  }
}

const _courseware = CoursewareModel(
  id: 'cw-1',
  subject: '数学',
  grade: 4,
  semester: '下学期',
  kpName: '轴对称图形',
  title: '图形的运动',
);

const _section = CoursewareSectionModel(
  id: 'practice-1',
  kind: CoursewareSectionKind.practice,
  title: '课堂练习',
  script: '下面哪些图形是轴对称图形？',
  practice: CoursewarePracticeBlock(qtype: 'choice', count: 1),
);

Future<void> _pumpPractice(
  WidgetTester tester,
  AssistantRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [assistantRepositoryProvider.overrideWithValue(repository)],
      // 刻意不套 Material：真实根节点是 ShadApp + CupertinoApp。
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder:
            (_) => const CupertinoApp(
              home: Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox(
                  width: 900,
                  height: 700,
                  child: SectionPractice(
                    courseware: _courseware,
                    section: _section,
                  ),
                ),
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('AssistantChatReq 仅在提供时序列化课件上下文', () {
    const plain = AssistantChatReq(message: '你好');
    expect(plain.toJson().containsKey('courseware'), isFalse);

    final contextual =
        const AssistantChatReq(
          message: '出题',
          courseware: _coursewareContext,
        ).toJson();
    expect(contextual['courseware'], {
      'courseware_id': 'cw-1',
      'section_id': 'practice-1',
      'knowledge_point': '轴对称图形',
      'subject': '数学',
      'grade': 4,
      'semester': '下学期',
    });
  });

  testWidgets('无 Material 祖先下可出题、判错并请求分级提示', (tester) async {
    final repository = _RecordingAssistant();
    await _pumpPractice(tester, repository);

    expect(find.text('下面哪些图形是轴对称图形？'), findsOneWidget);
    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.requests, hasLength(1));
    expect(repository.requests.first.courseware?.toJson(), {
      'courseware_id': 'cw-1',
      'section_id': 'practice-1',
      'knowledge_point': '轴对称图形',
      'subject': '数学',
      'grade': 4,
      'semester': '下学期',
    });
    expect(find.textContaining('正方形'), findsOneWidget);
    expect(find.text('对'), findsOneWidget);
    expect(find.text('错'), findsOneWidget);

    await tester.tap(find.text('错'));
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(2));
    // T05：默认「方向」级透传，提示词带级别且约束「不给关键条件 / 不直接说答案」。
    expect(repository.requests.last.message, contains('方向'));
    expect(repository.requests.last.message, contains('不要直接说答案'));
    expect(repository.requests.last.courseware?.extra, {'hint_level': 'direction'});
    expect(repository.requests.last.courseware?.sectionId, 'practice-1');
    expect(find.textContaining('先观察图形'), findsOneWidget);
    // 反馈卡：级别 + 不建任务 / 不记录作答说明。
    expect(find.textContaining('已给【方向】级提示'), findsOneWidget);
    expect(find.textContaining('不建任务'), findsOneWidget);
  });

  testWidgets('提示级别选择器可切换，选「下一步」后请求体带对应级别',
      (tester) async {
    final repository = _RecordingAssistant();
    await _pumpPractice(tester, repository);

    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();

    // 切换到「下一步」级（默认方向）。
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('提示级别'), findsOneWidget);

    await tester.tap(find.text('错'));
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.courseware?.extra, {'hint_level': 'next_step'});
    expect(repository.requests.last.message, contains('下一步'));
    expect(repository.requests.last.message, contains('下一步该做什么操作'));
    expect(find.textContaining('已给【下一步】级提示'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('提示级别「条件」级请求体携带对应约束', (tester) async {
    final repository = _RecordingAssistant();
    await _pumpPractice(tester, repository);

    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('条件'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('错'));
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.courseware?.extra, {'hint_level': 'condition'});
    expect(repository.requests.last.message, contains('关键条件'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('练习始终不落任务 / 作答（仅走课堂助手通道）', (tester) async {
    final repository = _RecordingAssistant();
    await _pumpPractice(tester, repository);

    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('错'));
    await tester.pumpAndSettle();

    // 全程只产生助手聊天请求，无任何任务 / 作答落库调用。
    expect(repository.requests.length, 2);
    expect(repository.requests.every((r) => r.courseware != null), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('请求失败显示明确兜底文案', (tester) async {
    await _pumpPractice(tester, _RecordingAssistant(fail: true));

    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();

    expect(find.text('课堂练习请求失败，请检查网络或模型配置后重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未配置模型时直接展示可操作提示', (tester) async {
    await _pumpPractice(tester, _RecordingAssistant(unconfigured: true));

    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未配置模型'), findsOneWidget);
    expect(find.text('重新出题'), findsOneWidget);
  });

  testWidgets('课堂练习编辑块：添加 / 改题型 / 移除（T06 第四内容块）',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
          appBuilder: (_) => CupertinoApp(
            home: Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: 900,
                height: 700,
                child: const _PracticeBlockHarness(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 起手无练习：只一颗「添加练习」。
    expect(find.text('添加练习'), findsOneWidget);
    expect(find.text('移除练习'), findsNothing);

    await tester.tap(find.text('添加练习'));
    await tester.pumpAndSettle();
    // 添加后展开配置：题型 / 题量 / 移除。
    expect(find.text('题型'), findsOneWidget);
    expect(find.text('题量'), findsOneWidget);
    expect(find.text('移除练习'), findsOneWidget);

    // 改题型为「计算题」→ 回写 qtype=calc。点的是选择器触发器（不是「题型」标签）。
    await tester.tap(find.byWidgetPredicate((w) => w is ShadSelect));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算题'));
    await tester.pumpAndSettle();
    final block = tester
        .widget<SectionPracticeEditBlock>(find.byType(SectionPracticeEditBlock))
        .practice;
    expect(block?.qtype, 'calc');

    // 移除 → 回到无练习态。
    await tester.tap(find.text('移除练习'));
    await tester.pumpAndSettle();
    expect(find.text('添加练习'), findsOneWidget);
    expect(find.text('移除练习'), findsNothing);
    expect(
      tester
          .widget<SectionPracticeEditBlock>(find.byType(SectionPracticeEditBlock))
          .practice,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}

const _coursewareContext = AssistantCoursewareContext(
  coursewareId: 'cw-1',
  sectionId: 'practice-1',
  knowledgePoint: '轴对称图形',
  subject: '数学',
  grade: 4,
  semester: '下学期',
);

/// 给练习编辑块套一个有 state 的父，便于测试「添加 / 移除 / 改题型」回写。
class _PracticeBlockHarness extends StatefulWidget {
  const _PracticeBlockHarness();

  @override
  State<_PracticeBlockHarness> createState() => _PracticeBlockHarnessState();
}

class _PracticeBlockHarnessState extends State<_PracticeBlockHarness> {
  CoursewarePracticeBlock? practice;

  @override
  Widget build(BuildContext context) => SectionPracticeEditBlock(
        practice: practice,
        onChanged: (p) => setState(() => practice = p),
      );
}
