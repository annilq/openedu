/// 模型层共用的日期解析：后端 ISO 字符串 → [DateTime]，空串 / null → null。
///
/// 原来是 `models.dart` 里的私有 `_parseDate`——**私有标识符不能跨 library**，
/// 按聚合拆文件后它被 question / wrong_question / mastery 三个聚合同时使用，
/// 只能提为公开。放在这里而不是塞回某个聚合文件，是因为它不属于任何聚合。
///
/// 只做解析不做格式化：展示层的格式化走 `shared/util/datetime_format.dart`。
DateTime? parseDate(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
