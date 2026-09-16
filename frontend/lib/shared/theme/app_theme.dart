import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:shadcn_ui/shadcn_ui.dart';

/// 按正确率分级的视觉情绪。
enum ResultTone { positive, warm, alert, neutral }

/// 应用主题模式。
enum AppThemeMode { system, light, dark }

Brightness resolveBrightness(AppThemeMode mode, Brightness systemBrightness) {
  return switch (mode) {
    AppThemeMode.system => systemBrightness,
    AppThemeMode.light => Brightness.light,
    AppThemeMode.dark => Brightness.dark,
  };
}

ThemeMode appThemeModeToMaterial(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };

/// 用户模式（双模式，ADR-0014）：家长工作台 / 娃娃学习台。
///
/// 独立于亮暗主题（[AppThemeMode]），控制字号阶梯与语气。
/// 家长端 = 密排专业；娃娃端 = 更大字号 + 学科色 + 适度趣味。
enum AppUserMode { parent, child }

/// 学科色（ADR-0014 Subject Accent Tokens）。
///
/// 在中性 + 靛蓝基底上叠加，中饱和，**仅小面积使用**（学科标识 / 进度条 /
/// 图标容器 / 小面积 chip）。`reserved` 为未来学科（科学 / 历史…）预留槽。
enum SubjectKey { math, chinese, english, reserved }

/// 学科色三件套：强调色 / 容器底 / 前景文字。
class SubjectColors {
  final Color accent;
  final Color container;
  final Color fg;
  const SubjectColors(this.accent, this.container, this.fg);
}

/// 学科色令牌解析（亮 / 暗各一套，与 [AppColors] 同源管理）。
class SubjectAccent {
  const SubjectAccent._();

  // 学科三件套（ADR-0044 三重编码：色相 + 明度差 + [SubjectMark] 几何标记）。
  // 色值变更说明：英语由绿改黄——旧绿与语文红在红绿色盲下趋同，且绿 vs 黄在
  // 纸底上的明度差（3.78 vs 1.38）不足以区分。fg 在 container 上实测
  // 5.39 ~ 6.43，全部过 AA；accent 在纸底上最低 1.38（英语黄）→ 必须带墨黑描边。
  static const SubjectColors _lightMath =
      SubjectColors(Color(0xFF2F6FD0), Color(0xFFDCE7FA), Color(0xFF1D4E9C));
  static const SubjectColors _lightChinese =
      SubjectColors(Color(0xFFFF6B5A), Color(0xFFFFE2DE), Color(0xFFB02A18));
  static const SubjectColors _lightEnglish =
      SubjectColors(Color(0xFFFFD43B), Color(0xFFFFF4CC), Color(0xFF7A5A00));
  static const SubjectColors _lightReserved =
      SubjectColors(Color(0xFF8A8F98), Color(0xFFF1F1F0), Color(0xFF5C6068));

  static const SubjectColors _darkMath =
      SubjectColors(Color(0xFF6C9BF0), Color(0xFF16233D), Color(0xFFB3C9F7));
  static const SubjectColors _darkChinese =
      SubjectColors(Color(0xFFFF8C7A), Color(0xFF3A1F1C), Color(0xFFFFC0B4));
  static const SubjectColors _darkEnglish =
      SubjectColors(Color(0xFFFFD43B), Color(0xFF3A3218), Color(0xFFFFE89A));
  static const SubjectColors _darkReserved =
      SubjectColors(Color(0xFF9CA3AF), Color(0xFF2A2A28), Color(0xFFC7CBD1));

  /// 按学科 + 亮暗解析三件套。
  static SubjectColors resolve(SubjectKey key, {required bool isDark}) {
    switch (key) {
      case SubjectKey.math:
        return isDark ? _darkMath : _lightMath;
      case SubjectKey.chinese:
        return isDark ? _darkChinese : _lightChinese;
      case SubjectKey.english:
        return isDark ? _darkEnglish : _lightEnglish;
      case SubjectKey.reserved:
        return isDark ? _darkReserved : _lightReserved;
    }
  }

  /// 按当前 context 的亮暗解析。
  static SubjectColors forContext(SubjectKey key, BuildContext context) =>
      resolve(key, isDark: AppTheme.isDarkOf(context));

  /// 学科中文名。
  static String label(SubjectKey key) => switch (key) {
        SubjectKey.math => '数学',
        SubjectKey.chinese => '语文',
        SubjectKey.english => '英语',
        SubjectKey.reserved => '其它',
      };

  /// 由领域字符串（如 '数学' / 'math'）映射到学科键，未知归 reserved。
  static SubjectKey fromName(String? name) {
    switch (name?.trim()) {
      case '数学':
      case 'math':
      case 'Math':
        return SubjectKey.math;
      case '语文':
      case 'chinese':
      case 'Chinese':
        return SubjectKey.chinese;
      case '英语':
      case 'english':
      case 'English':
        return SubjectKey.english;
      default:
        return SubjectKey.reserved;
    }
  }
}

// =====================================================================
// §新粗野原色与物理令牌（ADR-0044 · 完整色板与原则见 .impeccable.md）
//
// ADR-0004「设计约束 D」的 Linear 克制风（1px 极细描边 / 无阴影 / 中饱和
// 学科色仅小面积）**已被 ADR-0044 取代**：现为纸底 + 墨黑 2px 描边 + 无模糊
// 硬阴影 + 高饱和撞色。
// =====================================================================

/// 学科几何标记（ADR-0044 学科三重编码的形状层）。
///
/// 学科标识必须同时携带「色相 + 明度差 + 形状」三层信息，**禁止仅靠颜色区分**：
/// 语文（coral）与英语（yellow）同属暖色系，在红绿色盲下趋同，由形状兜底。
enum SubjectMark { square, circle, triangle }

/// 学科 → 几何标记映射（唯一事实源，UI 层不得自行 switch 学科）。
extension SubjectMarkOf on SubjectKey {
  SubjectMark get mark => switch (this) {
        SubjectKey.math => SubjectMark.square,
        SubjectKey.chinese => SubjectMark.circle,
        SubjectKey.english => SubjectMark.triangle,
        SubjectKey.reserved => SubjectMark.square,
      };
}

/// 学科几何标记图标（实心，自绘）。
///
/// 自绘而非用图标字体：lucide 的 square/circle/triangle 是**描边**图标，
/// 在 9-12px 尺寸下描边糊成一团，形状辨识度反而不如实心块。
class SubjectMarkIcon extends StatelessWidget {
  final SubjectMark mark;
  final double size;
  final Color color;

  const SubjectMarkIcon({
    super.key,
    required this.mark,
    this.size = 10,
    this.color = AppBrutal.ink,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _SubjectMarkPainter(mark: mark, color: color),
      );
}

class _SubjectMarkPainter extends CustomPainter {
  final SubjectMark mark;
  final Color color;
  const _SubjectMarkPainter({required this.mark, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    switch (mark) {
      case SubjectMark.square:
        canvas.drawRect(Offset.zero & size, paint);
      case SubjectMark.circle:
        canvas.drawCircle(size.center(Offset.zero), size.width / 2, paint);
      case SubjectMark.triangle:
        canvas.drawPath(
          Path()
            ..moveTo(size.width / 2, 0)
            ..lineTo(size.width, size.height)
            ..lineTo(0, size.height)
            ..close(),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_SubjectMarkPainter oldDelegate) =>
      oldDelegate.mark != mark || oldDelegate.color != color;
}

/// 新粗野撞色原色（ADR-0044）。
///
/// **一个色只有一种合规文字配对**，全部实测 WCAG AA：亮块配墨黑、深块配白。
/// **禁止互换**——所有高饱和色配白字对比度最高仅 4.78，过不了 4.5:1
///（`.impeccable.md` §Design Principles 3）。取色一律走 [AppBrutal.onColor]，
/// 不得在业务代码里硬写黑/白。
class AppBrutal {
  const AppBrutal._();

  /// 墨黑：承担全部描边与文字。非纯黑，避免与纸底产生刺眼反差。
  static const Color ink = Color(0xFF111110);

  /// 纸底：页面底色，微暖白。
  static const Color paper = Color(0xFFFDFBF7);

  /// 浮起纸面（卡片 / 浮层底）。
  static const Color paperRaised = Color(0xFFFFFFFF);

  // —— 亮块：只能配 [ink]（实测 4.83 ~ 13.25）——
  static const Color yellow = Color(0xFFFFD43B); // 13.25
  static const Color lime = Color(0xFFA9E34B); // 12.39
  static const Color cyan = Color(0xFF22B8CF); //  7.94
  static const Color teal = Color(0xFF12B886); //  7.40
  static const Color orange = Color(0xFFF08C00); //  7.61
  static const Color coral = Color(0xFFFF6B5A); //  6.75
  static const Color magenta = Color(0xFFE64980); //  5.06
  static const Color green = Color(0xFF2B9348); //  4.83

  // —— 深块：只能配 [onDark]（配 ink 仅 3.40 ~ 3.87，不达标）——
  static const Color violet = Color(0xFF7048E8); //  5.55 vs 白
  static const Color red = Color(0xFFC92525); //  5.56 vs 白
  static const Color blue = Color(0xFF2F6FD0); //  4.88 vs 白

  /// 深块专用前景（纯白）。
  static const Color onDark = Color(0xFFFFFFFF);

  /// 深块登记表。**新增撞色若属深块必须同步登记**，否则 [onColor] 会误判为
  /// 亮块而配墨黑字 → 对比度不达标。
  ///
  /// 不用 `const Set<Color>`：常量集合要求元素具备原始相等性，而 `Color`
  /// 重写了 `==` / `hashCode`，编译器会报 `const_set_element_not_primitive_equality`。
  static bool isDarkFill(Color fill) =>
      fill == violet || fill == red || fill == blue;

  /// 取该色的**唯一合规前景**：亮块 → [ink]，深块 → [onDark]。
  static Color onColor(Color fill) => isDarkFill(fill) ? onDark : ink;
}

/// 描边与硬阴影令牌（ADR-0044）。
///
/// **硬阴影 = 无模糊（`blurRadius = 0`）的纯色偏移**。禁止带 blurRadius 的
/// `BoxShadow`——模糊会破坏新粗野的硬边语言。Flutter 无内阴影 API，黏土式
/// 内阴影不在本方案内（ADR-0044 Considered Options ②）。
///
/// 描边不是装饰：相邻高饱和色块对比度中位数仅 1.67（最低 `violet/red = 1.00`），
/// 无描边时色块边界在视觉上不存在。
class AppElevation {
  const AppElevation._();

  /// 主描边宽度（卡片 / 控件 / 分隔线）。
  static const double borderWidth = 2;

  /// 次级描边宽度（密集表格 / 列表内分隔）。
  static const double borderWidthSm = 1.5;

  /// 发丝描边宽度（结构 chrome 边 / 区域分隔线 / 密集列表逐行卡片）。
  ///
  /// 三档口径（勿再写裸数字——仓里原先散着 6 处字面量 `1`，正是它们让
  /// `separatorTheme` 的注释「与卡片边框同档」和值 `1` 互相矛盾）：
  /// - [borderWidth] (2)：内容物体——卡片 / 弹窗 / 浮层 / 强调件。
  /// - [borderWidthSm] (1.5)：密集列表内的小色块——chip / 学科标记 / 题号。
  /// - [borderWidthHairline] (1)：结构边与重复出现的安静元素——顶栏底边、
  ///   侧栏右缘、底部导航上缘、区域分隔线、[AppCard.listRow]。
  static const double borderWidthHairline = 1;

  /// 常态硬阴影偏移。
  static const Offset offset = Offset(3, 3);

  /// 按压态偏移：元素下沉 2px，模拟物理按压。
  static const Offset offsetPressed = Offset(1, 1);

  /// 常态硬阴影（`blurRadius` 恒为 0）。
  static List<BoxShadow> hard([Color color = AppBrutal.ink]) =>
      <BoxShadow>[BoxShadow(color: color, offset: offset, blurRadius: 0)];

  /// 按压态硬阴影：位移收拢，元素「按下去了」。
  static List<BoxShadow> hardPressed([Color color = AppBrutal.ink]) =>
      <BoxShadow>[
        BoxShadow(color: color, offset: offsetPressed, blurRadius: 0),
      ];

  /// 无阴影（纸底内嵌元素 / 纯分隔线场景）。
  static const List<BoxShadow> none = <BoxShadow>[];
}

/// 物理弹簧令牌（ADR-0044）。
///
/// **取代 `Curves.easeOutBack`**：后者是三次贝塞尔近似，所有元素共用同一条曲线，
/// 多元素同时动时会「齐步走」，没有质量差异、显得廉价。这里按元素量级给不同
/// stiffness / damping——大卡片重、chip 轻（`.impeccable.md` §Design Principles 5）。
///
/// 括号内为阻尼比 `dampingRatio = damping / (2·√(mass·stiffness))`。
class AppSprings {
  const AppSprings._();

  /// 交互态（按压 / hover）：快、几乎无超调（≈0.88）。
  static const SpringDescription interaction =
      SpringDescription(mass: 1, stiffness: 620, damping: 44);

  /// 状态切换（展开 / 收起）：轻微超调（≈0.73）。
  static const SpringDescription state =
      SpringDescription(mass: 1, stiffness: 420, damping: 30);

  /// 页面进入（≈0.75）。
  static const SpringDescription page =
      SpringDescription(mass: 1, stiffness: 300, damping: 26);

  /// 庆祝反馈：明显回弹（≈0.47），仅 Child Mode。
  static const SpringDescription celebrate =
      SpringDescription(mass: 1, stiffness: 260, damping: 15);
}

/// 主题装配（亮色 + 暗色 · 纸底 + 墨黑描边 + 撞色强调，ADR-0044）。
///
/// 设计约定（见 .impeccable.md / ADR-0044）：
/// - surface 纸底 `#FDFBF7`、卡片纯白 + 2px 墨黑描边 + 无模糊硬阴影
/// - 撞色只作强调件（≤ 卡片 40%、单屏色相 ≤ 3），不铺底
/// - 语义色降饱和容器底 + 对应前景（fg 在容器上实测 ≥ 5.3:1）
/// - Inter 西文/数字 + Noto Sans SC（OFL）CJK 回退
/// - 密排字号 15sp 基线，Child Mode 放大一档（ADR-0014）
class AppTheme {
  const AppTheme._();

  /// Inter 为西文/数字主字体；CJK 回退到打包进工程的 Noto Sans SC
  ///（SIL OFL 变量字体，含字重轴，assets/fonts/NotoSansSC.ttf，pubspec.yaml 已声明）。
  /// 设计规范原列 HarmonyOS Sans SC，但其授权限制再分发，故改用可自由内嵌的 Noto Sans SC。
  static const String fontFamily = 'Inter';
  static const List<String> fontFamilyFallback = [
    'Noto Sans SC',
  ];

  /// 亮色令牌（新粗野：纸底 + 墨黑描边 + 高饱和撞色，ADR-0044）。
  ///
  /// 取值全部对齐 [AppBrutal]；语义容器的 fg 在容器底上实测 ≥ 5.3:1。
  /// **outline 已从浅灰改为墨黑**——这是本次视觉语言切换的核心开关。
  static const AppColors light = AppColors(
    brightness: Brightness.light,
    // CTA / 品牌主色：新粗野蓝（深块，配白字 4.88）
    primary: Color(0xFF2F6FD0),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCE7FA), // 浅蓝容器（头像底 / 选中底）
    onPrimaryContainer: Color(0xFF1D4E9C),
    // warning 语义（琥珀，亮块配墨黑）
    secondary: Color(0xFFF08C00),
    onSecondary: AppBrutal.ink,
    secondaryContainer: Color(0xFFFFF0CC), // = semanticWarning 底
    onSecondaryContainer: Color(0xFF6B4700), // = semanticWarningFg
    // positive 语义（绿，亮块配墨黑）
    tertiary: Color(0xFF2B9348),
    onTertiary: AppBrutal.ink,
    tertiaryContainer: Color(0xFFDFF3E4), // = semanticPositive 底
    onTertiaryContainer: Color(0xFF1D6B33), // = semanticPositiveFg
    // error 语义（深红，配白字 5.56）
    error: Color(0xFFC92525),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFE2E0), // = semanticError 底
    onErrorContainer: Color(0xFFA51C1C), // = semanticErrorFg
    // Surface 层次（纸底体系：[AppBrutal.paper] → 纯白浮起）
    surface: AppBrutal.paper, // 内容区纸底
    onSurface: AppBrutal.ink,
    surfaceContainerLowest: Color(0xFFFFFFFF), // = surfaceRaised
    surfaceContainerLow: Color(0xFFFFFFFF), // = surfaceRaised（卡片）
    surfaceContainer: Color(0xFFF2F0EA), // = surfaceSunken（侧栏）
    surfaceContainerHigh: Color(0xFFF2F0EA), // = surfaceSunken（仅作 surface 色调，禁止当边框用）
    surfaceContainerHighest: Color(0xFFE8E5DC), // = surfaceActive
    onSurfaceVariant: Color(0xFF5C6068),
    outline: AppBrutal.ink, // 墨黑描边（ADR-0044：功能必需，非装饰）
    inverseSurface: AppBrutal.ink,
    onInverseSurface: AppBrutal.paper,
    // 强调 + hover
    accent: Color(0xFF2F6FD0),
    onAccent: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFF2F0EA),
    outlineHover: AppBrutal.ink,
    // info 语义（蓝系）
    infoContainer: Color(0xFFDCE7FA), // = semanticInfo 底（AI 标记亦走此档）
    onInfoContainer: Color(0xFF1D4E9C), // = semanticInfoFg
    // CTA hover（蓝 CTA：hover 加深一档）
    ctaHover: Color(0xFF245AB0),
    // Toast 浮层：墨黑底 + 纸色字（新粗野反色，不用中性深炭）
    toast: AppBrutal.ink,
    onToast: AppBrutal.paper,
    scrim: Color(0x66000000),
  );

