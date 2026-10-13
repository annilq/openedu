import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_suggested_action.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_suggested_actions.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 票 03(a)：[AssistantSuggestedActions] 的「给定列表」模式——直接渲染服务端随
/// `SUGGESTED_ACTIONS` 帧下发的 chips，不再走 provider 拉取空态目录。
void main() {
  testWidgets('given-list 模式直接渲染 chips（prompt / navigate 分野）', (tester) async {
    final actions = [
      SuggestedAction(label: '我要问个问题', kind: 'prompt', payload: 'q'),
      SuggestedAction(label: '看看孩子错题', kind: 'navigate', payload: 'teacher_task_list'),
    ];
    await tester.pumpWidget(
      ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (_) => CupertinoApp(
          home: ShadToaster(
            child: AssistantSuggestedActions(
              givenActions: actions,
              onPrompt: (_) {},
              onNavigate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('试试这些：'), findsOneWidget);
    expect(find.text('我要问个问题'), findsWidgets);
    expect(find.text('看看孩子错题'), findsWidgets);
  });

  testWidgets('空给定列表 → 不渲染', (tester) async {
    await tester.pumpWidget(
      ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (_) => CupertinoApp(
          home: ShadToaster(
            child: AssistantSuggestedActions(
              givenActions: const [],
              onPrompt: (_) {},
              onNavigate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('试试这些：'), findsNothing);
  });
}
