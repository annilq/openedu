import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Colors, IconButton, showDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import '../../configs/app_config.dart';
import '../domain/providers/core_providers.dart';

/// 全屏看图（ADR-0077）：点击素材缩略图放大查看原图。
///
/// 纯展示组件，素材库 / 课件环节缩略图 / 素材 picker 共用。遮罩 + InteractiveViewer
/// 支持平移/缩放；点击遮罩或关闭按钮退出。无任何素材库/课件依赖，便于复用。
Future<void> showImageViewer(
  BuildContext context, {
  required String url,
  String? name,
}) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => _ImageViewerOverlay(url: url, name: name),
    );

class _ImageViewerOverlay extends ConsumerWidget {
  const _ImageViewerOverlay({required this.url, this.name});

  final String url;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppTheme.textOf(context);
    // 后端 url 是带 /api/v1 的相对路径，且需 Bearer 鉴权——补绝对地址 + token。
    final token = ref.read(storageServiceProvider).getToken();
    final base = AppConfig.apiBase.endsWith('/')
        ? AppConfig.apiBase.substring(0, AppConfig.apiBase.length - 1)
        : AppConfig.apiBase;
    final absolute = base + url;
    final headers = token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : const <String, String>{};
    return Stack(
      children: [
        // 遮罩：点它即退出（图片与遮罩同级，但图片在遮罩之上拦截手势）。
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(color: const Color(0xE6000000)),
          ),
        ),
        // 原图：InteractiveViewer 支持双指缩放 / 拖拽。
        Center(
          child: InteractiveViewer(
            child: Image.network(
              absolute,
              fit: BoxFit.contain,
              headers: headers,
              errorBuilder: (_, __, ___) => _broken(text),
            ),
          ),
        ),
        // 顶部条：名称 + 关闭。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name != null && name!.isNotEmpty)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        name!,
                        style:
                            text.titleMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.white),
                  iconSize: 22,
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _broken(AppText text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.imageOff,
                size: 48, color: Colors.white70),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '图片加载失败',
              style: text.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      );
}
