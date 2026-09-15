/// 后端 JSON 解析守卫。
///
/// 放在 `shared/utils/`（而非 `shared/presentation/`）是因为**消费方是 data 层**：
/// repository 把原始响应体转成领域模型时要用它们。若留在 presentation，
/// data 层就得反向 import 展示层，依赖方向就乱了。
library;

/// 把后端 JSON 解成列表；不是数组就报错，而不是把类型错误甩给上层。
///
/// 此前 19 处各自写 `(data as List).map((e) => X.fromJson(e as Map))`，
/// 无类型守卫：后端返回对象时整页白屏，且每处的容错水平不一致。
List<M> decodeList<M>(dynamic data, M Function(Map<String, dynamic>) fromJson) {
  if (data is! List) {
    throw FormatException('期望数组，实际是 ${data.runtimeType}');
  }
  return [
    for (final e in data)
      fromJson(e is Map<String, dynamic> ? e : <String, dynamic>{}),
  ];
}

/// 把后端 JSON 解成对象；不是 Map 就报错。
Map<String, dynamic> decodeMap(dynamic data) {
  if (data is! Map<String, dynamic>) {
    throw FormatException('期望对象，实际是 ${data.runtimeType}');
  }
  return data;
}
