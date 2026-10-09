import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../configs/app_config.dart';
import '../domain/providers/core_providers.dart';

/// 带鉴权的网络图片（修复素材库缩略图 / 预览双双加载失败，ADR-0077）。
///
/// 后端下发的素材 `url` 是**带 `/api/v1` 前缀的相对路径**（如
/// `/api/v1/courseware/assets/{id}/file`），且原图端点要求 Bearer 鉴权。
/// 直接用 `Image.network(asset.url)` 会双双失败：① 没有 host，URL 无法解析；
/// ② 不带 token，被后端 401/403 拒。**本组件补齐这两点**——拼绝对地址 +
/// 注入 `Authorization` 头。
///
/// 仍走 `Image.network`（而不是把字节读进内存）：流式下载 + 渐进解码，对大图更省内存。
class AuthImage extends ConsumerWidget {
  const AuthImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
  });

  /// 后端下发的相对路径（含 `/api/v1` 前缀）。
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.read(storageServiceProvider).getToken();
    // 去掉 base 可能的尾斜杠，避免 http://host//api/v1 双斜杠导致后端 404。
    final base = AppConfig.apiBase.endsWith('/')
        ? AppConfig.apiBase.substring(0, AppConfig.apiBase.length - 1)
        : AppConfig.apiBase;
    final absolute = base + url;
    final headers = token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : const <String, String>{};
    return Image.network(
      absolute,
      fit: fit,
      width: width,
      height: height,
      headers: headers,
      errorBuilder: errorBuilder ??
          (_, __, ___) => const Center(
                child: Icon(LucideIcons.imageOff, size: 28),
              ),
    );
  }
}
