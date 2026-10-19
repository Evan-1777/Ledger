import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/core/format/dates.dart';
import 'package:ledger_app/core/format/money.dart';

import '../support/harness.dart';

void main() {
  setUpAll(initTestLocale);

  test('money formatting keeps sign, currency and two decimals', () {
    expect(formatMoney(1234.5), '¥1,234.50');
    expect(formatMoney(-28), '-¥28.00');
    expect(formatMoney(28, signed: true), '+¥28.00');
    expect(formatMoney(-28, signed: true), '-¥28.00');
    expect(formatMoney(1234.5, withCurrency: false), '1,234.50');
    expect(formatCents(-2800), '-¥28.00');
  });

  test('percent formatting uses one decimal', () {
    expect(formatPercent(74.56), '74.6%');
    expect(formatPercent(0), '0.0%');
  });

  test('relative day labels cross the year boundary', () {
    final now = DateTime(2026, 10, 19, 12);
    expect(formatDayLabel(DateTime(2026, 10, 19), now), '今天');
    expect(formatDayLabel(DateTime(2026, 10, 18), now), '昨天');
    expect(formatDayLabel(DateTime(2026, 10, 17), now), '10月17日');
    expect(formatDayLabel(DateTime(2025, 10, 17), now), '2025年10月17日');
  });
}
