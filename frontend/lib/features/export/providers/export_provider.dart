import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/repositories/export_repository_impl.dart';
import '../domain/export_repository.dart';

/// export feature 的**组合根**。选址理由见
/// `features/authentication/providers/auth_provider.dart` 的同名注释。
final exportRepositoryProvider = Provider<ExportRepository>((ref) {
  return ExportRepositoryImpl(ref.watch(networkServiceProvider));
});

/// 把 PDF 字节交给渲染引擎，换回一个可以分页渲染的文档句柄。
typedef PdfDocumentOpener = Future<PdfDocument> Function(Uint8List bytes);

/// 打开 PDF 的唯一入口。
///
/// 之所以要经过 provider，而不是让页面直接 `PdfDocument.openData(bytes)`：
/// 这一步走原生渲染引擎，**会失败**——
/// App 进程早于依赖安装（装完插件只 Hot Restart，原生侧没有这个插件）、
/// 当前平台没有实现、字节不是 PDF 都是现实例子。失败必须能被确定性地测出来，
/// 而对着真实平台通道写替身做不到：没有原生一侧时那个 Future 既不完成也不报错，
/// 测试只会挂在那里（实测如此）。抽成接缝后，测试可以直接替换成「抛特定错误」。
final pdfDocumentOpenerProvider = Provider<PdfDocumentOpener>((ref) {
  return (bytes) => PdfDocument.openData(bytes);
});
