// 守住 ADR-0047：家长端 AI 助手是**整页**，不是浮层。
//
// 起因：浮球原先点开的是固定 380×540 的浮层面板——它与导航壳（侧栏 / 内容宽度）无关，
// 桌面 / 平板下压在内容上。所以这里断言的是「打开的容器铺满可用宽度」，而不是只断言
// 「渲染了 AssistantChatPage」：浮层时代该组件同样存在，只是被塞进一个 380 宽的盒子里。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_event.dart';
import 'package:kids_learn/features/assistant/domain/assistant_requests.dart';
import 'package:kids_learn/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:kids_learn/features/assistant/presentation/screens/assistant_chat_page.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/floating_assistant.dart';
import 'package:kids_learn/features/assistant/providers/assistant_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 假仓库：本测试只关心「打开的是哪个容器」，不关心对话内容，永不发请求。
class _NoopAssistant extends Fake implements AssistantRepository {
  @override
  Stream<AssistantEvent> chat(AssistantChatReq req) => const Stream.empty();
}

void main() {
  const bodyKey = ValueKey('host-body');
  const surfaceWidth = 1440.0;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(surfaceWidth, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantRepositoryProvider.overrideWithValue(_NoopAssistant()),
        ],
        // 必须显式传 theme：`ShadApp.custom` 不传会退回 shadcn 默认主题（ADR-0046 记录过
        // 这个坑），按钮被压到裁字，看起来像产品缺陷其实是测试替身。
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            home: FloatingAssistant(child: const SizedBox.expand(key: bodyKey)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('未点击时只浮着按钮，不预挂助手页', (tester) async {
    await pumpHost(tester);

    expect(find.byType(AssistantLauncher), findsOneWidget);
    expect(find.byType(AssistantChatPage), findsNothing,
        reason: '入口是浮动按钮；助手页只在点击后才存在（浮层时代这一断言也成立，'
            '但那时点开的是面板）');
  });

  testWidgets('点浮球打开的是整页：铺满可用宽度，而不是 380 宽浮层', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.byType(AssistantLauncher));
    await tester.pumpAndSettle();

    expect(find.byType(AssistantChatPage), findsOneWidget);
    expect(tester.getSize(find.byType(AssistantChatPage)).width, surfaceWidth,
        reason: '整页必须铺满可用宽度；浮层时代这里是 380（AppLayout.contentFloat）');
  });

  testWidgets('家长形态用家长口径的标题', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.byType(AssistantLauncher));
    await tester.pumpAndSettle();

    expect(find.text('AI 学习助手'), findsOneWidget);
    expect(find.text('问 AI 老师'), findsNothing,
        reason: '「问 AI 老师」是娃娃端页签的名字');
  });

  testWidgets('浮球键盘可达：Tab 到它、Enter 打开整页', (tester) async {
    await pumpHost(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(AssistantChatPage), findsOneWidget,
        reason: '浮球曾是裸 GestureDetector——不在焦点树里，Tab 跳不到、Enter 也点不动');
  });
}
