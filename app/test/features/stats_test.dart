import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/core/widgets/ledger_widgets.dart';
import 'package:ledger_app/features/stats/stats_screen.dart';

import '../support/harness.dart';

void expectEqualMetricCards(WidgetTester tester) {
  Rect card(String label) => tester.getRect(
    find
        .ancestor(of: find.text(label), matching: find.byType(LedgerCard))
        .first,
  );
  final week = card('本周花费');
  final month = card('当月花费');
  final lastMonth = card('上月花费');
  final daily = card('日均花费');
  expect(week.top, month.top);
  expect(lastMonth.top, daily.top);
  final heights = [week.height, month.height, lastMonth.height, daily.height];
  expect(
    heights.reduce(math.max) - heights.reduce(math.min),
    lessThanOrEqualTo(0.5),
  );
}

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

    expect(find.byType(LedgerSliverAppBar), findsOneWidget);
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

  testWidgets('metric cards share height across all four', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StatsScreen(),
      controllers: controllers,
      size: const Size(390, 1400),
    );
    await tester.pumpAndSettle();
    expectEqualMetricCards(tester);

    final noNote = statsJson();
    noNote['last_month_expense'] = 0;
    final noNoteControllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/stats/summary') {
        return jsonResponse(noNote);
      }
      return defaultApi(request);
    });
    await noNoteControllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StatsScreen(),
      controllers: noNoteControllers,
      size: const Size(390, 1400),
    );
    await tester.pumpAndSettle();
    expectEqualMetricCards(tester);
  });

  testWidgets('chart card sizes to content without inner scrolling', (
    tester,
  ) async {
    final stats = statsJson(monthExpense: 171);
    stats['category_distribution'] = [
      {
        'id': 1,
        'name': '功能性支出',
        'amount': 77.63,
        'percentage': 45.4,
        'tags': <Object?>[],
      },
      {
        'id': 2,
        'name': '零食消费',
        'amount': 37.73,
        'percentage': 22.1,
        'tags': <Object?>[],
      },
      {
        'id': 3,
        'name': '虚拟商品',
        'amount': 30.33,
        'percentage': 17.7,
        'tags': <Object?>[],
      },
      {
        'id': 4,
        'name': '生活缴费',
        'amount': 20.33,
        'percentage': 11.9,
        'tags': <Object?>[],
      },
      {
        'id': 5,
        'name': '购物消费',
        'amount': 4.33,
        'percentage': 2.5,
        'tags': <Object?>[],
      },
    ];
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/stats/summary') {
        return jsonResponse(stats);
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StatsScreen(),
      controllers: controllers,
      size: const Size(390, 1400),
    );
    await tester.pumpAndSettle();

    final compositionCard = find
        .ancestor(of: find.text('支出构成'), matching: find.byType(LedgerCard))
        .first;
    final compositionHeight = tester.getSize(compositionCard).height;
    expect(
      find.descendant(
        of: compositionCard,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    for (final name in ['功能性支出', '零食消费', '虚拟商品', '生活缴费', '购物消费']) {
      expect(find.text(name), findsOneWidget);
    }

    await tester.tap(find.text('趋势'));
    await tester.pumpAndSettle();

    final trendCard = find
        .ancestor(of: find.text('近 6 个月收支'), matching: find.byType(LedgerCard))
        .first;
    expect(
      find.descendant(
        of: trendCard,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(tester.getSize(trendCard).height, lessThan(compositionHeight));
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

    await tester.scrollUntilVisible(
      find.text('趋势'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('趋势'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