  /// 暗色令牌（深炭纸 + 亮描边，ADR-0044）。
  ///
  /// 暗色**不是优先目标**（`.impeccable.md` §Aesthetic Direction）：儿童端在暗底上
  /// 撞色会失控。`outline` 取亮暖灰而非纯白——纯白描边在密集列表里会糊成一片，
  /// 此值待暗色专项打磨时再定。
  static const AppColors dark = AppColors(
    brightness: Brightness.dark,
    primary: Color(0xFF7FA8F0), // 暗底品牌蓝（亮块，配深炭字）
    onPrimary: Color(0xFF141412),
    primaryContainer: Color(0xFF16233D), // 深蓝容器（选中/头像底）
    onPrimaryContainer: Color(0xFFB3C9F7), // 浅蓝（容器前景）
    secondary: Color(0xFFFFC94D), // warning 琥珀
    onSecondary: Color(0xFF141412),
    secondaryContainer: Color(0xFF3A3218), // = semanticWarning 底
    onSecondaryContainer: Color(0xFFFFE89A), // = semanticWarningFg
    tertiary: Color(0xFF6FC48A), // positive
    onTertiary: Color(0xFF141412),
    tertiaryContainer: Color(0xFF16301F), // = semanticPositive 底
    onTertiaryContainer: Color(0xFFA7E0BE), // = semanticPositiveFg
    error: Color(0xFFFF8C7A),
    onError: Color(0xFF141412),
    errorContainer: Color(0xFF3A1F1C), // = semanticError 底
    onErrorContainer: Color(0xFFFFC0B4), // = semanticErrorFg
    surface: Color(0xFF141412), // 内容区深炭
    onSurface: Color(0xFFF5F3EE),
    surfaceContainerLowest: Color(0xFF1C1C1A), // = surfaceRaised
    surfaceContainerLow: Color(0xFF1C1C1A), // = surfaceRaised（卡片）
    surfaceContainer: Color(0xFF1A1A18), // = surfaceSunken（侧栏）
    surfaceContainerHigh: Color(0xFF1A1A18), // = surfaceSunken（仅作 surface 色调，禁止当边框用）
    surfaceContainerHighest: Color(0xFF2A2A28), // = surfaceActive
    onSurfaceVariant: Color(0xFFA8A49B),
    outline: Color(0xFF8A8780), // 暗模式亮描边：保证色块边界仍可辨
    inverseSurface: Color(0xFFF5F3EE),
    onInverseSurface: Color(0xFF141412),
    accent: Color(0xFF7FA8F0),
    onAccent: Color(0xFF141412),
    surfaceHover: Color(0xFF232320),
    outlineHover: Color(0xFFA8A49B),
    infoContainer: Color(0xFF16233D), // = semanticInfo 底（AI 标记亦走此档）
    onInfoContainer: Color(0xFFB3C9F7), // = semanticInfoFg
    ctaHover: Color(0xFFFFFFFF),
    toast: Color(0xFFF5F3EE), // 暗模式下 Toast 反色为浅底
    onToast: Color(0xFF141412),
    scrim: Color(0x66000000),
  );

  static bool isDarkOf(BuildContext context) {
    return CupertinoTheme.brightnessOf(context) == Brightness.dark;
  }

  static AppColors colorsOf(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return isDark ? dark : light;
  }

  static final AppText _lightText = AppText._build(light, child: false);
  static final AppText _darkText = AppText._build(dark, child: false);
  static final AppText _lightTextChild = AppText._build(light, child: true);
  static final AppText _darkTextChild = AppText._build(dark, child: true);

  /// 取当前用户模式的排版集合。
  ///
  /// 默认从 [UserModeScope] 读取（由 [userModeProvider] 驱动，全局自动重建）；
  /// 也可显式传 [mode] 覆盖（如测试或部分布局固定用家长尺度）。
  static AppText textOf(BuildContext context, {AppUserMode? mode}) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final m = mode ?? UserModeScope.of(context);
    if (isDark) {
      return m == AppUserMode.child ? _darkTextChild : _darkText;
    }
    return m == AppUserMode.child ? _lightTextChild : _lightText;
  }

  // ============ Cupertino 主题 ============

  static CupertinoThemeData get cupertinoLight => _cupertino(light);
  static CupertinoThemeData get cupertinoDark => _cupertino(dark);

  static CupertinoThemeData cupertinoFor(bool isDark) =>
      _cupertino(isDark ? dark : light);

  /// [density] 为全局控件密度（默认 [AppDensity.compact]，即 parent 32 / child 40）。
  /// 密度与亮暗、用户模式正交：三者共同决定 shadcn 组件主题里的控件高度，
  /// 使裸 `ShadButton` / `ShadInput` 与 `App*` 组件严格同高。
  static ShadThemeData shadFor(
    bool isDark, [
    AppUserMode mode = AppUserMode.parent,
    AppDensity density = AppDensity.compact,
  ]) =>
      shadThemeData(
        isDark ? dark : light,
        child: mode == AppUserMode.child,
        density: density,
      );

