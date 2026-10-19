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

    expect(transactionMeta(expense), '餐饮美食 · 午餐 · 招商银行卡 · 08:42');
    expect(transactionMeta(transfer), '招商银行卡 → 支付宝 · 手续费 ¥1.50 · 09:05');
    expect(transactionMeta(repayment), '外部/未记录资金 → 招商信用卡 · 10:00');
  });
}
