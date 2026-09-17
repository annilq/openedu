import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_error.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_pushed_page.dart';
import '../../../shared/widgets/app_toast.dart';
import '../domain/export_repository.dart';
import '../providers/export_provider.dart';

/// 打印导出预览页（ADR-0052）：渲染**将要投递的那份字节**。
///
/// 「预览与导出不一致」在构造上不可能发生——预览组件吃的就是这份 bytes，
/// 打印与分享也复用同一份，本页不产生第二份 PDF。
///
/// 这是 `Navigator.push` 的整页，**不在壳的宽度兜底范围内**（ADR-0045），
/// 宽度还是出路都由 [AppPushedPage] 这一层兜住——见该组件的注释。
class ExportPreviewPage extends ConsumerStatefulWidget {
  const ExportPreviewPage({
    super.key,
    required this.request,
    required this.title,
    this.downgradedCount = 0,
  });

  final ExportSheetRequest request;

  /// 页面标题（文档标题），同时作为分享出的文件名。
  final String title;

  /// 含公式或图片、已按纯文本打印的题数（客户端自算，如实提示）。
  final int downgradedCount;

  @override
  ConsumerState<ExportPreviewPage> createState() => _ExportPreviewPageState();
}

/// 预览是在哪一步失败的。
///
/// 「没拿到字节」和「字节到手但渲染不出来」是两件完全不同的事，
/// 失败文案要给的不是同一句话：前者该重试网络，后者通常与 App 运行方式有关。
enum _PreviewFailure { fetch, render }

/// 把渲染阶段的失败翻成人话。
///
/// `PlatformException(channel-error, Unable to establish connection on channel.)`
/// 翻成中文照样什么也没说。它的语义是**原生侧没有这个插件**：App 二进制比依赖
/// 装得早——装完插件只做了 Hot Restart / Hot Reload，原生那一侧根本没重新编，
/// 通道没人接，pigeon 拿到 null 就报 channel-error。
///
/// 这时重试一百次还是同一句话，所以文案直接给「下一步做什么」，而不是给错误类型。
String _renderFailureMessage(Object error) {
  if (error is PlatformException && error.code == 'channel-error') {
    return '预览引擎没有随这次启动加载进来。请完全退出 App 后重新打开；'
        '若刚装完依赖就走到这里，需要重新构建一次——热重载不会加载原生插件。';
  }
  return '预览失败：$error';
}

/// 失败统一留痕：页面已经把异常接住并给了错误态，控制台不该因此一句话都没有。
///
/// 接住不等于没发生。排障要看的是「哪一步、什么错」，UI 上那句人话是给用户看的，
/// 这条是给看日志的人看的。
void _logFailure(String stage, Object error) {
  debugPrint('[export] $stage 失败: $error');
}

