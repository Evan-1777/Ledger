import 'dart:math' as math;

import '../../core/api/models.dart';

double dailyAverage(StatsSummary summary, DateTime now) =>
    summary.monthExpense / math.max(1, now.day);

double? monthOverMonth(StatsSummary summary) {
  if (summary.lastMonthExpense <= 0) return null;
  return (summary.monthExpense - summary.lastMonthExpense) /
      summary.lastMonthExpense *
      100;
}

double ratioOf(double part, double whole) =>
    whole <= 0 ? 0 : (part / whole).clamp(0, 1).toDouble();

String trendLabel(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  return '${int.tryParse(parts[1]) ?? parts[1]}月';
}
