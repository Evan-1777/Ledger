import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/core/api/models.dart';
import 'package:ledger_app/features/stream/stream_utils.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  setUpAll(initTestLocale);

  test('transactions are grouped by local day in descending order', () {
    final list = [
      transactionModel(id: 1, transactedAt: DateTime(2026, 10, 19, 8)),
      transactionModel(id: 2, transactedAt: DateTime(2026, 10, 19, 9)),
      transactionModel(id: 3, transactedAt: DateTime(2026, 10, 18, 20)),
    ];

    final groups = groupTransactions(list);

    expect(groups.length, 2);
    expect(groups.first.date, DateTime(2026, 10, 19));
    expect(groups.first.items.map((item) => item.id), [1, 2]);
    expect(groups.last.date, DateTime(2026, 10, 18));
  });

  test('day subtotals exclude transfers and repayments', () {
    final list = [
      transactionModel(id: 1, amountCents: -2800),
      transactionModel(
        id: 2,
        type: TransactionType.income,
        amountCents: 320000,
      ),
      transactionModel(
        id: 3,
        type: TransactionType.transfer,
        amountCents: 10000,
      ),
      transactionModel(
        id: 4,
        type: TransactionType.repayment,
        amountCents: 50000,
      ),
    ];

    final group = groupTransactions(list).single;

    expect(group.expense, 28);
    expect(group.income, 3200);
    expect(daySubtotal(group), '支出 ¥28.00  收入 ¥3,200.00');
  });

  test('day subtotals skip categories excluded from stats', () {
    final list = [
      transactionModel(id: 1, amountCents: -2800),
      transactionModel(
        id: 2,
        amountCents: -1000,
        categoryId: 2,
        categoryName: '交通出行',
      ),
      transactionModel(
        id: 3,
        type: TransactionType.income,
        amountCents: 320000,
        categoryId: 4,
        categoryName: '职业收入',
      ),
    ];
    final group = groupTransactions(list).single;

    expect(
      daySubtotal(group, excludedCategoryIds: {1}),
      '支出 ¥10.00  收入 ¥3,200.00',
    );
    expect(group.expenseExcluding({1}), 10);
    expect(group.incomeExcluding({1}), 3200);
    expect(daySubtotal(group), '支出 ¥38.00  收入 ¥3,200.00');
  });

  test('day subtotals skip refunded transactions', () {
    final list = [
      transactionModel(id: 1, amountCents: -2800),
      transactionModel(
        id: 2,
        amountCents: -1000,
        refundedAt: DateTime(2026, 10, 19, 5),
      ),
      transactionModel(
        id: 3,
        type: TransactionType.income,
        amountCents: 320000,
      ),
      transactionModel(
        id: 4,
        type: TransactionType.income,
        amountCents: 5000,
        categoryId: 4,
        categoryName: '职业收入',
        refundedAt: DateTime(2026, 10, 19, 6),
      ),
    ];

    final group = groupTransactions(list).single;

    expect(group.items.length, 4);
    expect(group.expense, 28);
    expect(group.income, 3200);
    expect(daySubtotal(group), '支出 ¥28.00  收入 ¥3,200.00');
  });

  test('day header includes relative label, date and weekday', () {
    final now = DateTime(2026, 10, 19, 12);
    final groups = groupTransactions([
      transactionModel(id: 1, transactedAt: DateTime(2026, 10, 19, 8)),
      transactionModel(id: 2, transactedAt: DateTime(2026, 10, 18, 8)),
      transactionModel(id: 3, transactedAt: DateTime(2026, 10, 17, 8)),
    ]);

    expect(dayHeader(groups[0], now), '今天 10月19日 · 周一');
    expect(dayHeader(groups[1], now), '昨天 10月18日 · 周日');
    expect(dayHeader(groups[2], now), '10月17日 · 周六');
  });

  test('metadata describes category, tag, channel and fee', () {
    final expense = transactionModel(
      transactedAt: DateTime(2026, 10, 19, 8, 42),
    );
    final transfer = transactionModel(
      type: TransactionType.transfer,
      amountCents: 10000,
      feeCents: 150,
      paymentMethodName: '支付宝',
      sourcePaymentMethodName: '招商银行卡',
      transactedAt: DateTime(2026, 10, 19, 9, 5),
    );
    final repayment = transactionModel(
      type: TransactionType.repayment,
      amountCents: 50000,
      paymentMethodName: '招商信用卡',
      transactedAt: DateTime(2026, 10, 19, 10),
    );

    expect(transactionMeta(expense), '餐饮美食 · 午餐 · 08:42');
    expect(transactionNote(expense), '招商银行卡');
    expect(transactionMeta(transfer), '招商银行卡 → 支付宝 · 09:05');
    expect(transactionNote(transfer), '手续费 ¥1.50');
    expect(transactionMeta(repayment), '外部/未记录资金 → 招商信用卡 · 10:00');
    expect(transactionNote(repayment), '');
  });

  test('metadata omits an empty tag and a fee-free transfer', () {
    final noTag = transactionModel(tagName: '');
    final freeTransfer = transactionModel(
      type: TransactionType.transfer,
      amountCents: 10000,
      paymentMethodName: '支付宝',
      sourcePaymentMethodName: '招商银行卡',
      transactedAt: DateTime(2026, 10, 19, 9, 5),
    );

    expect(transactionMeta(noTag), '餐饮美食 · 08:42');
    expect(transactionNote(freeTransfer), '');
  });

  test('query summary lists active dimensions in a fixed order', () {
    final categories = [
      category(
        id: 1,
        name: '餐饮美食',
        tags: const [Tag(id: 1, categoryId: 1, name: '午餐', sortOrder: 1)],
      ),
      category(id: 4, name: '职业收入', type: CategoryType.income),
    ];
    final channels = [paymentMethod(id: 1, name: '招商银行卡')];

    expect(
      transactionQuerySummary(
        const TransactionQuery(),
        categories: categories,
        channels: channels,
      ),
      isNull,
    );
    expect(
      transactionQuerySummary(
        const TransactionQuery(keyword: ' 拼多多 '),
        categories: categories,
        channels: channels,
      ),
      '搜索「拼多多」',
    );
    expect(
      transactionQuerySummary(
        const TransactionQuery(
          type: TransactionType.expense,
          categoryId: 1,
          tagId: 1,
          paymentMethodId: 1,
          keyword: '午餐',
        ),
        categories: categories,
        channels: channels,
      ),
      '支出 · 餐饮美食 · 午餐 · 招商银行卡 · 搜索「午餐」',
    );
    expect(
      transactionQuerySummary(
        const TransactionQuery(categoryId: 99, paymentMethodId: 99),
        categories: categories,
        channels: channels,
      ),
      isNull,
    );
  });
}