class _ExportPreviewPageState extends ConsumerState<ExportPreviewPage> {
  Uint8List? _bytes;
  Object? _error;
  _PreviewFailure? _failure;
  PdfDocument? _document;
  PdfControllerPinch? _controller;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    // 顺序要紧：先断控制器（它不拥有文档的生命周期），再关文档。
    // pdfx 不会替你关——打开出来的 PdfDocument 是原生侧的句柄，
    // 不 close 就一直是泄漏。
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    unawaited(_closeDocument());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _failure = null;
      _bytes = null;
    });
    final previous = _controller;
    _controller = null;
    previous?.dispose();
    await _closeDocument();

    final Uint8List bytes;
    try {
      bytes = await ref
          .read(exportRepositoryProvider)
          .exportSheet(widget.request);
    } catch (e) {
      _logFailure('取字节', e);
      if (!mounted) return;
      setState(() {
        _failure = _PreviewFailure.fetch;
        _error = e;
      });
      return;
    }
    if (!mounted) return;

    final PdfDocument document;
    try {
      // ⚠️ 这一步必须自己 await，不能把未完成的 Future 直接交给控制器。
      //
      // pdfx 打开文档要过原生渲染引擎。App 进程早于依赖安装（装完插件只做了
      // Hot Restart / Hot Reload，原生那一侧压根没有 PdfxPlugin），或当前平台
      // 没有实现时，这里抛 PlatformException(channel-error)。若把它原样交给
      // PdfControllerPinch，异常会掉进「无人 await 的异步空档」——控制台一条
      // Unhandled Exception，页面上既没有错误态也没有重试入口，看起来像卡死。
      document = await ref.read(pdfDocumentOpenerProvider)(bytes);
    } catch (e) {
      _logFailure('打开预览文档', e);
      if (!mounted) return;
      setState(() {
        _failure = _PreviewFailure.render;
        _error = e;
      });
      return;
    }
    if (!mounted) {
      unawaited(_closeQuietly(document));
      return;
    }

    setState(() {
      _bytes = bytes;
      _document = document;
      _controller = PdfControllerPinch(document: Future.value(document));
    });
  }

  /// 渲染失败的兜底口：文档已经打开、但在后续翻页/取页时才炸的情况也归到预览失败。
  void _onDocumentError(Object error) {
    _logFailure('渲染页面', error);
    if (!mounted) return;
    setState(() {
      _failure = _PreviewFailure.render;
      _error = error;
    });
  }

  Future<void> _closeDocument() async {
    final document = _document;
    _document = null;
    if (document == null) return;
    await _closeQuietly(document);
  }

  static Future<void> _closeQuietly(PdfDocument document) async {
    try {
      await document.close();
    } catch (_) {
      // 关不掉这件事本身无从挽回；手柄泄漏只影响本次会话，
      // 不能把「关不掉」再抛回 UI，把一个已经出错的页面二次打崩。
    }
  }

  Future<void> _print() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;
    setState(() => _busy = true);
    try {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      _logFailure('打印', e);
      if (mounted) AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;
    setState(() => _busy = true);
    try {
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${widget.title}.pdf',
      );
    } catch (e) {
      _logFailure('分享', e);
      if (mounted) AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final body = switch ((_controller, _error)) {
      (_, final Object? e) when e != null => AppError(
          message: _failure == _PreviewFailure.render
              ? _renderFailureMessage(e)
              : '导出失败：$e',
          onRetry: _load,
        ),
      (null, _) => const AppLoading(message: '正在生成练习卷...'),
      (final PdfControllerPinch controller, _) => PdfViewPinch(
          controller: controller,
          onDocumentError: _onDocumentError,
        ),
    };

    // 返回入口由 [AppPushedPage] 结构性保证：整页被 push 出来后既不在
    // [AdaptiveShell] 的宽度兜底范围内、也没有侧栏/底栏可走，出路必须在骨架这一层——
    // 此前这页漏了 `showBack`，桌面端既无系统返回手势也无 Esc，等于把人锁死在这一屏。
    return AppPushedPage(
      title: '打印预览',
      background: app.surface,
      child: Column(
        children: [
          if (widget.downgradedCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: app.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: AppBrutal.ink,
                    width: AppElevation.borderWidthSm,
                  ),
                ),
                child: Text(
                  '${widget.downgradedCount} 道题含公式或图片，已按纯文本打印',
                  style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
                ),
              ),
            ),
          Expanded(child: body),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  ShadButton.outline(
                    // 没有字节就没有动作。错误态下给一个可点的「分享 / 打印」等于
                    // 承诺当下不可能发生的事；加载态同理。预览 / 打印 / 分享
                    // 复用同一份字节（见类注释），额外的 _busy 只是防抖：
                    // 同一动作不能连点两次。
                    // 可用性绑定在「预览已就绪」而不是「字节已到手」：
                    // 渲染失败时字节照样在内存里，但那个失败恰恰说明这份文档
                    // 没被任何引擎打开过——让它可打印等于承诺一件当下做不到、
                    // 且失败原因未明的事。错误要的是一条明确的路（重试 / 返回），
                    // 不是一个可能同样炸的按钮。
                    onPressed: _controller == null || _busy ? null : _share,
                    leading: const Icon(LucideIcons.share2, size: 16),
                    child: const Text('分享'),
                  ),
                  ShadButton(
                    onPressed: _controller == null || _busy ? null : _print,
                    leading: const Icon(LucideIcons.printer, size: 16),
                    child: const Text('打印'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
