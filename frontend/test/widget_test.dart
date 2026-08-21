// 应用根组件冒烟测试：验证 MyApp 在 ProviderScope 下可正常构建渲染。
// （flutter create 生成的计数器模板与本项目无关，已替换为真实根组件冒烟。）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kids_learn/main/app.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';

void main() {
  testWidgets('App 根组件可构建并渲染登录页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 未登录时落到登录页
    expect(find.byType(MyApp), findsOneWidget);
    expect(find.text('登录'), findsWidgets);
  });
}
