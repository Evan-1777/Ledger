import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/core/api/models.dart';
import 'package:ledger_app/features/assets/assets_utils.dart';
import 'package:ledger_app/features/stats/stats_utils.dart';

import '../support/harness.dart';

void main() {
  test('stats derivatives handle zero denominators', () {
    final summary = StatsSummary.fromJson(statsJson());
    final now = DateTime(2026, 10, 10);

    expect(dailyAverage(summary.monthExpense, now), closeTo(324.85, 0.001));
    expect(
      monthOverMonth(summary.monthExpense, summary.lastMonthExpense),
      closeTo(12.4, 0.1),
    );
    expect(ratioOf(0, 0), 0);
    expect(ratioOf(2, 1), 1);
    expect(trendLabel('2026-03'), '3月');
  });

  test('month over month is null when last month is empty', () {
    expect(monthOverMonth(0, 0), isNull);
    expect(dailyAverage(0, DateTime(2026, 10, 1)), 0);
  });

  test('assets sort by balance and share only positive balances', () {
    final summary = AssetSummary.fromJson({
      'total_assets': 1000,
      'total_liabilities': 500,
      'net_assets': 500,
      'asset_channels': [
        {'id': 1, 'name': '现金', 'remaining_balance': 200, 'percentage': 20},
        {'id': 2, 'name': '银行卡', 'remaining_balance': 900, 'percentage': 90},
        {'id': 3, 'name': '透支卡', 'remaining_balance': -100, 'percentage': 0},
      ],
      'liability_channels': [
        {
          'id': 5,
          'name': '信用卡',
          'current_debt': 500,
          'credit_limit': 2000,
          'remaining_credit': 1500,
          'usage_rate': 25,
        },
      ],
    });

    final derived = deriveAssets(summary);

    expect(derived.assets.map((item) => item.channel.name), [
      '银行卡',
      '现金',
      '透支卡',
    ]);
    expect(derived.assets[0].share, closeTo(900 / 1100, 0.0001));
    expect(derived.assets[2].share, 0);
    expect(derived.debtRatio, 50);
    expect(liabilityUsage(derived.liabilities.single), 25);
    expect(
      liabilityUsage(
        const LiabilityChannelStat(
          id: 1,
          name: '卡',
          currentDebt: 0,
          initialDebt: 0,
          creditLimit: 100,
          remainingCredit: 100,
          usageRate: 150,
        ),
      ),
      100,
    );
  });

  test('debt ratio is null when assets are not positive', () {
    final derived = deriveAssets(
      const AssetSummary(
        totalAssets: 0,
        totalLiabilities: 100,
        netAssets: -100,
        assetChannels: [],
        liabilityChannels: [],
      ),
    );

    expect(derived.debtRatio, isNull);
    expect(derived.assets, isEmpty);
  });
}
