import 'dart:math' as math;

double dailyAverage(double amount, DateTime now) =>
    amount / math.max(1, now.day);

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
