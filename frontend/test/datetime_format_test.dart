import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/shared/util/datetime_format.dart';

String _fmt(int v) => v.toString().padLeft(2, '0');

void main() {
  test('UTC 输入转本地时区', () {
    const iso = '2026-09-15T12:00:00+00:00';
    final got = formatLocalDayMinute(iso);
    final local = DateTime.parse(iso).toLocal();
    final expected =
        '${_fmt(local.month)}-${_fmt(local.day)} ${_fmt(local.hour)}:${_fmt(local.minute)}';
    expect(got, expected);
  });

  test('非法串 fallback 为空串', () {
    expect(formatLocalDayMinute('not-a-date'), '');
    expect(formatLocalDayMinute(''), '');
  });

  test('正常本地化（无时区偏移串按本地解析）', () {
    const iso = '2026-03-04T09:05:00';
    final got = formatLocalDayMinute(iso);
    final local = DateTime.parse(iso).toLocal();
    final expected =
        '${_fmt(local.month)}-${_fmt(local.day)} ${_fmt(local.hour)}:${_fmt(local.minute)}';
    expect(got, expected);
    expect(got, '03-04 09:05');
  });
}
