import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/screens/student_detail_screen.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 学生详情页（T13）守卫：
///   1. 在「不套 Material」的树里真构建通过（ShadApp + CupertinoApp，无 Material 祖先）；
///   2. 三页签（概览 / 错题本 / AI 答疑）均渲染；
///   3. 页签切换为**局部状态**——切走概览后「快捷查看」消失，切回又出现，
///      不依赖全局选中态（ADR-0059 核心教训）。
void main() {
  testWidgets('学生详情页：非 Material 树构建 + 页签局部切换', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            home: StudentDetailScreen(studentId: 's1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 三个页签都在（非 Material 树里真构建通过）。
    expect(find.text('概览'), findsWidgets);
    expect(find.text('错题本'), findsWidgets);
    expect(find.text('AI 答疑'), findsWidgets);

    // 概览默认：快捷查看区可见。
    expect(find.text('快捷查看'), findsOneWidget);

    // 切到错题本：局部状态切换，快捷查看区消失。
    await tester.tap(find.text('错题本').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('快捷查看'), findsNothing);

    // 切回概览：快捷查看区重新出现，证明是局部状态而非全局。
    await tester.tap(find.text('概览').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('快捷查看'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
