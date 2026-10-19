import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/core/api/models.dart';
import 'package:ledger_app/features/record/record_rules.dart';

import '../support/fakes.dart';

void main() {
  final channels = [
    paymentMethod(id: 1, name: '招商银行卡'),
    paymentMethod(id: 2, name: '支付宝'),
    paymentMethod(id: 3, name: '现金'),
    paymentMethod(
      id: 5,
      name: '招商信用卡',
      type: ChannelType.liability,
      creditLimit: 20000,
    ),
  ];

  test('target channels follow the transaction type', () {
    expect(
      RecordRules.targetChannels(TransactionType.expense, channels).length,
      4,
    );
    expect(
      RecordRules.targetChannels(
        TransactionType.income,
        channels,
      ).map((item) => item.id),
      [1, 2, 3],
    );
    expect(
      RecordRules.targetChannels(
        TransactionType.transfer,
        channels,
      ).map((item) => item.id),
      [1, 2, 3],
    );
    expect(
      RecordRules.targetChannels(
        TransactionType.repayment,
        channels,
      ).map((item) => item.id),
      [5],
    );
  });

  test('source channels only exist for transfer and repayment', () {
    expect(
      RecordRules.sourceChannels(TransactionType.expense, channels),
      isEmpty,
    );
    expect(
      RecordRules.sourceChannels(TransactionType.transfer, channels).length,
      3,
    );
    expect(
      RecordRules.sourceChannels(TransactionType.repayment, channels).length,
      3,
    );
  });

  test('transfer requires two distinct asset channels', () {
    final assets = RecordRules.targetChannels(
      TransactionType.transfer,
      channels,
    );
    expect(
      RecordRules.transferReady(assets: assets, sourceId: 1, targetId: 2),
      isTrue,
    );
    expect(
      RecordRules.transferReady(assets: assets, sourceId: 1, targetId: 1),
      isFalse,
    );
    expect(
      RecordRules.transferReady(
        assets: [channels[0]],
        sourceId: 1,
        targetId: 1,
      ),
      isFalse,
    );
    expect(
      RecordRules.transferReady(assets: assets, sourceId: null, targetId: 2),
      isFalse,
    );
  });

  test('amount and fee parsing rejects invalid values', () {
    expect(RecordRules.parsePositiveAmount('28.50'), 28.5);
    expect(RecordRules.parsePositiveAmount('0'), isNull);
    expect(RecordRules.parsePositiveAmount('-1'), isNull);
    expect(RecordRules.parsePositiveAmount('abc'), isNull);
    expect(RecordRules.parseFee(''), 0);
    expect(RecordRules.parseFee('1.5'), 1.5);
    expect(RecordRules.parseFee('0'), 0);
    expect(RecordRules.parseFee('-0.1'), isNull);
    expect(RecordRules.parseFee('abc'), isNull);
  });
}
