// 控件高度对齐守卫（规则见 AppControl 文档 / docs/adr/0044）
//
// 为什么需要：输入框、按钮、选择器同属「交互控件」，**同行必须严格同高**——错落是
// 用户一眼就能看出来的缺陷，且极易复发：
//   1. 给 ShadButton / ShadInput 传一次硬编码 height（仓里曾同时存在 32 / 36 / 40 / 52）；
//   2. 漏掉 `ShadButton.height` 是「内容盒高」而描边画在盒外，直接透传会高出 2×描边宽；
//   3. 用一个自带默认 minSize 的控件（CupertinoButton 的 44×44）混进同一行。
// 这三条历史上都发生过，最终积累出「输入框 32 而按钮 40」的局面。
//
// 因此本测试守两件事：
//   1. **阶梯结构**——标准档 = 锚点 −1 阶、紧凑档 = 锚点 −2 阶（调档位只需改锚点）；
//   2. **真实渲染高度**——量的是 `getSize` 出来的实测值，不是主题声明值。
//      （声明 32 却渲染 40 正是当初的 bug，只看声明值是发现不了的。）
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_inputs.dart';

const _k = ValueKey('control-height-guard');

Widget _host(
  Widget child, {
  required AppUserMode mode,
  required AppDensity density,
}) =>
    ShadTheme(
      data: AppTheme.shadFor(false, mode, density),
      child: UserModeScope(
        mode: mode,
        child: DensityScope(
          density: density,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(900, 700)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 400, child: child),
              ),
            ),
          ),
        ),
      ),
    );

/// 实测给定 widget 的渲染高度。
Future<double> _measure(
  WidgetTester tester,
  Widget child, {
  AppUserMode mode = AppUserMode.parent,
  AppDensity density = AppDensity.compact,
}) async {
  await tester.pumpWidget(_host(child, mode: mode, density: density));
  await tester.pumpAndSettle();
  return tester.getSize(find.byKey(_k)).height;
}

