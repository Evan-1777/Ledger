import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/format/dates.dart';

enum StatsRangePreset {
  week,
  month,
  lastMonth,
  last30,
  custom;

  String get label => switch (this) {
    StatsRangePreset.week => '本周',
    StatsRangePreset.month => '本月',
    StatsRangePreset.lastMonth => '上月',
    StatsRangePreset.last30 => '近 30 天',
    StatsRangePreset.custom => '自定义',
  };
}

DateTimeRange resolveRange(StatsRangePreset preset, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return switch (preset) {
    StatsRangePreset.week => DateTimeRange(
      start: today.subtract(Duration(days: now.weekday - 1)),
      end: today,
    ),
    StatsRangePreset.month => DateTimeRange(
      start: DateTime(today.year, today.month),
      end: today,
    ),
    StatsRangePreset.lastMonth => DateTimeRange(
      start: DateTime(today.year, today.month - 1),
      end: DateTime(today.year, today.month, 0),
    ),
    StatsRangePreset.last30 => DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: today,
    ),
    StatsRangePreset.custom => DateTimeRange(start: today, end: today),
  };
}

StatsRangePreset rangePresetFor(DateTimeRange range, DateTime now) {
  const ordered = [
    StatsRangePreset.month,
    StatsRangePreset.week,
    StatsRangePreset.lastMonth,
    StatsRangePreset.last30,
  ];
  for (final preset in ordered) {
    final candidate = resolveRange(preset, now);
    if (_sameDay(candidate.start, range.start) &&
        _sameDay(candidate.end, range.end)) {
      return preset;
    }
  }
  return StatsRangePreset.custom;
}

String rangeLabel(StatsRangePreset preset, DateTimeRange range) {
  if (preset != StatsRangePreset.custom) return preset.label;
  final sameYear = range.start.year == range.end.year;
  final start = sameYear
      ? formatMonthDay(range.start)
      : '${range.start.year}年${formatMonthDay(range.start)}';
  final end = sameYear
      ? formatMonthDay(range.end)
      : '${range.end.year}年${formatMonthDay(range.end)}';
  return '$start - $end';
}

String dimensionSummary(StatsQuery query, List<Category> categories) {
  if (query.categoryId == null) return '全部维度';
  final matches = categories.where((item) => item.id == query.categoryId);
  final category = matches.isEmpty ? null : matches.first;
  if (query.tagId == null) return category?.name ?? '全部维度';
  final tags =
      category?.tags.where((item) => item.id == query.tagId) ?? const [];
  if (tags.isEmpty) return category?.name ?? '全部维度';
  return '${category!.name} · ${tags.first.name}';
}

double dailyAverage(double amount, int days) => amount / math.max(1, days);

double? monthOverMonth(double current, double previous) {
  if (previous <= 0) return null;
  return (current - previous) / previous * 100;
}

double ratioOf(double part, double whole) =>
    whole <= 0 ? 0 : (part / whole).clamp(0, 1).toDouble();

String trendLabel(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  return '${int.tryParse(parts[1]) ?? parts[1]}月';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
