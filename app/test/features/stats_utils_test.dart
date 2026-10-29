import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/core/api/models.dart';
import 'package:ledger_app/features/stats/stats_utils.dart';

import '../support/harness.dart';

void main() {
  setUpAll(initTestLocale);

  test('range presets use calendar boundaries', () {
    final wednesday = DateTime(2026, 10, 28);
    final sunday = DateTime(2026, 11, 1);

    final week = resolveRange(StatsRangePreset.week, wednesday);
    expect(week.start, DateTime(2026, 10, 26));
    expect(week.end, DateTime(2026, 10, 28));

    final sundayWeek = resolveRange(StatsRangePreset.week, sunday);
    expect(sundayWeek.start, DateTime(2026, 10, 26));
    expect(sundayWeek.end, DateTime(2026, 11, 1));

    final month = resolveRange(StatsRangePreset.month, wednesday);
    expect(month.start, DateTime(2026, 10, 1));
    expect(month.end, DateTime(2026, 10, 28));

    final lastMonth = resolveRange(StatsRangePreset.lastMonth, wednesday);
    expect(lastMonth.start, DateTime(2026, 9, 1));
    expect(lastMonth.end, DateTime(2026, 9, 30));

    final last30 = resolveRange(StatsRangePreset.last30, wednesday);
    expect(last30.start, DateTime(2026, 9, 29));
    expect(last30.end, DateTime(2026, 10, 28));
  });

  test('range preset and label round-trip', () {
    final now = DateTime(2026, 10, 28);
    final range = resolveRange(StatsRangePreset.last30, now);
    expect(rangePresetFor(range, now), StatsRangePreset.last30);
    expect(rangeLabel(StatsRangePreset.last30, range), '近 30 天');

    final custom = rangePresetFor(
      DateTimeRange(start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 9)),
      now,
    );
    expect(custom, StatsRangePreset.custom);
    expect(
      rangeLabel(
        custom,
        DateTimeRange(start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 9)),
      ),
      '9月3日 - 9月9日',
    );
  });

  test('dimension summary prefers category then tag', () {
    final categories = [
      Category.fromJson({
        'id': 1,
        'name': '餐饮美食',
        'type': 'expense',
        'tags': [
          {'id': 1, 'category_id': 1, 'name': '午餐'},
        ],
      }),
    ];
    expect(
      dimensionSummary(
        StatsQuery(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 28)),
        categories,
      ),
      '全部维度',
    );
    expect(
      dimensionSummary(
        StatsQuery(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 28),
          categoryId: 1,
        ),
        categories,
      ),
      '餐饮美食',
    );
    expect(
      dimensionSummary(
        StatsQuery(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 28),
          categoryId: 1,
          tagId: 1,
        ),
        categories,
      ),
      '餐饮美食 · 午餐',
    );
  });

  test('daily average uses the range day count', () {
    expect(dailyAverage(100, 28), closeTo(3.571, 0.001));
    expect(dailyAverage(100, 0), 100);
  });
}