void main() {
  group('控件高度阶梯结构', () {
    test('标准档 = 锚点 −1 阶，紧凑档 = 锚点 −2 阶', () {
      for (final mode in AppUserMode.values) {
        for (final density in AppDensity.values) {
          final lg = AppControl.heightLg(mode, density);
          expect(AppControl.height(mode, density), lg - AppControl.step,
              reason: '标准档 ${mode.name}/${density.name}');
          expect(AppControl.heightSm(mode, density), lg - 2 * AppControl.step,
              reason: '紧凑档 ${mode.name}/${density.name}');
        }
      }
    });

    test('阶梯取值表与文档一致（改动即需同步 AppControl 文档与 ADR-0044）', () {
      // 「child 比 parent 大一档」与「normal 比 compact 大一档」是同一个 +8 位移，
      // 故 child·compact 与 parent·normal 必然同值。
      expect(AppControl.heightSm(AppUserMode.parent, AppDensity.compact), 32);
      expect(AppControl.height(AppUserMode.parent, AppDensity.compact), 40);
      expect(AppControl.heightLg(AppUserMode.parent, AppDensity.compact), 48);

      expect(AppControl.heightSm(AppUserMode.parent, AppDensity.normal), 40);
      expect(AppControl.height(AppUserMode.parent, AppDensity.normal), 48);
      expect(AppControl.heightLg(AppUserMode.parent, AppDensity.normal), 56);

      expect(AppControl.heightSm(AppUserMode.child, AppDensity.compact), 40);
      expect(AppControl.height(AppUserMode.child, AppDensity.compact), 48);
      expect(AppControl.heightLg(AppUserMode.child, AppDensity.compact), 56);

      expect(AppControl.heightSm(AppUserMode.child, AppDensity.normal), 48);
      expect(AppControl.height(AppUserMode.child, AppDensity.normal), 56);
      expect(AppControl.heightLg(AppUserMode.child, AppDensity.normal), 64);
    });

    test('标准档不低于触控下限（Material 48dp 下一档 = 40）', () {
      // 32 是桌面鼠标工具的惯例（Ant Design / Element Plus），低于所有触控规范；
      // 本项目平板优先、纯触控，标准档不得回退到 32 及以下。
      for (final mode in AppUserMode.values) {
        for (final density in AppDensity.values) {
          expect(AppControl.height(mode, density),
              greaterThanOrEqualTo(40.0),
              reason: '标准档 ${mode.name}/${density.name} 不得回退到桌面档');
        }
      }
    });
  });

  group('实测渲染高度与标准档严格相等', () {
    testWidgets('parent / compact（默认档）', (tester) async {
      final std = AppControl.height(AppUserMode.parent, AppDensity.compact);

      expect(await _measure(tester, ShadInput(key: _k, placeholder: const Text('x'))),
          std, reason: 'ShadInput');
      expect(
          await _measure(tester,
              ShadButton(key: _k, onPressed: () {}, child: const Text('按钮'))),
          std, reason: 'ShadButton');
      expect(
          await _measure(tester,
              ShadButton.outline(key: _k, onPressed: () {}, child: const Text('按钮'))),
          std, reason: 'ShadButton.outline');
      expect(
          await _measure(tester,
              ShadButton.secondary(key: _k, onPressed: () {}, child: const Text('按钮'))),
          std, reason: 'ShadButton.secondary');
      // ghost / link 无描边 → 内容盒高即可见高，主题须单独给一套尺寸，
      // 否则会与实心按钮差 2×描边宽。
      expect(
          await _measure(tester,
              ShadButton.ghost(key: _k, onPressed: () {}, child: const Text('按钮'))),
          std, reason: 'ShadButton.ghost');
      expect(
          await _measure(
              tester,
              AppPrimaryButton(
                  key: _k, label: '提交', fullWidth: false, onPressed: () {})),
          std, reason: 'AppPrimaryButton（内部做 contentHeight 折算）');
      expect(
          await _measure(
              tester,
              AppBrutalButton(
                  key: _k, label: '提交', fill: AppBrutal.yellow, onPressed: () {})),
          std, reason: 'AppBrutalButton');
      expect(
          await _measure(tester,
              AppIconAction(key: _k, icon: LucideIcons.x, onPressed: () {})),
          std, reason: 'AppIconAction（收口 CupertinoButton 的 44×44 默认 minSize）');
      // 选择器：与应用一致用 tight 约束包住（app_inputs 的写法）。
      expect(
          await _measure(
              tester,
              Builder(
                builder: (ctx) => ConstrainedBox(
                  constraints: AppControl.inputConstraintsOf(ctx),
                  child: ShadSelect<String>(
                    key: _k,
                    // 传 initialValue，规避 shadcn「value 为 null 时 placeholder 必须非空」断言。
                    initialValue: 'a',
                    options: const [ShadOption(value: 'a', child: Text('A'))],
                    selectedOptionBuilder: (_, v) => Text(v),
                    onChanged: (_) {},
                  ),
                ),
              )),
          std, reason: 'ShadSelect');

      // AppTextField 是「label + 间距 + 输入框」的整列，整列高无意义——
      // 要守的是它内部那个 ShadInput（真正与按钮同行比对的控件）。
      await tester.pumpWidget(_host(
        AppTextField(label: '总题数', controller: TextEditingController()),
        mode: AppUserMode.parent,
        density: AppDensity.compact,
      ));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ShadInput)).height, std,
          reason: 'AppTextField 内部 ShadInput');
    });

    testWidgets('child / compact 随模式放大一档', (tester) async {
      final std = AppControl.height(AppUserMode.child, AppDensity.compact);
      expect(std, 48);
      expect(
          await _measure(tester, ShadInput(key: _k, placeholder: const Text('x')),
              mode: AppUserMode.child),
          std, reason: 'ShadInput child');
      expect(
          await _measure(tester,
              ShadButton(key: _k, onPressed: () {}, child: const Text('按钮')),
              mode: AppUserMode.child),
          std, reason: 'ShadButton child');
      expect(
          await _measure(tester,
              ShadButton.ghost(key: _k, onPressed: () {}, child: const Text('按钮')),
              mode: AppUserMode.child),
          std, reason: 'ShadButton.ghost child');
    });

    testWidgets('parent / normal 随密度放大一档', (tester) async {
      final std = AppControl.height(AppUserMode.parent, AppDensity.normal);
      expect(std, 48);
      expect(
          await _measure(tester, ShadInput(key: _k, placeholder: const Text('x')),
              density: AppDensity.normal),
          std, reason: 'ShadInput parent/normal');
      expect(
          await _measure(tester,
              ShadButton(key: _k, onPressed: () {}, child: const Text('按钮')),
              density: AppDensity.normal),
          std, reason: 'ShadButton parent/normal');
    });

    testWidgets('紧凑档与主行动档同样严格落在令牌上', (tester) async {
      final sm = AppControl.heightSm(AppUserMode.parent, AppDensity.compact);
      final lg = AppControl.heightLg(AppUserMode.parent, AppDensity.compact);
      expect(
          await _measure(tester,
              ShadButton(
                  key: _k,
                  size: ShadButtonSize.sm,
                  onPressed: () {},
                  child: const Text('按钮'))),
          sm, reason: 'ShadButton.sm');
      expect(
          await _measure(tester,
              ShadButton(
                  key: _k,
                  size: ShadButtonSize.lg,
                  onPressed: () {},
                  child: const Text('按钮'))),
          lg, reason: 'ShadButton.lg');
    });
  });
}
