import 'package:intl/intl.dart';

final _moneyFormat = NumberFormat('#,##0.00');

String formatMoney(
  double value, {
  bool withCurrency = true,
  bool signed = false,
}) {
  final sign = value < 0 ? '-' : (signed && value > 0 ? '+' : '');
  final body = _moneyFormat.format(value.abs());
  return '$sign${withCurrency ? '¥' : ''}$body';
}

String formatPercent(double value, {int digits = 1}) =>
    '${value.toStringAsFixed(digits)}%';
