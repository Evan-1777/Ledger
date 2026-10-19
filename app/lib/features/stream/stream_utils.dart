import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/format/dates.dart';
import '../../core/format/money.dart';
import '../../core/theme/finance_colors.dart';

class TransactionDayGroup {
  TransactionDayGroup({required this.date, required this.items});

  final DateTime date;
  final List<Transaction> items;

  double get expense => items
      .where((item) => item.type == TransactionType.expense)
      .fold(0, (sum, item) => sum + item.amount.abs());

  double get income => items
      .where((item) => item.type == TransactionType.income)
      .fold(0, (sum, item) => sum + item.amount.abs());
}

List<TransactionDayGroup> groupTransactions(List<Transaction> transactions) {
  final groups = <String, TransactionDayGroup>{};
  for (final transaction in transactions) {
    final local = transaction.localTransactedAt;
    final date = DateTime(local.year, local.month, local.day);
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    groups.putIfAbsent(key, () => TransactionDayGroup(date: date, items: []));
    groups[key]!.items.add(transaction);
  }
  final result = groups.values.toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return result;
}

String dayHeader(TransactionDayGroup group, DateTime now) {
  final label = formatDayLabel(group.date, now);
  final prefix = (label == '今天' || label == '昨天')
      ? '$label ${formatMonthDay(group.date)}'
      : label;
  return '$prefix · ${formatWeekday(group.date)}';
}

List<String> daySubtotalParts(TransactionDayGroup group) {
  final parts = <String>[];
  if (group.expense > 0) {
    parts.add('支出 ${formatMoney(group.expense)}');
  }
  if (group.income > 0) {
    parts.add('收入 ${formatMoney(group.income)}');
  }
  return parts;
}

String daySubtotal(TransactionDayGroup group) {
  return daySubtotalParts(group).join('  ');
}

String transactionMeta(Transaction transaction) {
  final time = formatTime(transaction.localTransactedAt);
  return switch (transaction.type) {
    TransactionType.transfer => [
      '${transaction.sourcePaymentMethodName} → ${transaction.paymentMethodName}',
      if (transaction.feeCents > 0) '手续费 ${formatMoney(transaction.fee)}',
      time,
    ].join(' · '),
    TransactionType.repayment => [
      '${transaction.sourcePaymentMethodName.isEmpty ? '外部/未记录资金' : transaction.sourcePaymentMethodName} → ${transaction.paymentMethodName}',
      time,
    ].join(' · '),
    _ => [
      transaction.categoryName,
      if (transaction.tagName.isNotEmpty) transaction.tagName,
      transaction.paymentMethodName,
      time,
    ].join(' · '),
  };
}

Color transactionColor(BuildContext context, Transaction transaction) {
  final finance = Theme.of(context).extension<FinanceColors>()!;
  return switch (transaction.type) {
    TransactionType.expense => finance.expense,
    TransactionType.income => finance.income,
    TransactionType.transfer => finance.transfer,
    TransactionType.repayment => finance.repayment,
  };
}
