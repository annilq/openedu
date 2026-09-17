// 守住「模型管理页」视觉契约：卡片标题可读、行内操作走应用字体、弹窗宽度足够。
//
// 背景：列表卡片曾直接用 `text.labelLarge` 当标题，而 labelLarge 前景色被系统设为
// `onCta`（用于按钮文字）→ 白字落在白卡片上完全不可见，用户以为「缺少 title」。
// 同时「编辑 / 删除」用裸 `CupertinoButton`，被 Cupertino 默认字体覆盖，中文字变糙。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/model_management/domain/models.dart';
import 'package:kids_learn/features/model_management/domain/repositories/models_repository.dart';
import 'package:kids_learn/features/model_management/domain/model_requests.dart';
import 'package:kids_learn/features/model_management/presentation/providers/models_notifier.dart';
import 'package:kids_learn/features/model_management/presentation/screens/model_form_dialog.dart';
import 'package:kids_learn/features/model_management/presentation/screens/parent_model_management_screen.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

class _StubRepo implements ModelsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SeededNotifier extends ModelsNotifier {
  _SeededNotifier(List<ModelInfo> custom, List<ModelProviderPreset> providers)
      : super(_StubRepo()) {
    state = ModelsLoaded(ModelListResp(custom: custom), providers);
  }
  @override
  Future<void> load() async {}
  @override
  Future<String?> create(ModelCreateReq req) async => null;
  @override
  Future<String?> update(String id, ModelUpdateReq req) async => null;
  @override
  Future<String?> delete(String id) async => null;
  @override
  Future<String?> setDefault(String id) async => null;
}

ModelInfo _model({
  required String id,
  required String label,
  bool isDefault = false,
}) =>
    ModelInfo(
      id: id,
      label: label,
      provider: 'openai_compat',
      baseUrl: 'https://api.example.com/v1',
      modelName: 'gpt-4o',
      isDefault: isDefault,
    );

const _presets = <ModelProviderPreset>[
  ModelProviderPreset(
    key: 'openai',
    label: 'OpenAI',
    provider: 'openai_compat',
    baseUrl: 'https://api.openai.com/v1',
    models: ['gpt-4o', 'gpt-4o-mini'],
    apiKeyHint: 'sk-xxxxxxxx',
  ),
];

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    List<ModelInfo> models, {
    Size size = const Size(900, 700),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelsNotifierProvider
              .overrideWith((ref) => _SeededNotifier(models, _presets)),
        ],
        child: ShadApp.custom(
          theme: AppTheme.shadFor(
              false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: const ParentModelManagementScreen(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('模型卡片标题可见（不是 onCta 白字）', (tester) async {
    await pumpScreen(tester, <ModelInfo>[_model(id: 'm1', label: '测试模型')]);

    final title = tester.widget<Text>(find.text('测试模型'));
    final app = AppTheme.colorsOf(tester.element(find.text('测试模型')));
    expect(title.style?.color, app.onSurface,
        reason: '卡片标题必须走 onSurface，labelLarge 的 onCta 会隐形');
  });

  testWidgets('默认模型不显示「设为默认」，操作行有间隔', (tester) async {
    await pumpScreen(tester, <ModelInfo>[
      _model(id: 'm1', label: '默认模型', isDefault: true),
      _model(id: 'm2', label: '普通模型'),
    ]);

    expect(find.text('设为默认'), findsOneWidget,
        reason: '只有非默认模型才需要「设为默认」入口');

    final edit = tester.getRect(find.text('编辑').first);
    final del = tester.getRect(find.text('删除').first);
    expect(edit.right, lessThan(del.left),
        reason: '「编辑」与「删除」之间必须留出间隙，不能黏在一起');
  });

  testWidgets('行内操作文字使用应用字体而非 Cupertino 系统字体', (tester) async {
    await pumpScreen(tester, <ModelInfo>[_model(id: 'm1', label: '测试模型')]);

    final edit = tester.widget<Text>(find.text('编辑'));
    expect(edit.style?.fontFamily, AppTheme.fontFamily,
        reason: '行内操作必须显式使用 Inter + Noto Sans SC，禁用 Cupertino 默认字体');
  });

  testWidgets('「删除」文字使用错误色', (tester) async {
    await pumpScreen(tester, <ModelInfo>[_model(id: 'm1', label: '测试模型')]);

    final app = AppTheme.colorsOf(tester.element(find.text('删除')));
    final delete = tester.widget<Text>(find.text('删除'));
    expect(delete.style?.color, app.error,
        reason: '删除是高危动作，文字必须走 error 色表态');
  });

  testWidgets('添加模型弹窗宽度升级到 dialogForm，API Key 输入框更宽', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelsNotifierProvider
              .overrideWith((ref) => _SeededNotifier(const [], _presets)),
        ],
        child: ShadApp.custom(
          theme: AppTheme.shadFor(
              false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 700,
                child: Center(
                  child: ModelFormDialog(
                    initial: null,
                    presets: _presets,
                    onDone: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 弹窗外层 ConstrainedBox 在直接嵌入时会占满 Center 的可用宽度（900），
    // 但真正的面板是内部的 DecoratedBox / 内容。用 API Key 输入框宽度来守。
    final inputs = find.byType(ShadInput);
    expect(inputs, findsAtLeastNWidgets(4));
    var maxW = 0.0;
    for (var i = 0; i < inputs.evaluate().length; i++) {
      final w = tester.getRect(inputs.at(i)).width;
      if (w > maxW) maxW = w;
    }
    expect(maxW, greaterThanOrEqualTo(500),
        reason: 'dialogForm(560) 应让输入框达到 ~512，旧 contentNarrow(480) 只有 ~432');
  });
}