  static CupertinoThemeData _cupertino(AppColors c) {
    return CupertinoThemeData(
      brightness: c.brightness,
      primaryColor: c.accent,
      primaryContrastingColor: c.onAccent,
      barBackgroundColor: c.surface,
      scaffoldBackgroundColor: c.surface,
      textTheme: CupertinoTextThemeData(
        primaryColor: c.accent,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          color: c.onSurface,
        ),
      ),
    );
  }

  // ============ Shad Theme ============

  /// 设计系统令牌 → shadcn `custom` 色表。
  ///
  /// 命名以 `.impeccable.md` 的 public 令牌名为准（语义名优先），
  /// 旧的角色名 key（primaryContainer / secondaryContainer / tertiaryContainer /
  /// infoContainer…）一并保留做兼容，**新代码只用语义名**。
  static Map<String, Color> _customColors(AppColors c) {
    final isDark = c.brightness == Brightness.dark;
    final Map<String, Color> subject = {};
    for (final key in SubjectKey.values) {
      final sc = SubjectAccent.resolve(key, isDark: isDark);
      final name = switch (key) {
        SubjectKey.math => 'math',
        SubjectKey.chinese => 'chinese',
        SubjectKey.english => 'english',
        SubjectKey.reserved => 'reserved',
      };
      subject['subject${name[0].toUpperCase()}${name.substring(1)}'] =
          sc.accent;
      subject['subject${name[0].toUpperCase()}${name.substring(1)}Container'] =
          sc.container;
      subject['subject${name[0].toUpperCase()}${name.substring(1)}Fg'] = sc.fg;
    }
    return <String, Color>{
      // —— 新粗野撞色原色（ADR-0044）——
      // 经 `ShadColorScheme.custom['brutalXxx']` 取用；取**文字色**必须走
      // `AppBrutal.onColor(fill)`，不得在这里另配 on* 键，否则会出现第二套配对
      // 事实源。
      'brutalInk': AppBrutal.ink,
      'brutalPaper': AppBrutal.paper,
      'brutalPaperRaised': AppBrutal.paperRaised,
      'brutalYellow': AppBrutal.yellow,
      'brutalLime': AppBrutal.lime,
      'brutalCyan': AppBrutal.cyan,
      'brutalTeal': AppBrutal.teal,
      'brutalOrange': AppBrutal.orange,
      'brutalCoral': AppBrutal.coral,
      'brutalMagenta': AppBrutal.magenta,
      'brutalGreen': AppBrutal.green,
      'brutalViolet': AppBrutal.violet,
      'brutalRed': AppBrutal.red,
      'brutalBlue': AppBrutal.blue,
      // —— 强调（注意：ShadColorScheme.accent 是 shadcn 的 hover 高亮灰，
      //    不是设计系统 accent；品牌蓝在这里，另见 ring / selection）——
      'accent': c.accent,
      'onAccent': c.onAccent,
      'cta': c.cta,
      'onCta': c.onCta,
      'ctaHover': c.ctaHover,
      // —— Surface 层次 ——
      'surfaceRaised': c.surfaceRaised,
      'surfaceSunken': c.surfaceSunken,
      'surfaceActive': c.surfaceActive,
      'surfaceHover': c.surfaceHover,
      'outlineHover': c.outlineHover,
      // —— 语义色（文档 public 令牌名）——
      'semanticPositive': c.semanticPositive,
      'semanticPositiveFg': c.semanticPositiveFg,
      'semanticWarning': c.semanticWarning,
      'semanticWarningFg': c.semanticWarningFg,
      'semanticError': c.semanticError,
      'semanticErrorFg': c.semanticErrorFg,
      'semanticInfo': c.semanticInfo,
      'semanticInfoFg': c.semanticInfoFg,
      // —— 浮层 ——
      'toast': c.toast,
      'onToast': c.onToast,
      'scrim': c.scrim,
      // —— 学科色（ADR-0014）——
      ...subject,
      // —— 旧角色名（兼容，新代码勿用）——
      'infoContainer': c.infoContainer,
      'onInfoContainer': c.onInfoContainer,
      'primaryContainer': c.primaryContainer,
      'onPrimaryContainer': c.onPrimaryContainer,
      'secondaryContainer': c.secondaryContainer,
      'onSecondaryContainer': c.onSecondaryContainer,
      'tertiaryContainer': c.tertiaryContainer,
      'onTertiaryContainer': c.onTertiaryContainer,
      'errorContainer': c.errorContainer,
      'onErrorContainer': c.onErrorContainer,
      'surfaceContainerLowest': c.surfaceContainerLowest,
      'surfaceContainer': c.surfaceContainer,
      'surfaceContainerHigh': c.surfaceContainerHigh,
      'surfaceContainerHighest': c.surfaceContainerHighest,
    };
  }

  /// 卡片 / 浮层 / 弹层通用装饰：纸面底 + 墨黑描边 + 无模糊硬阴影（ADR-0044）。
  ///
  /// 原为「1px 描边 + 无阴影」，现改为 `AppElevation.borderWidth` + 硬阴影：
  /// 相邻撞色块对比度中位数仅 1.67，描边是边界可辨的**功能前提**。
  /// 暗模式下墨黑阴影不可见（阴影色与描边同色），故退化为无阴影。
  /// 浮层硬阴影（浮动表面统一口径：卡片 / 弹窗 / 下拉面板 / popover）。
  ///
  /// 暗色模式返回 [AppElevation.none]：硬阴影是墨黑实色，投在深底上不可见，
  /// 留着只会让浮层显脏。暗色下浮层靠描边 + 提亮底表达层级。
  static List<BoxShadow> _floatingShadows(AppColors c) =>
      c.brightness == Brightness.dark
          ? AppElevation.none
          : AppElevation.hard(c.outline);

  static ShadDecoration _surfaceDecoration(AppColors c, {double? radius}) =>
      ShadDecoration(
        color: c.surfaceRaised,
        border: ShadBorder.all(
          color: c.outline,
          width: AppElevation.borderWidth,
          radius: BorderRadius.all(Radius.circular(radius ?? AppRadius.card)),
        ),
        shadows: _floatingShadows(c),
      );

  static ShadThemeData shadThemeData(
    AppColors c, {
    required bool child,
    AppDensity density = AppDensity.compact,
  }) {
    // 交互控件（按钮 / 输入框 / 选择器）统一高度：主题层无 context，
    // 按「当前用户模式 × 全局密度」推导，与 AppControl.heightOf(context) 同源。
    // 密度由 [densityProvider] 驱动（默认 compact → parent 32 / child 40）。
    final mode = child ? AppUserMode.child : AppUserMode.parent;
    final controlH = AppControl.height(mode, density);
    final controlSmH = AppControl.heightSm(mode, density);
    final controlLgH = AppControl.heightLg(mode, density);

    // 按钮尺寸主题。**必须先分清「可见高」与「内容盒高」**：
    // `ShadButton.height` 是内容盒高，有描边的变体在盒外另占 2×描边宽。
    // 所以「有描边」与「无描边」两族必须给不同的内容盒高，否则同屏的实心按钮
    // 会比 ghost 按钮高出 4px——登录页「登录」与「没有账号？注册」两个按钮上下
    // 相叠，4px 差肉眼可辨（实测 40 vs 36）。
    ShadButtonSizesTheme buttonSizes({required bool bordered}) {
      double box(double visible) =>
          bordered ? AppControl.buttonContentHeight(visible) : visible;
      return ShadButtonSizesTheme(
        regular: ShadButtonSizeTheme(
          height: box(controlH),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        sm: ShadButtonSizeTheme(
          height: box(controlSmH),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        lg: ShadButtonSizeTheme(
          height: box(controlLgH),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        icon: ShadButtonSizeTheme(
          height: box(controlH),
          width: box(controlH),
          padding: EdgeInsets.zero,
        ),
      );
    }

    final scheme = ShadColorScheme(
      background: c.surface,
      foreground: c.onSurface,
      card: c.surfaceRaised,
      cardForeground: c.onSurface,
      popover: c.surfaceRaised,
      popoverForeground: c.onSurface,
      primary: c.primary,
      primaryForeground: c.onPrimary,
      secondary: c.surfaceSunken,
      secondaryForeground: c.onSurface,
      muted: c.surfaceContainer,
      mutedForeground: c.onSurfaceVariant,
      // 陷阱提示：shadcn 的 `accent` 是「hover 高亮」语义（=我们的 surfaceSunken），
      // **不是**设计系统 accent 靛蓝。靛蓝走 `ring` / `selection` / custom['accent']。
      accent: c.surfaceSunken,
      accentForeground: c.onSurface,
      destructive: c.error,
      destructiveForeground: c.onError,
      border: c.outline,
      input: c.outline, // 描边只有一个令牌：outline（边框与分隔线同档）
      ring: c.accent,
      selection: c.accent,
      custom: _customColors(c),
    );

    const transparent = Color(0x00000000);

    // 「零几何」按钮装饰：四边显式 width 0（不绘制）、内距零，但保留圆角。
    //
    // 给 ghost / link 用。它们的「无边界」是设计意图，但不能不设 decoration——
    // 不设时会继承 shadcn 主题默认装饰的 `padding: 2`，凭空多出 4px（实测
    // height:40 → 44），与同屏的实心按钮错落。也不该改成「补一圈透明描边」：
    // 那会平白加 4px 宽，把顶栏里显式 `width: 40` 的图标按钮撑成 44 挤出槽位。
    //
    // 四边必须显式写出来（`ShadBorder.all(width: 0)`）而不能只写 padding/radius：
    // 变体默认装饰的描边侧在 merge 时会保留，`link` 变体正因此仍多出 4px。
    final zeroGeometryDecoration = ShadDecoration(
      border: ShadBorder.all(
        width: 0,
        padding: EdgeInsets.zero,
        radius: const BorderRadius.all(Radius.circular(AppRadius.button)),
      ),
    );

    // 暗模式下墨黑硬阴影与描边同色、不可见，退化为无阴影（ADR-0044）。
    final hardShadows =
        c.brightness == Brightness.dark ? AppElevation.none : AppElevation.hard();

    // hover / press 分级（文档：hover surface 变色、press 再深一档）。
    // 实心按钮（CTA / destructive）底已是近黑或饱和色，hover 提亮/加深一档，
    // 绝不是「无反馈」——此前 hover=bg 等于把 hover 令牌废掉。
    //
    // 新粗野化：实心 CTA 加 2px 墨黑描边 + 硬阴影，从纸面「浮起来」；
    // 原为 `width: 0` 无描边，撞色块在纸底上边界不可辨（相邻色块对比中位数 1.67）。
    ShadButtonTheme button(Color bg, Color fg, {Color? hover}) => ShadButtonTheme(
          backgroundColor: bg,
          foregroundColor: fg,
          hoverBackgroundColor: hover ?? bg,
          pressedBackgroundColor: hover ?? bg,
          pressedForegroundColor: fg,
          decoration: ShadDecoration(
            border: ShadBorder.all(
              color: AppBrutal.ink,
              width: AppElevation.borderWidth,
              // 必须显式写零内距：`ShadBorder.all` 省略 padding 时会继承主题默认
              // 装饰的 `EdgeInsets.all(2)`，在内容盒外再悄悄撑高 4px（实测 32 → 40）。
              // 描边本身就画在盒外那圈，留不留这 4px 都不影响观感（按钮水平 padding
              // ≥8px，内容不会压到描边），但会让所有高度算式凭空多出 4px。
              padding: EdgeInsets.zero,
              radius: BorderRadius.all(Radius.circular(AppRadius.button)),
            ),
            shadows: hardShadows,
          ),
        );

    ShadBadgeTheme badge(Color bg, Color fg) => ShadBadgeTheme(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
            // 徽标一律描边（与学科 chip / AppTags 同口径）。secondary 档用的是
            // surfaceSunken，在卡面上对比仅 ~1.09:1，不描边等于没有边界。
            side: BorderSide(
              color: c.outline,
              width: AppElevation.borderWidthSm,
            ),
          ),
        );

    return ShadThemeData(
      brightness: c.brightness,
      colorScheme: scheme,
      radius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
      textTheme: _shadTextTheme(c, child: child),
      disabledOpacity: 0.5,
      // 按钮尺寸走 AppControl 令牌：与输入框 / 选择器同高。
      // 水平 padding 各减 2px，正好抵消新粗野 2px 描边带来的宽度增量：
      // 旧 = padding×2 + border 0（实心）/1（描边）；新 = (padding-2)×2 + border 2。
      // 实心按钮总宽需求**完全不变**，描边按钮反而窄 2px——这样加粗描边不会
      // 把任何「宽度刚好卡住」的按钮挤到 RenderFlex overflow（真机已踩过一次）。
      buttonSizesTheme: buttonSizes(bordered: true),
      primaryButtonTheme: button(c.cta, c.onCta, hover: c.ctaHover),
      secondaryButtonTheme: ShadButtonTheme(
        backgroundColor: c.surfaceSunken,
        foregroundColor: c.onSurface,
        hoverBackgroundColor: c.surfaceHover,
        pressedBackgroundColor: c.surfaceActive,
        pressedForegroundColor: c.onSurface,
        // 次级按钮：描边加粗到 2px 但**不加**硬阴影——与浮起的 CTA 拉开层级，
        // 避免家长端表单里一排按钮全部浮起造成视觉噪声。
        decoration: ShadDecoration(
          border: ShadBorder.all(
            color: c.outline,
            width: AppElevation.borderWidth,
            padding: EdgeInsets.zero,
            radius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
        ),
      ),
      destructiveButtonTheme: button(c.error, c.onError),
      outlineButtonTheme: ShadButtonTheme(
        backgroundColor: transparent,
        foregroundColor: c.onSurface,
        hoverBackgroundColor: c.surfaceHover,
        pressedBackgroundColor: c.surfaceActive,
        decoration: ShadDecoration(
          border: ShadBorder.all(
            color: c.outline,
            width: AppElevation.borderWidth,
            padding: EdgeInsets.zero,
            radius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
        ),
      ),
      // ghost / link 无描边 → 可见高 == 内容盒高，因此换一套尺寸（用 bordered 族
      // 的 -4 折算会让它们比同屏的实心按钮矮 2×描边宽），并要求零几何装饰把继承
      // 来的 4px 内距清掉。两者配合，四个变体才真正同高。
      ghostButtonTheme: ShadButtonTheme(
        backgroundColor: transparent,
        foregroundColor: c.onSurface,
        hoverBackgroundColor: c.surfaceHover,
        pressedBackgroundColor: c.surfaceActive,
        sizesTheme: buttonSizes(bordered: false),
        decoration: zeroGeometryDecoration,
      ),
      linkButtonTheme: ShadButtonTheme(
        backgroundColor: transparent,
        foregroundColor: c.accent,
        textDecoration: TextDecoration.underline,
        sizesTheme: buttonSizes(bordered: false),
        decoration: zeroGeometryDecoration,
      ),
      primaryBadgeTheme: badge(c.semanticInfo, c.semanticInfoFg),
      secondaryBadgeTheme: badge(c.surfaceSunken, c.onSurface),
      destructiveBadgeTheme: badge(c.semanticError, c.semanticErrorFg),
      outlineBadgeTheme: ShadBadgeTheme(
        backgroundColor: transparent,
        foregroundColor: c.onSurface,
        shape: RoundedRectangleBorder(
          // 徽标属小色块，与 chip / 学科标记同档（1.5px）。
          side: BorderSide(color: c.outline, width: AppElevation.borderWidthSm),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
      ),
      // 主题层卡片默认值：与 AppCard 组件同口径（2px 墨黑边 + 硬阴影）。
      // 组件侧会显式传 border/shadows 覆盖本项，这里对齐只为「单一事实源」——
      // 任何直接使用裸 ShadCard 的地方不该拿到旧克制风的 1px + 无阴影。
      cardTheme: ShadCardTheme(
        backgroundColor: c.surfaceRaised,
        border:
            ShadBorder.all(color: c.outline, width: AppElevation.borderWidth),
        radius: const BorderRadius.all(Radius.circular(AppRadius.card)),
        padding: const EdgeInsets.all(AppSpacing.md),
        shadows: _floatingShadows(c),
      ),
      progressTheme: ShadProgressTheme(
        backgroundColor: c.surfaceActive,
        color: c.accent,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xs)),
        minHeight: 6,
      ),
      inputTheme: ShadInputTheme(
        // 竖向 padding 归零：高度由 tight 约束钉死，文字靠 crossAxisAlignment 居中。
        // 若这里给竖向 padding，ConstrainedBox 只会把「内容高」顶到约束之外，
        // 输入框又比按钮高出一截（32 → 34）。
        padding: AppControl.inputPadding,
        crossAxisAlignment: CrossAxisAlignment.center,
        alignment: Alignment.centerLeft,
        placeholderAlignment: Alignment.centerLeft,
        // 与按钮同高（单行至少 32）：用 minHeight 而非 tight——
        // tight 会把多行输入/带竖向 padding 的输入死钉 32，导致多行内容溢出、
        // 单行文字顶对齐不居中。minHeight 让多行按内容增高、单行仍落在 32。
        // 注意：单行文字垂直居中需在具体输入上用 editableTextSize 钉高（见 AppTextField）。
        constraints: BoxConstraints(minHeight: controlH),
        decoration: ShadDecoration(
          disableSecondaryBorder: true,
          color: c.surfaceRaised,
          border: ShadBorder.all(
            color: c.outline,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
          focusedBorder: ShadBorder.all(
            color: c.accent,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
        ),
        placeholderStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          fontSize: 15,
          color: c.onSurfaceVariant,
        ),
        cursorColor: c.accent,
      ),
      // 统一交互主色（A）：开关/勾选/单选选中态走靛蓝 accent，
      // 与 focus ring / selection / progress 同色；primary 现亦为靛蓝，
      // CTA 与全站品牌色（状态色/图标/光标）统一为蓝紫。
      switchTheme: ShadSwitchTheme(
        checkedTrackColor: c.accent,
        uncheckedTrackColor: c.surfaceSunken,
        thumbColor: c.onAccent,
      ),
      checkboxTheme: ShadCheckboxTheme(
        color: c.accent,
        uncheckedColor: c.outline,
      ),
      radioTheme: ShadRadioTheme(color: c.accent),
      // —— 浮层 / 弹层 / 表单接管 ——
      // 不接管这些主题时，shadcn 会退回内置 slate 配色 + 阴影，
      // 与「描边分层、无阴影、走令牌」的设计系统脱节（同一页面两套管语言）。
      // 接管后 Popover / Dialog / Select / Toast / Alert 与 AppCard 同构。
      // 无半透明 focus ring：focus 用 1px accent（各输入类组件已显式配
      // focusedBorder）表达。注意不要在全局 `decoration` 上挂 border——
      // 它会漏到 switch / checkbox 等无框控件上，凭空长出描边。
      disableSecondaryBorder: true,
      popoverTheme: ShadPopoverTheme(
        // ⚠️ 这条内边距（连同 decoration 的 2px 描边）是包在浮层**内容之外**的，
        // 属于 [AppLayout.popoverChrome]。想让某个浮层的外框等于某个宽度，
        // 内容侧必须减去这份开销，别按内容宽直接写数字。
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: _surfaceDecoration(c, radius: AppRadius.card),
        // 原为 const <BoxShadow>[]，把 decoration 里刚算好的硬阴影又抹掉了——
        // 浮层于是只剩描边，与输入框处在同一视觉平面，读不出「浮在页面之上」。
        shadows: _floatingShadows(c),
      ),
      primaryDialogTheme: _dialogTheme(c),
      alertDialogTheme: _dialogTheme(c),
      selectTheme: ShadSelectTheme(
        decoration: ShadDecoration(
          disableSecondaryBorder: true,
          color: c.surfaceRaised,
          border: ShadBorder.all(
            color: c.outline,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
          focusedBorder: ShadBorder.all(
            color: c.accent,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
        ),
        padding: AppControl.inputPadding,
        optionsPadding: const EdgeInsets.all(AppSpacing.xs),
        // 下拉面板浮在页面之上，必须投硬阴影才能与触发器分层。这个 shadows 会
        // 原样传给内部的 ShadPopover（= 面板本体），与 popoverTheme 同口径；
        // 触发器自身的 1px 描边不动（输入类控件与 inputStrut 的高度折算耦合）。
        shadows: _floatingShadows(c),
      ),
      optionTheme: ShadOptionTheme(
        backgroundColor: c.surfaceRaised,
        hoveredBackgroundColor: c.surfaceHover,
        selectedBackgroundColor: c.surfaceActive,
        selectedIconColor: c.accent,
        radius: BorderRadius.all(Radius.circular(AppRadius.chip)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      primaryToastTheme: _toastTheme(c),
      destructiveToastTheme: _toastTheme(c),
      primaryAlertTheme: _alertTheme(c),
      destructiveAlertTheme: _alertTheme(c),
      textareaTheme: ShadTextareaTheme(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // 多行控件至少两行高，但底边与单行控件同圆角同描边。
        constraints: BoxConstraints(minHeight: controlH * 2),
        decoration: ShadDecoration(
          disableSecondaryBorder: true,
          color: c.surfaceRaised,
          border: ShadBorder.all(
            color: c.outline,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
          focusedBorder: ShadBorder.all(
            color: c.accent,
            width: 1,
            radius: BorderRadius.all(Radius.circular(AppRadius.input)),
          ),
        ),
      ),
      // 区域分隔线走发丝档：卡片是「物体」用 2px，分隔线是重复出现的安静元素，
      // 与 AppCard.listRow 同档。（原注释写「与卡片边框同档」但值是 1，是卡片边宽
      // 从 1 提到 2 时漏改注释留下的自相矛盾。）
      separatorTheme: ShadSeparatorTheme(
        color: c.outline,
        thickness: AppElevation.borderWidthHairline,
      ),
      // 文档：tooltip 延迟 500ms、tooltip 属交互态（120ms 淡入）。
      tooltipTheme: ShadTooltipTheme(
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: ShadDecoration(
          color: c.inverseSurface,
          border: ShadBorder.all(
            color: c.inverseSurface,
            width: 0,
            radius: BorderRadius.all(Radius.circular(AppRadius.chip)),
          ),
          shadows: const <BoxShadow>[],
        ),
      ),
    );
  }

  static ShadDialogTheme _dialogTheme(AppColors c) => ShadDialogTheme(
        backgroundColor: c.surfaceRaised,
        radius: BorderRadius.all(Radius.circular(AppRadius.card)),
        // 弹窗是遮罩之上的独立物体，描边与阴影须与卡片同档（2px + 硬阴影）。
        // 原为 1px + 无阴影，是旧克制风的残留——在新语言里弹窗会「陷」进页面。
        border: Border.all(color: c.outline, width: AppElevation.borderWidth),
        padding: const EdgeInsets.all(AppSpacing.lg),
        gap: AppSpacing.md,
        shadows: _floatingShadows(c),
      );

  static ShadToastTheme _toastTheme(AppColors c) => ShadToastTheme(
        backgroundColor: c.toast,
        border: ShadBorder.all(color: c.toast, width: 0),
        radius: BorderRadius.all(Radius.circular(AppRadius.bubble)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shadows: const <BoxShadow>[],
      );

  static ShadAlertTheme _alertTheme(AppColors c) => ShadAlertTheme(
        decoration: _surfaceDecoration(c),
        iconSize: 16,
        iconPadding: const EdgeInsets.only(right: AppSpacing.sm),
      );

  /// 排版 → ShadTextTheme。复用 [AppText._typeScale] 单一事实源（设计系统约束 D），
  /// Child Mode 在 Parent 基础上整体放大一档（ADR-0014）。
  static ShadTextTheme _shadTextTheme(AppColors c, {required bool child}) {
    double grow(double s) => child ? _childScale(s) : s;

    TextStyle style(String k, {Color? color}) {
      final (size, weight, height, spacing) = AppText._typeScale[k]!;
      return TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: grow(size),
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? c.onSurface,
      );
    }

    return ShadTextTheme(
      family: fontFamily,
      h1Large: style('displayLarge'),
      h1: style('displayMedium'),
      h2: style('headlineLarge'),
      h3: style('headlineMedium'),
      h4: style('headlineSmall'),
      p: style('bodyLarge'),
      blockquote: style('bodyLarge', color: c.onSurfaceVariant),
      table: style('labelMedium'),
      list: style('bodyLarge'),
      lead: style('headlineMedium'),
      large: style('titleLarge'),
      small: style('labelSmall'),
      muted: style('bodySmall', color: c.onSurfaceVariant),
    );
  }
}

// =====================================================================
// §语义色令牌集合
// =====================================================================

class AppColors {
  final Brightness brightness;

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;

  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;

  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  final Color surface;
  final Color onSurface;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurfaceVariant;
  final Color outline;

  final Color inverseSurface;
  final Color onInverseSurface;

  // 靛蓝强调 + hover + info 语义
  final Color accent;
  final Color onAccent;
  final Color surfaceHover;
  final Color outlineHover;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color ctaHover; // CTA（近黑/反色）按钮的 hover 底色
  final Color toast; // Toast 浮层底
  final Color onToast; // Toast 浮层文字
  final Color scrim; // 模态遮罩（抽屉/弹层）：固定半透明黑，避免运行时 withValues 伪造

  const AppColors({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurfaceVariant,
    required this.outline,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.accent,
    required this.onAccent,
    required this.surfaceHover,
    required this.outlineHover,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.ctaHover,
    required this.toast,
    required this.onToast,
    required this.scrim,
  });

  /// 浮起表面（卡片/容器背景）。
  Color get surfaceRaised => surfaceContainerLow;

  /// 下沉表面（侧栏/凹槽/弱化背景）。
  Color get surfaceSunken => surfaceContainerHigh;

  /// 选中态表面。
  Color get surfaceActive => surfaceContainerHighest;

  // ============ 语义色别名（文档 @.impeccable.md 的 public 令牌名） ============
  //
  // 底层存储沿用 shadcn / Material 角色名（primary/secondary/tertiary…），
  // 但**业务代码一律只用本段语义别名**，与文档令牌名一一对应，杜绝
  // 「用 secondaryContainer 表达 warning」这类角色名错读（CONTEXT.md 已把
  // primaryContainer/secondaryContainer/tertiaryContainer 列为 Avoid 词）。

  /// 正向（positive）容器底 / 前景。
  Color get semanticPositive => tertiaryContainer;

  Color get semanticPositiveFg => onTertiaryContainer;

  /// 警告（warning）容器底 / 前景。
  Color get semanticWarning => secondaryContainer;

  Color get semanticWarningFg => onSecondaryContainer;

  /// 错误（error）容器底 / 前景。
  Color get semanticError => errorContainer;

  Color get semanticErrorFg => onErrorContainer;

  /// 信息（info）容器底 / 前景。
  Color get semanticInfo => infoContainer;

  Color get semanticInfoFg => onInfoContainer;

  /// CTA 按钮底 / 文字（文档 `cta` / `onCta`）。
  Color get cta => primary;

  Color get onCta => onPrimary;
}

// =====================================================================
// §排版令牌（密排 15sp 基线）
// =====================================================================

/// Child Mode 字号放大映射（ADR-0014 Dual-Mode Type Scale）。
/// [AppText] 与 [AppTheme._shadTextTheme] 共用，消除双排版表漂移。
double _childScale(double s) {
  if (s == 22) return 26;
  if (s == 20) return 24;
  if (s == 18) return 21;
  if (s == 17) return 19;
  if (s == 16) return 18;
  if (s == 15) return 17;
  if (s == 14) return 16;
  if (s == 13) return 14;
  if (s == 12) return 13;
  return s + 2;
}

class AppText {
  final TextStyle? displayLarge;
  final TextStyle? displayMedium;
  final TextStyle? headlineLarge;
  final TextStyle? headlineMedium;
  final TextStyle? headlineSmall;
  final TextStyle? titleLarge;
  final TextStyle? titleMedium;
  final TextStyle? titleSmall;
  final TextStyle? bodyLarge;
  final TextStyle? bodyMedium;
  final TextStyle? bodySmall;
  final TextStyle? labelLarge;
  final TextStyle? labelMedium;
  final TextStyle? labelSmall;

  const AppText({
    required this.displayLarge,
    required this.displayMedium,
    required this.headlineLarge,
    required this.headlineMedium,
    required this.headlineSmall,
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
  });

  /// 单一字号事实源（双模式共用）。[AppText] 与 [_shadTextTheme] 均从此取数，
  /// 杜绝两套并行排版表漂移（设计系统约束 D）。
  static const Map<String, (double size, FontWeight weight, double height,
      double spacing)> _typeScale = {
    'displayLarge': (22, FontWeight.w700, 1.2, -0.6),
    'displayMedium': (20, FontWeight.w700, 1.2, -0.4),
    'headlineLarge': (18, FontWeight.w600, 1.25, -0.3),
    'headlineMedium': (17, FontWeight.w600, 1.3, -0.2),
    'headlineSmall': (16, FontWeight.w600, 1.3, -0.1),
    'titleLarge': (16, FontWeight.w600, 1.35, -0.1),
    'titleMedium': (15, FontWeight.w600, 1.35, 0),
    'titleSmall': (15, FontWeight.w600, 1.35, 0),
    'bodyLarge': (15, FontWeight.w400, 1.5, 0),
    'bodyMedium': (14, FontWeight.w400, 1.45, 0),
    'bodySmall': (13, FontWeight.w400, 1.45, 0.2),
    'labelLarge': (14, FontWeight.w600, 1.35, 0.2),
    'labelMedium': (13, FontWeight.w600, 1.35, 0.3),
    'labelSmall': (12, FontWeight.w500, 1.35, 0.3),
  };

  factory AppText._build(AppColors c, {required bool child}) {
    const ff = AppTheme.fontFamily;
    const ffb = AppTheme.fontFamilyFallback;
    final base = c.onSurface;
    final muted = c.onSurfaceVariant;
    final onCta = c.onPrimary;

    // Child Mode 字号映射（与 Dual-Mode Type Scale 表一致，复用 _childScale）。
    double cs(double s) => child ? _childScale(s) : s;

    // 每令牌前景色覆盖（其余默认 base）。
    Color? colorOf(String k) => switch (k) {
          'labelLarge' => onCta,
          'bodySmall' || 'labelSmall' => muted,
          _ => base,
        };
    // Child Mode 正文行高微调（低龄可读性）。
    double heightOf(String k, double h) => (child && k == 'bodyLarge') ? 1.55 : h;

    TextStyle mk(String k) {
      final (size, weight, height, spacing) = _typeScale[k]!;
      return TextStyle(
        fontFamily: ff,
        fontFamilyFallback: ffb,
        fontSize: cs(size),
        fontWeight: weight,
        height: heightOf(k, height),
        letterSpacing: spacing,
        color: colorOf(k),
      );
    }

    return AppText(
      displayLarge: mk('displayLarge'),
      displayMedium: mk('displayMedium'),
      headlineLarge: mk('headlineLarge'),
      headlineMedium: mk('headlineMedium'),
      headlineSmall: mk('headlineSmall'),
      titleLarge: mk('titleLarge'),
      titleMedium: mk('titleMedium'),
      titleSmall: mk('titleSmall'),
      bodyLarge: mk('bodyLarge'),
      bodyMedium: mk('bodyMedium'),
      bodySmall: mk('bodySmall'),
      labelLarge: mk('labelLarge'),
      labelMedium: mk('labelMedium'),
      labelSmall: mk('labelSmall'),
    );
  }
}

// =====================================================================
// §通用组件
// =====================================================================

/// 卡片：2px 墨黑描边 + 硬阴影（新粗野），可点击时按下整卡位移、阴影收拢。
///
/// 卡片强度变体（ADR-0044「列表降噪」）。
/// - [standard]：2px 墨黑描边 + 硬阴影，用于独立卡片 / 强调件。
/// - [listRow]：1px 墨黑描边 + 无阴影，用于密集列表的逐行卡片——避免每行
///   都压 2px 边 + 硬阴影导致家长端看板视觉过载（「统一到家长端上限」的代价补偿）。
///
/// ⚠️ **卡片比内容高时，内容会贴顶、不会垂直居中**：底层 [ShadCard] 内部固定是
/// `Row(crossAxisAlignment: start)` → `Column(mainAxisSize: min)`，内容只按自身高度
/// 收缩并朝上沿对齐。内容自撑高度时（绝大多数用法）两者相等、看不出问题；一旦外面用
/// `SizedBox(height:)` 把卡片钉高（如侧栏头部触发器），差值就变成底部一段空白。
/// 调用点需自己包一层 `Center`——不要指望这里居中，改这里会动到全站每张卡片的布局。
enum AppCardVariant { standard, listRow }

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double? radius;
  final Border? border;
  final VoidCallback? onTap;
  final AppCardVariant variant;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = const EdgeInsets.symmetric(vertical: 4),
    this.color,
    this.radius,
    this.border,
    this.onTap,
    this.variant = AppCardVariant.standard,
  });

  /// 密集列表逐行卡片：1px 墨黑边、无阴影。
  const AppCard.listRow({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = const EdgeInsets.symmetric(vertical: 4),
    this.color,
    this.radius,
    this.border,
    this.onTap,
  }) : variant = AppCardVariant.listRow;

  static ShadBorder _convertBorder(Border b) {
    ShadBorderSide side(BorderSide s) => ShadBorderSide(
          color: s.color,
          width: s.width,
          style: s.style,
        );
    return ShadBorder(
      top: side(b.top),
      right: side(b.right),
      bottom: side(b.bottom),
      left: side(b.left),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    // 暗模式下墨黑硬阴影与描边同色、不可见 → 退化为无阴影（ADR-0044）。
    List<BoxShadow> shadowsFor(bool pressed) => app.brightness == Brightness.dark
        ? AppElevation.none
        : (pressed
            ? AppElevation.hardPressed(app.outline)
            : AppElevation.hard(app.outline));

    // 列表行变体：发丝边、无阴影；标准变体：2px 边 + 硬阴影。
    final isRow = variant == AppCardVariant.listRow;
    final borderWidth =
        isRow ? AppElevation.borderWidthHairline : AppElevation.borderWidth;
    final rowShadows = AppElevation.none;

    ShadCard buildCard(Color borderColor, List<BoxShadow> shadows) => ShadCard(
          padding: padding,
          backgroundColor: color ?? app.surfaceContainerLow,
          radius: BorderRadius.circular(radius ?? AppRadius.card),
          border: border != null
              ? _convertBorder(border!)
              : ShadBorder.all(color: borderColor, width: borderWidth),
          shadows: shadows,
          child: child,
        );
    // NOTE: Do NOT wrap `buildCard(...)` in `ShadButton.ghost(width: double.infinity)`.
    // That injects a `BoxConstraints(minWidth: ∞, maxWidth: ∞)` into the card,
    // which shadcn's internal `ShadCard` structure
    // (`Row(mainAxisSize: min) → Flexible → Column → Flexible → child`) then
    // passes down as UNBOUNDED width. Any `Expanded`/`Flexible` inside the
    // card content (e.g. the task-list card's `Row(Expanded)`) then throws
    // "RenderFlex children have non-zero flex but incoming width constraints
    // are unbounded". A bare `GestureDetector` is pass-through: it imposes no
    // width constraint, so the card receives the parent's bounded width and
    // still fills it via its own `Expanded` content. `GestureDetector` needs
    // no `Material` ancestor, so it is safe under `ShadApp`.
    if (onTap == null) {
      return Container(
          margin: margin,
          child: buildCard(app.outline, isRow ? rowShadows : shadowsFor(false)));
    }
    // 可点击卡片：hover 时边框微深到 outlineHover，让"可点"有真实反馈；
    // 按下时整卡下沉 + 阴影收拢（新粗野的「按压」语义，ADR-0044）。
    // (hover, pressed) 打包进同一个 notifier，避免两层 ValueListenableBuilder。
    final state = ValueNotifier<(bool, bool)>((false, false));
    return Container(
      margin: margin,
      child: ValueListenableBuilder<(bool, bool)>(
        valueListenable: state,
        builder: (_, s, __) {
          final (h, p) = s;
          return MouseRegion(
            cursor: SystemMouseCursors.basic,
            onEnter: (_) => state.value = (true, state.value.$2),
            onExit: (_) => state.value = (false, state.value.$2),
            // 走 AppFocusableAction（而非裸 GestureDetector）：卡片是全站最主要的可点
            // 区域，裸 GestureDetector 不在焦点树里 → 桌面端 Tab 得到菜单却打不开任何东西
            // （ADR-0045）。它全程不注入宽高约束，因此不会踩上面 ShadButton.ghost 那个
            // 「无界宽度」的坑；键盘 Enter/Space 也会走同一 onTap。
            child: AppFocusableAction(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius ?? AppRadius.card),
              onPressedChanged: (pressed) =>
                  state.value = (state.value.$1, pressed),
              // 只动 transform（GPU 合成），不触发布局重排。
              child: Transform.translate(
                offset: p ? AppElevation.offsetPressed : Offset.zero,
              child: buildCard(h ? app.outlineHover : app.outline,
                  isRow ? rowShadows : shadowsFor(p)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 键盘可达的即时点击区（ADR-0045）。
///
/// **背景**：本仓的可点区域（导航项 / 列表行 / 卡片）一律用裸 [GestureDetector] +
/// `MouseRegion` 实现（应用根是 `ShadApp`、无 Material 祖先，因此刻意不用 `InkWell`）。
/// 但裸 [GestureDetector] **不进焦点树**——Tab 跳不过去、Enter/Space 也点不动，桌面端
/// 因此完全没有键盘可达性；`flutter analyze` 也照不出这类问题（它不是类型错误）。
///
/// 本组件补齐三件事：
/// 1. 进入焦点树（[FocusableActionDetector] + `Shortcuts`/`Actions`）；
/// 2. `Enter` / `Space` / 小键盘回车激活——与鼠标点击走**同一个** [onTap]；
/// 3. 焦点可见：聚焦时叠一圈 2px 焦点环（不使用系统默认高亮）。
///
/// 用 `foregroundDecoration` 而非 `decoration` 画焦点环：前者覆盖绘制、**不参与布局**，
/// 因此聚焦 / 失焦不会让元素尺寸跳动（描边加粗导致行高变化的经典坑）。
///
/// 焦点环取 [AppColors.accent]（靛蓝）而非墨黑：本仓的墨黑描边到处都是（卡片、列表行、
/// 每组色块的边），用墨黑画焦点环会退化成「边框好像变粗了」，读不出「焦点在这里」。
///
/// **约束**：本组件全程不注入任何宽高约束（`FocusableActionDetector` / `Semantics` /
/// `GestureDetector` / `MouseRegion` / `DecoratedBox` 都是透传的 proxy），因此可以安全地
/// 包住 [AppCard]——那张卡对「外层塞进无界宽度」极其敏感（见上方 `ShadButton.ghost`
/// 的 NOTE）。
///
/// [onTap] 为空或 [enabled] 为 false 时不进焦点树——不可操作的项不该被 Tab 到。
class AppFocusableAction extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// 按压态变化（按下 → true，抬起 / 取消 → false）。
  ///
  /// 用于驱动「整卡下沉」「硬阴影收拢」这类按压反馈：键盘 [ActivateIntent] 也会
  /// 走一次 true→false，使键盘激活与鼠标点击有同样的视觉反馈。
  final ValueChanged<bool>? onPressedChanged;

  /// 焦点环圆角；缺省跟随 chip 档（与导航药丸一致）。
  final BorderRadius? borderRadius;

  final bool enabled;

  /// 供读屏使用的动作名（如「首页」）。
  final String? semanticLabel;

  /// 悬停时是否垫一层药丸底色（缺省否）。
  ///
  /// 只画底色，**不改布局**（与焦点环同思路）。底部绘制，故选中的子项自带底色时
  /// 会盖住它——「选中」与「悬停」因而天然分层：悬停是浅的 `surfaceHover`，选中是
  /// 深的 `surfaceActive`，同一元素上二者可区分。
  ///
  /// 侧栏导航项 / 收缩按钮 / 下拉菜单项这类「无文字撑宽、只有图标或短标签」的可点
  /// 区域都应打开；否则鼠标移上去没有任何反馈（触屏看不出来，桌面端很明显）。
  final bool hoverHighlight;

  const AppFocusableAction({
    super.key,
    required this.child,
    this.onTap,
    this.onPressedChanged,
    this.borderRadius,
    this.enabled = true,
    this.semanticLabel,
    this.hoverHighlight = false,
  });

  @override
  State<AppFocusableAction> createState() => _AppFocusableActionState();
}

class _AppFocusableActionState extends State<AppFocusableAction> {
  bool _focused = false;
  bool _hovered = false;

  bool get _actionable => widget.enabled && widget.onTap != null;

  void _activate() {
    // 键盘激活补齐一次按压反馈：鼠标走 onTapDown/Up，键盘两者都没有。
    widget.onPressedChanged?.call(true);
    widget.onPressedChanged?.call(false);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final radius = widget.borderRadius ?? BorderRadius.circular(AppRadius.chip);
    return FocusableActionDetector(
      enabled: _actionable,
      includeFocusSemantics: true,
      onShowFocusHighlight: (v) {
        if (_focused != v) setState(() => _focused = v);
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: _actionable,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:
              _actionable ? (_) => widget.onPressedChanged?.call(true) : null,
          onTapUp: _actionable
              ? (_) => widget.onPressedChanged?.call(false)
              : null,
          onTapCancel:
              _actionable ? () => widget.onPressedChanged?.call(false) : null,
          onTap: _actionable ? _activate : null,
          child: MouseRegion(
            cursor: _actionable
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: widget.hoverHighlight
                ? (_) => setState(() => _hovered = true)
                : null,
            onExit: widget.hoverHighlight
                ? (_) => setState(() => _hovered = false)
                : null,
            child: DecoratedBox(
              // 悬停底色画在**底层**（decoration），子项自带的选中底色会盖住它。
              decoration: BoxDecoration(
                color: _hovered && _actionable
                    ? scheme.surfaceHover
                    : CupertinoColors.transparent,
                borderRadius: radius,
              ),
              // 焦点环画在顶层（foregroundDecoration）：覆盖绘制、不参与布局，
              // 因此聚焦 / 失焦不会让元素尺寸跳动（描边加粗导致行高变化的经典坑）。
              child: Container(
                foregroundDecoration: _focused && _actionable
                    ? BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: scheme.accent,
                          width: AppElevation.borderWidth,
                        ),
                      )
                    : null,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 主操作按钮：品牌靛蓝 CTA（走 accent）。
/// 主行动按钮（品牌蓝 CTA）。
///
/// [height] 是**可见总高**（含 2px 描边），默认走标准档 [AppControl.heightOf]；
/// 单屏唯一的主行动传 [AppControl.heightLgOf]。内部会换算成 shadcn 需要的内容盒
/// 高度——这一点很关键：`ShadButton.height` 并非可见高度，直接透传会让按钮比同行
/// 的输入框高出 2×描边宽。
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool fullWidth;
  final IconData? icon;
  final String? loadingLabel;

  /// 可见总高；null 走标准档。
  final double? height;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.fullWidth = true,
    this.icon,
    this.loadingLabel,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final spinner = Icon(
      LucideIcons.loaderCircle,
      size: 18,
      color: app.onCta,
    ).animate(onPlay: (c) => c.repeat()).rotate(
          begin: 0,
          end: 1,
          duration: const Duration(milliseconds: 900),
          curve: Curves.linear,
        );
    final labelWidget = Text(
      loading ? (loadingLabel ?? label) : label,
      textAlign: TextAlign.center,
      style: AppTheme.textOf(context).labelLarge?.copyWith(
            color: app.onCta,
          ),
    );
    final child = icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              loading ? spinner : Icon(icon, size: 16, color: app.onCta),
              const SizedBox(width: 8),
              labelWidget,
            ],
          )
        : (loading ? spinner : labelWidget);
    return ShadButton(
      // 令牌给的是可见总高，ShadButton 要的是内容盒高 → 减掉 2×描边宽。
      height: AppControl.buttonContentHeight(
        height ?? AppControl.heightOf(context),
      ),
      expands: fullWidth,
      onPressed: loading ? null : onPressed,
      child: child,
    );
  }
}

/// 新粗野实心按钮：撞色填充 + 唯一合规前景 + 2px 墨黑描边 + 硬阴影，
/// 按下时整块下沉（[AppElevation.offsetPressed]）并收拢阴影（ADR-0044）。
///
/// 与 [AppPrimaryButton] 的区别：后者走 shadcn 主题（品牌蓝 CTA），本组件
/// 接受任意 [AppBrutal] 撞色，用于「每屏最多 3 个色相」的强调件。
///
/// 前景色**不**由调用方传——必须走 [AppBrutal.onColor]，否则亮块配白字会
/// 掉到 4.78:1 以下（实测所有高饱和色配白字最高仅 4.78）。
class AppBrutalButton extends StatefulWidget {
  final String label;
  final Color fill;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool fullWidth;

  /// 可见总高；null 走标准档 [AppControl.heightOf]。
  ///
  /// 与 [AppPrimaryButton] 的 `height` 语义**一致**（都是可见总高）：本组件用裸
  /// `Container` + `BoxDecoration(border:)`，Flutter 的描边画在盒内，故传入值
  /// 就是可见高度，无需换算。
  final double? height;

  const AppBrutalButton({
    super.key,
    required this.label,
    required this.fill,
    this.onPressed,
    this.icon,
    this.fullWidth = false,
    this.height,
  });

  @override
  State<AppBrutalButton> createState() => _AppBrutalButtonState();
}

class _AppBrutalButtonState extends State<AppBrutalButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (widget.onPressed == null) return;
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final enabled = widget.onPressed != null;
    final fg = AppBrutal.onColor(widget.fill);
    final content = Row(
      mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 16, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: text.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onPressed,
      child: Opacity(
        // 禁用态沿用全站 disabledOpacity 语义，不新增令牌。
        opacity: enabled ? 1 : 0.5,
        child: Transform.translate(
          // 只动 transform（GPU 合成）；下沉是即时位移而非补间动画，
          // 因此无需按 reduce-motion 关闭（手势与反馈都保留）。
          offset: _pressed ? AppElevation.offsetPressed : Offset.zero,
          child: Container(
            height: widget.height ?? AppControl.heightOf(context),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.fill,
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppRadius.button)),
              border: Border.all(
                color: AppBrutal.ink,
                width: AppElevation.borderWidth,
              ),
              boxShadow: _pressed
                  ? AppElevation.hardPressed()
                  : AppElevation.hard(),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// 行内图标操作：方形命中区 + 居中图标，尺寸走 [AppControl] 标准档。
///
/// 为什么需要它：`CupertinoButton(padding: EdgeInsets.zero, child: Icon(...))`
/// 看着是「纯图标」，实际被 Cupertino 的默认 `minSize` 钉成 **44×44**——与标准档
/// 输入框同行时会把整行撑高 4px，且图标中心与输入框文字中线错位。这是本仓第三种
/// 「控件高度权威」（前两种是 [AppControl] 与 `ShadButton` 的内容盒高，见
/// [AppControl.buttonContentHeight]），必须收口。
///
/// 命中区取标准档而非更小的紧凑档：行高本就由同行的输入框决定，命中区与行高对齐
/// 既不会撑行，也不牺牲可点性（紧凑档 32 在密集表单里偏小）。
///
/// **不是裸 `GestureDetector`**：内层走 [AppFocusableAction]，因此进焦点树、支持
/// Enter / Space 激活、有焦点环与悬停底色。`CupertinoButton` 本来是可聚焦的，
/// 直接换成裸手势会**倒退键盘可达性**（见 ADR-0046）。
class AppIconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  /// 图标视觉尺寸（命中区恒为标准档，与此无关）。
  final double iconSize;
  final Color? color;

  /// 读屏动作名。图标按钮没有文字，**调用点应尽量提供**（如「删除该选项」）。
  final String? semanticLabel;

  const AppIconAction({
    super.key,
    required this.icon,
    this.onPressed,
    this.iconSize = 18,
    this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final hit = AppControl.heightOf(context);
    final tint = onPressed != null
        ? (color ?? app.onSurfaceVariant)
        : app.onSurfaceVariant.withValues(alpha: 0.5);
    return AppFocusableAction(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      hoverHighlight: true,
      child: SizedBox(
        width: hit,
        height: hit,
        child: Center(child: Icon(icon, size: iconSize, color: tint)),
      ),
    );
  }
}

/// 行内文字操作：用于卡片 / 列表行里的「编辑 / 删除 / 设为默认」等二次动作。
///
/// 与 [AppIconAction] 同属「行内操作」家族：方形命中区换成文字标签 + 水平内边距，
/// 其余属性（焦点树 / 悬停药丸 / 键盘 Enter 激活）完全一致。
///
/// 为什么不用 `CupertinoButton`：它会把 child 套进 Cupertino 主题的
/// `DefaultTextStyle`，强制使用系统字体（.SF Pro / PingFang），**覆盖**
/// 我们内嵌的 Inter + Noto Sans SC；中文会变糙、字号也会跳到 Cupertino 默认值。
/// 这里显式给 `Text` 传 `AppTheme.textOf` 样式，保证字形与字号都走设计系统。
class AppTextAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// 文字色。不传时走 `onSurfaceVariant`；删除等破坏动作用 `app.error`。
  final Color? color;

  /// 读屏动作名。文字标签本身可读时通常无需再传。
  final String? semanticLabel;

  const AppTextAction({
    super.key,
    required this.label,
    this.onPressed,
    this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final tint = onPressed != null
        ? (color ?? app.onSurfaceVariant)
        : app.onSurfaceVariant.withValues(alpha: 0.5);
    final child = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        label,
        style: text.labelMedium?.copyWith(color: tint),
      ),
    );
    return AppFocusableAction(
      onTap: onPressed,
      semanticLabel: semanticLabel ?? label,
      hoverHighlight: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: AppControl.heightSmOf(context),
        ),
        child: Center(
          widthFactor: 1,
          child: child,
        ),
      ),
    );
  }
}

/// 线性进度条：靛蓝填充。
class AppProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  const AppProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return ShadProgress(
      value: value.clamp(0.0, 1.0),
      minHeight: height,
      color: color ?? app.accent,
      backgroundColor: trackColor ?? app.surfaceContainerHighest,
    );
  }
}

// =====================================================================
// §语义化组件
// =====================================================================

/// Hover 感知的语义 pill：常态与 hover 态同步切换底色（克制版——同色微深，
/// 不填实饱和色），前景色保持不变，文字始终可读且整体协调。
///
/// 设计背景：shadcn 的 [ShadBadge] 仅支持单一 [foregroundColor]，hover 时
/// 背景切到 [hoverBackgroundColor] 而文字颜色不变；本 App 的 badge 主题未设
/// [hoverBackgroundColor]，导致 hover 背景变透明、文字残留容器前景色而不可读。
/// 这里自管 hover 状态，同时切换底色（同色微深）+ 保持前景，彻底解决「背景变、
/// 字不变、看不清」，且 hover 不再填实饱和色（修复标签成全站最吵元素的问题）。
Color _hoverDeepen(Color bg, Brightness b) => b == Brightness.dark
    ? Color.lerp(bg, const Color(0xFFFFFFFF), 0.10)!
    : Color.lerp(bg, const Color(0xFF000000), 0.08)!;

class _HoverPill extends StatelessWidget {
  final Color bg;
  final Color fg;
  final ShapeBorder shape;
  final EdgeInsetsGeometry padding;
  final double iconSize;
  final double gap;
  final IconData? icon;

  /// 自定义前导件（学科 chip 传几何标记 [SubjectMarkIcon]）。优先于 [icon]。
  final Widget? leading;
  final String label;

  const _HoverPill({
    required this.bg,
    required this.fg,
    required this.shape,
    required this.padding,
    this.iconSize = 13,
    this.gap = 5,
    this.icon,
    this.leading,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final bright = CupertinoTheme.brightnessOf(context) == Brightness.dark
        ? Brightness.dark
        : Brightness.light;
    final hovered = ValueNotifier(false);
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => hovered.value = true,
      onExit: (_) => hovered.value = false,
      child: ValueListenableBuilder<bool>(
        valueListenable: hovered,
        builder: (ctx, h, _) {
          final b = h ? _hoverDeepen(bg, bright) : bg;
          final f = fg;
          return Container(
            decoration: ShapeDecoration(shape: shape, color: b),
            padding: padding,
            child: IconTheme(
              data: IconThemeData(color: f, size: iconSize),
              child: DefaultTextStyle(
                style: (AppTheme.textOf(context).labelSmall ??
                        const TextStyle())
                    .copyWith(color: f, fontWeight: FontWeight.w600),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[
                      leading!,
                      SizedBox(width: gap),
                    ] else if (icon != null) ...[
                      Icon(icon, size: iconSize),
                      SizedBox(width: gap),
                    ],
                    Text(label),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 语义 Chip/Pill：降饱和底色 + 对应前景色。
class AppTags {
  static Widget normal(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon,
        semantics: _TagSemantics.normal,
      );

  static Widget info(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon,
        semantics: _TagSemantics.info,
      );

  static Widget ai(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon ?? LucideIcons.sparkles,
        semantics: _TagSemantics.ai,
      );

  static Widget success(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon ?? LucideIcons.checkCircle2,
        semantics: _TagSemantics.success,
      );

  static Widget warning(String label, {IconData? icon}) => _TagChip(
        label: label,
        icon: icon,
        semantics: _TagSemantics.warning,
      );

  /// 学科标签：用学科色（accent/container/fg）着色，仅小面积使用。
  static Widget subject(SubjectKey key, {String? label, IconData? icon}) =>
      _TagChip(
        label: label ?? SubjectAccent.label(key),
        icon: icon,
        semantics: _TagSemantics.normal,
        subject: key,
      );
}

enum _TagSemantics { normal, info, ai, success, warning }

class _TagChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final _TagSemantics semantics;
  final SubjectKey? subject;
  const _TagChip({
    required this.label,
    this.semantics = _TagSemantics.normal,
    this.icon,
    this.subject,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    late final Color bg;
    late final Color fg;
    Widget? leading;
    ShapeBorder shape;
    if (subject != null) {
      final sc = SubjectAccent.forContext(subject!, context);
      // 学科 chip 属「小面积强调」，允许全填充。前景**必须**由 [AppBrutal.onColor]
      // 判定：数学蓝是深块配白字，语文珊瑚 / 英语黄是亮块配墨黑字——反过来就不过 AA。
      bg = sc.accent;
      fg = AppBrutal.onColor(sc.accent);
      leading = SubjectMarkIcon(mark: subject!.mark, color: fg, size: 9);
      // 英语黄在纸底上仅 1.38:1、语文珊瑚 2.71:1，不描边时 chip 边界不存在。
      shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
        side: const BorderSide(
            color: AppBrutal.ink, width: AppElevation.borderWidthSm),
      );
    } else {
      // 非学科 chip 同样要描边：nearest 底色是 surfaceSunken(#F2F0EA)，在白色卡面上
      // 对比约 1.09:1，不描边则标签边界不存在（与上面学科分支同一个理由，原先只给
      // 学科分支加了边，这里漏了）。
      shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
        side: const BorderSide(
            color: AppBrutal.ink, width: AppElevation.borderWidthSm),
      );
      (bg, fg) = switch (semantics) {
        _TagSemantics.normal => (app.surfaceSunken, app.onSurface),
        _TagSemantics.info => (app.semanticInfo, app.semanticInfoFg),
        // AI 归 info 靛蓝档：不新增与 warning 琥珀重复的色，保持「一色 + 四档语义色」。
        _TagSemantics.ai => (app.semanticInfo, app.semanticInfoFg),
        _TagSemantics.success => (app.semanticPositive, app.semanticPositiveFg),
        // 曾经误用 errorContainer（红）表达 warning——与文档 semanticWarning
        // 琥珀档不符，红/琥珀语义串味。改走语义别名，杜绝再次错读。
        _TagSemantics.warning => (app.semanticWarning, app.semanticWarningFg),
      };
    }

    return _HoverPill(
      bg: bg,
      fg: fg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      shape: shape,
      iconSize: 13,
      gap: 4,
      icon: icon,
      leading: leading,
      label: label,
    );
  }
}

/// 语义 Badge（胶囊）。
class AppBadge {
  static Widget successChip(String label) => _BadgePill(
        label: label,
        icon: LucideIcons.check,
        semantics: _BadgeSemantics.success,
      );

  static Widget warningChip(String label) => _BadgePill(
        label: label,
        icon: LucideIcons.alertTriangle,
        semantics: _BadgeSemantics.warning,
      );

  static Widget infoChip(String label) => _BadgePill(
        label: label,
        icon: LucideIcons.info,
        semantics: _BadgeSemantics.info,
      );
}

enum _BadgeSemantics { success, warning, info }

class _BadgePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final _BadgeSemantics semantics;
  const _BadgePill({
    required this.label,
    required this.icon,
    required this.semantics,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final (bg, fg) = switch (semantics) {
      _BadgeSemantics.success =>
        (app.semanticPositive, app.semanticPositiveFg),
      _BadgeSemantics.warning =>
        (app.semanticWarning, app.semanticWarningFg),
      _BadgeSemantics.info => (app.semanticInfo, app.semanticInfoFg),
    };

    return _HoverPill(
      bg: bg,
      fg: fg,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      shape: const StadiumBorder(),
      iconSize: 12,
      gap: 4,
      icon: icon,
      label: label,
    );
  }
}

/// 章节标题：左侧 4px 墨黑色条 + 标题文字（ADR-0044：色条从 3px 靛蓝改为 4px 墨黑，
/// 与描边语言统一；标题色在撞色环境里承担「锚点」，不再与学科色抢色相）
/// 规范章节节奏（统一间距事实源，ADR 设计系统约束）：
/// - top    = [AppSpacing.sm] (8)：标题上沿留白；相邻 section 靠「上标题 bottom(8)
///   + 下标题 top(8)」叠加成 16px 统一间隔，页面无需再手动加 SizedBox。
/// - bottom = [AppSpacing.sm] (8)：标题 → 内容的统一间隔。
/// - 水平 0：标题左缘与全宽卡片（AppCard）左缘对齐；页面不要再给卡片套
///   `Padding(horizontal: lg)`，否则会与标题错位 ~12px。
/// 所有家长/设置页共用此节奏，确保跨页面 UI 一致。
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding =
        const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.sm),
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final style = AppTheme.textOf(context).titleMedium;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: app.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(child: Text(text, style: style)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Squircle 方圆形头像。
class AvatarSquircle extends StatelessWidget {
  final String name;
  final double size;
  final Color? bg;
  final Color? fg;

  const AvatarSquircle({
    super.key,
    required this.name,
    this.size = 96,
    this.bg,
    this.fg,
  });

  const AvatarSquircle.small({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 40;

  /// 紧凑预设：用于侧栏/顶栏的触发芯片（如切换娃娃按钮），比 [small] 更小。
  const AvatarSquircle.xs({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 28;

  const AvatarSquircle.medium({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 56;

  const AvatarSquircle.large({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 80;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final background = bg ?? app.primaryContainer;
    final foreground = fg ?? app.onPrimaryContainer;
    return ShadAvatar(
      null,
      size: Size.square(size),
      backgroundColor: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(size * 0.32)),
        side: BorderSide.none,
      ),
      placeholder: Text(
        name.isNotEmpty ? name[0] : '?',
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontFamilyFallback: AppTheme.fontFamilyFallback,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// 间距令牌（4 基准模数刻度：xs=4 为步长；密排缩减，非 8 倍网格）
class AppSpacing {
  static const double xs2 = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xl2 = 28;
  static const double xl3 = 32;
  static const double xl4 = 40;
  static const double xl5 = 48;
}

/// 断点与内容宽度令牌（ADR-0045）
///
/// 设计约束（单一事实源）：
/// - 布局决策**只**基于 [LayoutBuilder] 的 `constraints.maxWidth`（父级分配的可用
///   宽度），不得使用 `MediaQuery.orientationOf` / `OrientationBuilder`，也不得按
///   硬件类型（phone / tablet / desktop）分支——Flutter 应用跑在可缩放窗口、多窗口
///   与画中画里，**设备形态不等于可用空间**。
/// - 内容宽度上限的作用是防止大屏下文本行过长、卡片被无限拉宽。约束值按**语义**
///   分档，禁止在页面里再写裸数字（否则「哪一档才是我该用的」无从判断）。
class AppLayout {
  /// 紧凑档上界：`width < compactMax` 走紧凑布局（娃娃端底栏 / 家长端汉堡抽屉）。
  static const double compactMax = 700;

  /// 大屏档下界：`width >= largeMin` 时由页面提供 master-detail 双栏编排。
  static const double largeMin = 1200;

  /// 侧栏展开宽度。
  static const double sidebarExpanded = 240;

  /// 侧栏收起宽度（轨态）。
  static const double sidebarCollapsed = 64;

  /// 最小方形触控目标边长。
  ///
  /// 取 44：Apple HIG 的最小可点尺寸（44pt），也高于 Material 的 48dp 触控目标
  /// 对**图标按钮**的宽松下限。用于侧栏头部按钮 / 紧凑顶栏菜单按钮 / 列表行内的
  /// 行内操作——凡是「只有一个图标、没有文字撑宽」的可点区域，都取这一档，
  /// 不要各自写 40 / 44 / 48。
  static const double tapTarget = 44;

  /// 大号方形触控目标边长（浮动入口，如助手浮球）。
  ///
  /// 取 52：它悬浮在内容**之上**，要比行内图标按钮更大才能从内容里「跳出来」
  /// （52 = 图标 24 + 两侧各 14 呼吸）。同样是「只有一个图标、没有文字撑宽」的
  /// 可点区域，因此也收口到令牌，不写裸数字。
  static const double tapTargetLg = 52;

  /// 侧栏头部（[AdaptiveShell.sidebarTop]）四向内边距。
  ///
  /// 左侧必须等于导航项的左缘（[AppSpacing.sm]）——否则侧栏内会出现「头部贴边、
  /// 导航缩进」的双左缘，视觉上像两个不相干的区块。
  static const EdgeInsets sidebarHeaderPadding = EdgeInsets.fromLTRB(
    AppSpacing.sm,
    AppSpacing.md,
    AppSpacing.sm,
    AppSpacing.xs,
  );

  /// 侧栏菜单（[AdaptiveShell.sidebarTop] 里那个浮层）**外框**宽度。
  ///
  /// 等于侧栏展开宽度减去 [sidebarHeaderPadding] 的左右内边距——菜单外框与头部
  /// 触发卡共用同一条左右边缘，整体落在侧栏内、左右各留 [AppSpacing.sm]。
  ///
  /// 只用在这里，所以直接从 [sidebarExpanded] 推导：侧栏变宽时菜单自动跟随，
  /// 不会出现「侧栏改了、浮层还是老宽度于是又溢出」。
  /// **不要**拿它当通用的浮层宽度——它的值来自「与侧栏等宽」这个具体约束。
  static const double sidebarMenuWidth = sidebarExpanded - 2 * AppSpacing.sm;

  /// 浮层外框相对**内容**多出的固定开销：主题内边距（左右各 [AppSpacing.sm]）
  /// + 新粗野 2px 描边（左右各 [AppElevation.borderWidth]）。
  ///
  /// 存在的理由：shadcn 的 `popoverTheme.padding` 与 `decoration` 的描边都包在
  /// **内容之外**，所以「我要外框 224」必须写成「内容 224 - 开销」。
  /// 这条开销**无法从内容侧推导**，只能显式记账——配套的
  /// `test/sidebar_header_layout_test.dart` 会断言渲染出来的外框宽 ==
  /// [sidebarMenuWidth]，所以改了主题内边距 / 描边宽度会立刻红，而不是静默变宽。
  static const double popoverChrome =
      2 * AppSpacing.sm + 2 * AppElevation.borderWidth;

  /// 侧栏菜单最大高度；超出后菜单内部滚动。
  static const double menuMaxHeight = 400;

  /// master-detail 双栏的宽度配比（主栏 : 详情栏 = 5 : 8）。
  ///
  /// 详情栏更宽：主栏是列表（行文本短），详情栏是要读的题面 / 解析。用配比而非固定
  /// 像素——内容区已被 [contentWide] 钉死，配比在实机宽度区间内变化很小，同时避免
  /// 主栏是表单页时被压成一条窄缝。
  static const int masterFlex = 5;
  static const int detailFlex = 8;

  /// 家长端工作区内容最大宽度（列表 / 仪表盘 / 表单页）。
  static const double contentWide = 1080;

  /// 答题与阅读区内容最大宽度（缩短视线跨度，提升阅读舒适度）。
  static const double contentReading = 820;

  /// 单张结果卡 / 居中卡片的内容最大宽度。
  static const double contentCard = 520;

  /// 对话框表单（如「添加模型」）的最大宽度。
  ///
  /// 比 [contentCard] 略宽：API Key、Base URL 这类长字符串字段在 520 内
  /// 依旧局促，560 给输入框更多横向呼吸空间，同时仍小于 [contentReading]。
  static const double dialogForm = 560;

  /// 登录页与表单对话框等窄栏内容最大宽度。
  static const double contentNarrow = 480;

  /// 空态 / 提示卡内容最大宽度。
  ///
  /// 注意：曾有第六档 `contentFloat = 380`（悬浮助手面板），ADR-0047 把助手改成整页
  /// 后浮层不复存在，该档已删除——留一个没有消费方的档位只会让人猜「什么该用它」。
  static const double contentEmpty = 440;

  // ───────────── 长列表密度（ADR-0053） ─────────────
  //
  // 三个长列表（题库 / 任务 / 错题本）此前各有各的行距与页边距，切换页面时会有
  // 「这个页面更挤」的突兀感。密度收口在这里，页面不许再写裸数字。

  /// 列表区的左右页边距。
  static const double listGutter = AppSpacing.lg;

  /// 行间距。
  ///
  /// 统一 8：行卡自带 1px 墨黑描边，8 足够分隔。此前三个页面是 8 / 12 / 16 三种值。
  static const double listRowGap = AppSpacing.sm;

  /// 列间距（两列之间）。
  ///
  /// 比行间距 [listRowGap] 大一档：行与行之间还有卡片自己的描边分隔，
  /// 列与列之间什么都没有，只能靠间距。
  static const double listColumnGap = AppSpacing.md;

  /// 两列布局中单列的**目标**宽度。
  static const double listColumnWidth = contentCard;

  /// 自动进两列所需的可用内容宽度（已减左右页边距）。
  ///
  /// 取 1048 = [contentWide] 1080 − 2 × [listGutter]，即「大屏、detail 关闭」时
  /// 列表区实际拿到的宽度。此时两列各 (1048 − 12) / 2 = 518，比 [listColumnWidth]
  /// 只差 2px——差 2px 就掉回一列会让家长拉窗口时列表在临界点反复跳列，所以阈值
  /// 取「两列都基本达到目标宽度」而不是「两列都必须 ≥ 520」。
  static const double listTwoColumnMin = contentWide - 2 * listGutter;

  /// 可用内容宽度 [width] 能放几列。**上限 2 列**：3 列会把列宽压到约 340，
  /// 远低于 [contentNarrow] 480 的可读下限，而两列已经能换来「一屏两倍」。
  ///
  /// 只看可用宽度：不由 `MediaQuery.size`（屏宽）、不由方向、不由平台判断
  ///（ADR-0045 的硬约束）。大屏打开 detail 时主栏约 446 → 1 列，符合预期。
  static int listColumnsFor(double width) =>
      width >= listTwoColumnMin ? 2 : 1;
}

/// 圆角令牌（ADR-0044：新粗野小圆角 / 大面直角）
///
/// 设计约束（单一事实源，全站通用组件共用）：
/// - 由旧的 4 / 6 / 8 三档**收敛为 2 / 4 / 0**：新粗野靠硬边与大色块建立体量，
///   不需要靠圆角放大来「维持体量」。
/// - 控件（chip / button / input）与卡片（card）统一 4，保证按钮落在卡片内时
///   角半径一致、视觉内聚。
/// - **大面（banner）取 0**：横幅是最大面积的强调件，直角才能撑住撞色块。
/// - 装饰性大圆角（头像 / 分数环 / 浮层）不在本表约束内，按场景取 28/32/999。
class AppRadius {
  static const double xs = 2; // 标记点 / 极小元素
  static const double sm = 4; // 微缩元素
  static const double chip = 4; // 标签 / 侧栏项
  static const double button = 4; // 按钮
  static const double input = 4; // 输入框
  static const double card = 4; // 卡片容器
  static const double bubble = 4; // 答案气泡 / 浮层小卡
  static const double banner = 0; // 大面横幅（新粗野：直角）
}

/// 控件密度（交互控件紧凑度）。与亮暗（[AppThemeMode]）、用户模式（[AppUserMode]）正交，
/// 用于推导统一的控件高度，使按钮 / 输入框 / 选择器随紧凑度缩放。
///
/// **默认 [compact]**（parent 40 / child 48）。密度已全局接入：由 `densityProvider`
/// 持久化并驱动 `AppTheme.shadFor(isDark, mode, density)`，[DensityScope] 只需在
/// 需要局部偏离的子树上包一层（如数据密集型表格切 [normal]）。
/// 所有控件高度都由该维度推导，无硬编码魔法值。
enum AppDensity { normal, compact }

/// 控件高度令牌（交互控件统一高度，单一事实源）
///
/// 设计约束：输入框、按钮、下拉选择器等同属「交互控件」，必须共用同一高度，避免同行控件
/// 高低不齐。三档高度完全由「用户模式 × 密度」推导，**取值全部落在间距令牌
/// [AppSpacing] 上，无魔法数字**，并随紧凑度 / 双模式自动缩放
/// （呼应 ADR-0014 双模式字号阶梯）。
///
/// ## 一条等距阶梯，锚在触控下限档
///
/// 三档不是三个各自独立拍出来的数，而是**相邻恒差 [step] 的等距阶梯**，锚点是主行动档
/// [heightLg]——它是三档里唯一被**外部规范**约束的一档：Material 的最小触控目标 48dp
/// 与 Apple HIG 的 44pt 都要满足，取 48 即同时达标。标准档与紧凑档由锚点向下推
/// （各减一阶 / 两阶），所以**调档位时只需改锚点**，阶梯不会散架。
///
/// | 档位 | parent·compact | parent·normal | child·compact | child·normal |
/// |---|---|---|---|---|
/// | [heightSm] 紧凑 | 32 | 40 | 40 | 48 |
/// | [height] 标准 | **40** | 48 | 48 | 56 |
/// | [heightLg] 主行动 | 48 | 56 | 56 | 64 |
///
/// 「child 比 parent 大一档」与「normal 比 compact 大一档」是**同一个 +8 位移**，
/// 所以 child·compact 与 parent·normal 数值完全相同——这不是巧合，而是阶梯的必然结果。
///
/// ## 为什么标准档是 40 而不是 32
///
/// 32 是 **Ant Design / Element Plus** 的表单控件默认值，那是**桌面鼠标**工具的惯例
/// （可点区域可以很小）。本项目平板优先、纯触控，32 低于所有触控规范（Material 48dp /
/// HIG 44pt）——旧注释写「平板优先 + 触控目标」却取 32，**理由与取值自相矛盾**，
/// 这才是「输入框看着有点小」的根因。取 40 也正是 Material 3 的按钮标准高度，
/// 位于 HIG 44pt 下一档、阶梯上恰为锚点 −1 阶。
///
/// 38 未采用：它是 Bootstrap 的实现副产物（12px padding×2 + 24px 行高 + 2px 描边），
/// 不对应任何设计原则，也不落在本仓间距令牌的任何一档上，引入即新增魔法数字。
class AppControl {
  /// 全局默认密度（= [AppDensity.compact]，parent 40 / child 48）。
  static const AppDensity defaultDensity = AppDensity.compact;

  /// 相邻档位的高度差（阶梯公差）。
  ///
  /// 独立成常量而**不复用 [AppSpacing.sm]**：间距令牌与控件档差是两件事，
  /// 若共用，日后调整间距会静默改掉全站控件高度。
  static const double step = 8;

  /// 主行动档（单屏唯一的主要 CTA）——**阶梯锚点**，标准档 / 紧凑档由它下推。
  ///
  /// 取 Material 的最小触控目标 48dp（Apple HIG 为 44pt，48 同时满足两者）。
  static double heightLg(AppUserMode mode, AppDensity density) => switch ((mode, density)) {
        (AppUserMode.child, AppDensity.compact) => AppSpacing.xl5 + step, // 56
        (AppUserMode.child, AppDensity.normal) => AppSpacing.xl5 + AppSpacing.lg, // 64
        (AppUserMode.parent, AppDensity.compact) => AppSpacing.xl5, // 48
        (AppUserMode.parent, AppDensity.normal) => AppSpacing.xl5 + step, // 56
      };

  /// 标准档（表单输入框 / 选择器 / 表单内按钮）= 锚点下一阶。
  ///
  /// **同行控件必须同用这一档**。三档都指「可见总高」（含描边），与「传给
  /// `ShadButton` 的 content-box 高」是两个量——换算见 [buttonContentHeight]。
  static double height(AppUserMode mode, AppDensity density) =>
      heightLg(mode, density) - step; // parent 40 / child 48

  /// 紧凑档（表格行内小按钮 / 行内操作）= 锚点下两阶。
  static double heightSm(AppUserMode mode, AppDensity density) =>
      heightLg(mode, density) - 2 * step; // parent 32 / child 40

  /// 从上下文解析当前模式 + 密度（[UserModeScope] / [DensityScope] 未挂载时回退
  /// parent / [AppControl.defaultDensity]）。
  static double heightOf(BuildContext context) =>
      height(UserModeScope.of(context), DensityScope.of(context));

  /// 从上下文解析主行动档高度。
  static double heightLgOf(BuildContext context) =>
      heightLg(UserModeScope.of(context), DensityScope.of(context));

  /// 把「可见高度」换算成 **ShadButton 的 `height` 参数值**（内容盒高度）。
  ///
  /// shadcn 的 `ShadButton.height` 是**内容盒**高度，不是可见高度：描边由
  /// `ShadDecorator` 画在内容盒**之外**，实测「可见高 = 传入值 + 2×描边宽」。
  /// 我们的按钮描边是 [AppElevation.borderWidth]（2px），所以直接传 [heightOf]
  /// 会**高出 4px**；而输入框被 `tightFor` 钉死在 [heightOf]，两者同行必然错落
  /// （实测按钮 40 / 输入框 32）。
  ///
  /// 用算式而非硬编码 `4`：描边宽本身就是令牌，改档时必须同步，算式让它无法漂移。
  ///
  /// **`ghost` / `link` 变体没有描边，不得用本函数**——它们的内容盒高即可见高，
  /// 主题层已单独给它们一套尺寸（见 `shadThemeData` 的 `buttonSizes(bordered:)`）。
  static double buttonContentHeight(double visibleHeight) =>
      visibleHeight - 2 * AppElevation.borderWidth;

  /// 从上下文解析紧凑控件高度。
  static double heightSmOf(BuildContext context) =>
      heightSm(UserModeScope.of(context), DensityScope.of(context));

  /// 输入类控件（ShadInput / ShadSelect / ShadTextarea 外层）的内边距。
  ///
  /// **竖向必须为 0**：高度由 [inputConstraintsOf] 的 tight 约束钉死，竖向 padding 只会
  /// 把内容挤出去；垂直居中靠 `crossAxisAlignment: center`。
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(horizontal: 12);

  /// 输入类控件的盒约束：钉死到 [heightOf]，与按钮严格同高。
  ///
  /// 用 `minHeight` 不够——单行文字行高（15px 字 ≈ 18~20px）+ padding 会把它顶成
  /// 34px，按钮却是 32px，同行又错落。必须用 `tightFor`。
  static BoxConstraints inputConstraintsOf(BuildContext context) =>
      BoxConstraints.tightFor(height: heightOf(context));

  /// 单行输入框文字垂直居中所需的 [StrutStyle]。
  ///
  /// 根因：shadcn 的 `ShadInput` 不暴露 `textAlignVertical`，其内部 `EditableText`
  /// 默认 `textAlignVertical: top`，文字会落在编辑盒**顶端**——盒子比文字行高高出
  /// 多少，文字就偏上多少，因此档位越高偏得越明显。这就是「输入框文字不上下居中」
  /// 的真正原因。
  /// 用 `forceStrutHeight` 把行高强制撑满编辑盒（controlH - 4，扣边框与 shadcn
  /// 内部预留），Flutter 的半行距（half-leading）会把字形上下均分 → 视觉严格居中。
  ///
  /// 仅用于「精确 controlH 高、无额外竖向 padding」的**单行**输入；多行输入本就该
  /// 顶对齐，带大竖向 padding 的输入（如聊天栏）已因盒子高、文字盒短而被居中，勿用。
  static StrutStyle inputStrut(BuildContext context, TextStyle? style) {
    final fontSize = style?.fontSize ?? 16;
    return StrutStyle(
      fontSize: fontSize,
      height: (heightOf(context) - 4) / fontSize,
      forceStrutHeight: true,
    );
  }

  /// 多行输入的最小高度（两行起步）。
  static BoxConstraints textareaConstraintsOf(BuildContext context) =>
      BoxConstraints(minHeight: heightOf(context) * 2);
}

/// 转场时长令牌（三档 + Child Mode 庆祝档，ADR-0014）
class AppMotion {
  /// 交互态：hover / press / focus
  static const Duration interaction = Duration(milliseconds: 120);

  /// 状态切换：展开 / 收起 / 切换
  static const Duration state = Duration(milliseconds: 200);

  /// 页面进入
  static const Duration page = Duration(milliseconds: 300);

  /// 庆祝反馈：徽章解锁 / 连击 +1 / 打卡成功。**仅 Child Mode**（见
  /// [celebrateFor]）；Parent Mode 不触发，避免游戏化。
  static const Duration celebrate = Duration(milliseconds: 450);

  /// 答对题的 scale-pop（Child Mode 微奖励）
  static const Duration pop = interaction;

  /// 庆祝动效按用户模式取值：Child 走 450ms 庆祝档，Parent 退回状态切换档。
  static Duration celebrateFor(AppUserMode mode) =>
      mode == AppUserMode.child ? celebrate : state;
}

/// 转场曲线令牌（与 [AppMotion] 配套，禁止裸写 Curves.*）。
///
/// **本表已降级为「必须是 Curve」的场合专用**：shadcn 内部转场、第三方组件只收
/// `Curve` 的参数、以及 `AnimatedContainer` 这类隐式动画。
///
/// 业务动效（按压、入场、庆祝）一律走 [AppSprings] 物理弹簧（ADR-0044）。
/// `easeOutBack` 是三次贝塞尔近似，所有元素共用同一条曲线 → 多元素同时动时
/// 「齐步走」，没有质量差异；弹簧能按元素量级给不同 stiffness / damping。
///
/// ⚠️ **隐式动画不会自动尊重 reduce-motion**：用本表的 `AnimatedScale` /
/// `AnimatedContainer` 必须显式写 `duration: reduced ? Duration.zero : ...`。
class AppCurves {
  /// 交互态：快出
  static const Curve interaction = Curves.easeOut;

  /// 状态切换：快出
  static const Curve state = Curves.easeOut;

  /// 页面进入：渐进渐出
  static const Curve page = Curves.easeInOut;

  /// 庆祝：回弹（仅 Child Mode）。新代码请用 [AppSprings.celebrate]。
  static const Curve celebrate = Curves.easeOutBack;
}

// =====================================================================
// §用户模式作用域（双模式切换，ADR-0014）
// =====================================================================

/// 将当前 [AppUserMode] 注入 Widget 树。
///
/// [AppTheme.textOf] 通过它读取模式，从而所有 `Text(style: AppTheme.textOf(context)...)`
/// 在模式切换时自动重建——无需逐个 widget 监听 [userModeProvider]。
/// 未挂载时默认 [AppUserMode.parent]，避免脱离作用域调用崩溃。
class UserModeScope extends InheritedWidget {
  final AppUserMode mode;

  const UserModeScope({
    super.key,
    required this.mode,
    required super.child,
  });

  static AppUserMode of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserModeScope>()?.mode ??
      AppUserMode.parent;

  @override
  bool updateShouldNotify(UserModeScope old) => old.mode != mode;
}

/// 控件密度作用域：向子树广播 [AppDensity]，使 [AppControl.heightOf] 随紧凑度推导高度。
///
/// 用法同 [UserModeScope]。全局密度已由 `densityProvider` 驱动（默认
/// [AppDensity.compact]），本 Scope 只用于**局部偏离**（如密集表格切回 [normal]）。
/// 未挂载时回退 [AppControl.defaultDensity]，与主题层保持一致。
class DensityScope extends InheritedWidget {
  final AppDensity density;

  const DensityScope({
    super.key,
    required this.density,
    required super.child,
  });

  static AppDensity of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DensityScope>()?.density ??
      AppControl.defaultDensity;

  @override
  bool updateShouldNotify(DensityScope old) => old.density != density;
}
