import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/features/stats/stats_screen.dart';

import '../support/harness.dart';

void main() {
  setUpAll(initTestLocale);

  testWidgets('stats page shows hero, metrics and chart toggle', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StatsScreen(),
      controllers: controllers,
    );

    expect(find.text('本月结余'), findsOneWidget);
    expect(find.text('¥9,551.50'), findsOneWidget);
    expect(find.text('本周花费'), findsOneWidget);
    expect(find.text('当月花费'), findsOneWidget);
    expect(find.text('支出构成'), findsOneWidget);
    expect(find.text('餐饮美食'), findsWidgets);

    await tester.tap(find.text('趋势'));
    await tester.pumpAndSettle();
    expect(find.text('近 6 个月收支'), findsOneWidget);
    expect(find.text('支出'), findsWidgets);

    await tester.tap(find.text('构成'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('餐饮美食').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮美食').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('细分标签'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
  });

  testWidgets('stats page handles empty data', (tester) async {
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/stats/summary') {
        return jsonResponse({
          ...statsJson(monthExpense: 0, monthIncome: 0, monthBalance: 0),
          'category_distribution': [],
          'payment_distribution': [],
          'monthly_trends': [],
        });
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StatsScreen(),
      controllers: controllers,
    );

    expect(find.text('当月暂无分类支出'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('当月暂无渠道支出'), findsOneWidget);
    expect(find.text('储蓄率 0.0%'), findsNothing);
  });

  testWidgets('stats fit 320dp with 2x text', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StatsScreen(),
      controllers: controllers,
      size: const Size(320, 800),
      textScaler: const TextScaler.linear(2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
