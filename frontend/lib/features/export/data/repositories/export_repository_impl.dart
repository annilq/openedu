import 'dart:typed_data';

import '../../../../shared/data/remote/network_service.dart';
import '../../domain/export_repository.dart';

/// 打印导出实现：单一端点 `POST /export/sheet`，返回 `application/pdf` 字节。
///
/// 服务端按 id 自己取数与装配——客户端不传题面内容，只传「选了谁」。
class ExportRepositoryImpl implements ExportRepository {
  ExportRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<Uint8List> exportSheet(ExportSheetRequest request) {
    return _network.postBytes('/export/sheet', body: request.toJson());
  }
}
