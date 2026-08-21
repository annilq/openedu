import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../theme/app_theme.dart';

/// 轻提示（Overlay 实现，纯 Cupertino，替代 Material SnackBar）。
///
/// 使用 [AppToast.show] / [AppToast.error] 在任意 context 弹出，自动消退。
/// floating 圆角扁平化，与设计系统一致。
class AppToast {
  AppToast._();

  static final Map<bool, Color> _bgByError = {
    false: const Color(0xFF2F2A24), // 暖炭
    true: const Color(0xFFE56B54), // 温柔珊瑚
  };

  /// 普通提示（暖炭）。
  static void show(BuildContext context, String message) {
    _show(context, message, isError: false);
  }

  /// 错误提示（温柔珊瑚）。
  static void error(BuildContext context, String message) {
    _show(context, message, isError: true);
  }

  static void _show(
    BuildContext context,
    String message, {
    required bool isError,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastHost(
        message: message,
        color: _bgByError[isError]!,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _ToastHost extends StatefulWidget {
  final String message;
  final Color color;
  final VoidCallback onDone;

  const _ToastHost({
    required this.message,
    required this.color,
    required this.onDone,
  });

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<double> _slide;
  Timer? _dismiss;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 0.25, end: 0).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOut),
    );
    _c.forward();
    _dismiss = Timer(const Duration(milliseconds: 2400), () {
      _c.reverse().whenComplete(_onCompleted);
    });
  }

  void _onCompleted() {
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final app = AppTheme.colorsOf(context);
    return Positioned(
      left: 24,
      right: 24,
      bottom: 24 + media.padding.bottom,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(_slide),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                widget.message,
                style: AppTheme.textOf(context).bodyMedium?.copyWith(
                      color: app.surfaceContainerLowest,
                      height: 1.3,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}