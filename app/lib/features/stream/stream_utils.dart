import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/format/dates.dart';
import '../../core/format/money.dart';
import '../../core/theme/finance_colors.dart';

class TransactionDayGroup {
  TransactionDayGroup({required this.date, required this.items});

  final DateTime date;
  final List<Transaction> items;

  double get expense => expenseExcluding(const {});

  double expenseExcluding(Set<int> excludedCategoryIds) => items
      .where(
        (item) =>
            item.type == TransactionType.expense &&
            !excludedCategoryIds.contains(item.categoryId),
      )
      .fold(0, (sum, item) => sum + item.amount.abs());

  double get income => incomeExcluding(const {});

  double incomeExcluding(Set<int> excludedCategoryIds) => items
      .where(
        (item) =>
            item.type == TransactionType.income &&
            !excludedCategoryIds.contains(item.categoryId),
      )
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

List<String> daySubtotalParts(
  TransactionDayGroup group, {
  Set<int> excludedCategoryIds = const {},
}) {
  final parts = <String>[];
  final expense = group.expenseExcluding(excludedCategoryIds);
  final income = group.incomeExcluding(excludedCategoryIds);
  if (expense > 0) {
    parts.add('支出 ${formatMoney(expense)}');
  }
  if (income > 0) {
    parts.add('收入 ${formatMoney(income)}');
  }
  return parts;
}

String daySubtotal(
  TransactionDayGroup group, {
  Set<int> excludedCategoryIds = const {},
}) {
  return daySubtotalParts(
    group,
    excludedCategoryIds: excludedCategoryIds,
  ).join('  ');
}

String transactionMeta(Transaction transaction) {
  final time = formatTime(transaction.localTransactedAt);
  return switch (transaction.type) {
    TransactionType.transfer => [
      '${transaction.sourcePaymentMethodName} → ${transaction.paymentMethodName}',
      time,
    ].join(' · '),
    TransactionType.repayment => [
      '${transaction.sourcePaymentMethodName.isEmpty ? '外部/未记录资金' : transaction.sourcePaymentMethodName} → ${transaction.paymentMethodName}',
      time,
    ].join(' · '),
    _ => [
      transaction.categoryName,
      if (transaction.tagName.isNotEmpty) transaction.tagName,
      time,
    ].join(' · '),
  };
}

String transactionNote(Transaction transaction) {
  return switch (transaction.type) {
    TransactionType.transfer =>
      transaction.feeCents > 0 ? '手续费 ${formatMoney(transaction.fee)}' : '',
    TransactionType.repayment => '',
    _ => transaction.paymentMethodName,
  };
}

String? transactionQuerySummary(
  TransactionQuery query, {
  required List<Category> categories,
  required List<PaymentMethod> channels,
}) {
  final parts = <String>[];
  final type = query.type;
  if (type != null) parts.add(type.label);
  final category = _firstOrNull(
    categories,
    (item) => item.id == query.categoryId,
  );
  if (category != null) {
    parts.add(category.name);
    final tag = _firstOrNull(category.tags, (item) => item.id == query.tagId);
    if (tag != null) parts.add(tag.name);
  }
  final channel = _firstOrNull(
    channels,
    (item) => item.id == query.paymentMethodId,
  );
  if (channel != null) parts.add(channel.name);
  final keyword = query.keyword.trim();
  if (keyword.isNotEmpty) parts.add('搜索「$keyword」');
  return parts.isEmpty ? null : parts.join(' · ');
}

T? _firstOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
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
