import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_app/core/format/dates.dart';
import 'package:ledger_app/core/widgets/ledger_widgets.dart';
import 'package:ledger_app/features/stats/stats_screen.dart';

import '../support/harness.dart';

void expectEqualMetricCards(WidgetTester tester) {
  Rect card(String label) => tester.getRect(
    find
        .ancestor(of: find.text(label), matching: find.byType(LedgerCard))
        .first,
  );
  final current = card('本期支出');
  final daily = card('日均支出');
  final previous = card('上期支出');
  final average = card('单笔均额');
  expect(current.top, daily.top);
  expect(previous.top, average.top);
  final heights = [
    current.height,
    daily.height,
    previous.height,
    average.height,
  ];
  expect(
    heights.reduce(math.max) - heights.reduce(math.min),
    lessThanOrEqualTo(0.5),
  );
}

void main() {
  setUpAll(initTestLocale);

  Future<TestControllers> mountStats(
    WidgetTester tester, {
    Future<http.Response> Function(http.Request)? handler,
    Size size = const Size(390, 1400),
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    final controllers = await testControllersWithHandler(handler ?? defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StatsScreen(),
      controllers: controllers,
      size: size,
      textScaler: textScaler,
    );
    await tester.pumpAndSettle();
    return controllers;
  }

  http.Request lastRangeRequest(List<http.Request> requests) =>
      requests.lastWhere((request) => request.url.path == '/api/stats/range');

  String dateParam(DateTime date) => formatDateParam(date);

  testWidgets('stats page shows range summary, hero, metrics and chart', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final controllers = await mountStats(
      tester,
      handler: (request) async {
        requests.add(request);
        return defaultApi(request);
      },
    );

    final now = DateTime.now();
    expect(find.text('结余'), findsOneWidget);
    expect(find.text('本月 · 全部维度'), findsOneWidget);
    expect(find.text('¥9,551.50'), findsOneWidget);
    expect(find.text('本期支出'), findsOneWidget);
    expect(find.text('日均支出'), findsOneWidget);
    expect(find.text('上期支出'), findsOneWidget);
    expect(find.text('单笔均额'), findsOneWidget);
    expect(find.text('支出构成'), findsOneWidget);
    expect(find.text('餐饮美食'), findsWidgets);
    expect(find.text('储蓄率 74.6%'), findsOneWidget);

    final query = lastRangeRequest(requests).url.queryParameters;
    expect(query['start'], dateParam(DateTime(now.year, now.month)));
    expect(query['end'], dateParam(now));
    expect(query.containsKey('category_id'), isFalse);
    expect(query.containsKey('tag_id'), isFalse);

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
    expect(controllers.ledger.rangeStats?.expense, 3248.5);
  });

  testWidgets('income view swaps metrics, composition and channels', (
    tester,
  ) async {
    await mountStats(tester);

    expect(find.text('支出构成'), findsOneWidget);
    expect(find.text('本期支出'), findsOneWidget);
    expect(find.text('支付途径'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stats-view-income')));
    await tester.pumpAndSettle();

    expect(find.text('收入构成'), findsOneWidget);
    expect(find.text('本期收入'), findsOneWidget);
    expect(find.text('日均收入'), findsOneWidget);
    expect(find.text('上期收入'), findsOneWidget);
    expect(find.text('收入途径'), findsOneWidget);
    expect(find.text('支出构成'), findsNothing);
    expect(find.text('本期支出'), findsNothing);
    expect(find.text('支付途径'), findsNothing);

    await tester.tap(find.text('趋势'));
    await tester.pumpAndSettle();
    expect(find.text('近 6 个月收支'), findsOneWidget);
    await tester.tap(find.text('构成'));
    await tester.pumpAndSettle();
    expect(find.text('收入构成'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stats-view-expense')));
    await tester.pumpAndSettle();
    expect(find.text('支出构成'), findsOneWidget);
    expect(find.text('本期支出'), findsOneWidget);
  });

  testWidgets('filter draft does not apply until the user confirms', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await mountStats(
      tester,
      handler: (request) async {
        requests.add(request);
        return defaultApi(request);
      },
    );
    final before = requests
        .where((r) => r.url.path == '/api/stats/range')
        .length;

    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    expect(find.text('日期范围'), findsOneWidget);
    expect(find.text('选择分类后可筛选标签'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stats-range-lastMonth')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('本月 · 全部维度'), findsOneWidget);
    expect(
      requests.where((r) => r.url.path == '/api/stats/range').length,
      before,
    );

    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-range-lastMonth')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-filter-apply')));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final query = lastRangeRequest(requests).url.queryParameters;
    expect(query['start'], dateParam(DateTime(now.year, now.month - 1)));
    expect(query['end'], dateParam(DateTime(now.year, now.month, 0)));
    expect(find.text('上月 · 全部维度'), findsOneWidget);
  });

  testWidgets('applying income or tag dimensions switches view and request', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await mountStats(
      tester,
      handler: (request) async {
        requests.add(request);
        return defaultApi(request);
      },
    );

    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('stats-category-4')));
    await tester.tap(find.byKey(const ValueKey('stats-category-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('收入构成'), findsOneWidget);
    expect(find.text('本月 · 职业收入'), findsOneWidget);
    expect(lastRangeRequest(requests).url.queryParameters['category_id'], '4');

    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('stats-category-1')));
    await tester.tap(find.byKey(const ValueKey('stats-category-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-tag-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-filter-apply')));
    await tester.pumpAndSettle();

    final query = lastRangeRequest(requests).url.queryParameters;
    expect(query['category_id'], '1');
    expect(query['tag_id'], '1');
    expect(find.text('支出构成'), findsOneWidget);
    expect(find.text('本月 · 餐饮美食 · 午餐'), findsOneWidget);
  });

  testWidgets('reset restores the default month without dimensions', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await mountStats(
      tester,
      handler: (request) async {
        requests.add(request);
        return defaultApi(request);
      },
    );

    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-range-lastMonth')));
    await tester.tap(find.byKey(const ValueKey('stats-category-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-tag-1')));
    await tester.tap(find.byKey(const ValueKey('stats-filter-apply')));
    await tester.pumpAndSettle();
    expect(find.text('上月 · 餐饮美食 · 午餐'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-filter-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-filter-apply')));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final query = lastRangeRequest(requests).url.queryParameters;
    expect(query['start'], dateParam(DateTime(now.year, now.month)));
    expect(query['end'], dateParam(now));
    expect(query.containsKey('category_id'), isFalse);
    expect(query.containsKey('tag_id'), isFalse);
    expect(find.text('本月 · 全部维度'), findsOneWidget);
  });

  testWidgets('custom date picker cancel keeps the draft unchanged', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await mountStats(
      tester,
      handler: (request) async {
        requests.add(request);
        return defaultApi(request);
      },
    );
    final before = lastRangeRequest(requests).url.queryParameters;

    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-range-custom')));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-filter-apply')));
    await tester.pumpAndSettle();

    expect(lastRangeRequest(requests).url.queryParameters, before);
    expect(find.text('本月 · 全部维度'), findsOneWidget);
  });

  testWidgets('dimension filter replaces savings rate with count badge', (
    tester,
  ) async {
    await mountStats(tester);

    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-category-1')));
    await tester.tap(find.byKey(const ValueKey('stats-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('45 笔'), findsOneWidget);
    expect(find.textContaining('储蓄率'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-filter-reset')));
    await tester.tap(find.byKey(const ValueKey('stats-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.textContaining('储蓄率'), findsOneWidget);
    expect(find.text('45 笔'), findsNothing);
  });

  testWidgets('range failure clears old numbers and retry recovers', (
    tester,
  ) async {
    var fail = false;
    final controllers = await mountStats(
      tester,
      handler: (request) async {
        if (fail && request.url.path == '/api/stats/range') {
          return jsonResponse({'error': 'server error'}, status: 500);
        }
        return defaultApi(request);
      },
    );
    expect(find.text('¥9,551.50'), findsOneWidget);

    fail = true;
    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-range-lastMonth')));
    await tester.tap(find.byKey(const ValueKey('stats-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('¥9,551.50'), findsNothing);

    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('¥9,551.50'), findsOneWidget);
    expect(controllers.ledger.rangeStatsError, isNull);
  });

  testWidgets('metric cards share height across all four', (tester) async {
    await mountStats(tester);
    expectEqualMetricCards(tester);

    final noNote = rangeStatsJson(previousExpense: 0);
    await mountStats(
      tester,
      handler: (request) async {
        if (request.url.path == '/api/stats/range') {
          return jsonResponse(noNote);
        }
        return defaultApi(request);
      },
    );
    expectEqualMetricCards(tester);
  });

  testWidgets('chart card sizes to content without inner scrolling', (
    tester,
  ) async {
    final stats = rangeStatsJson(expense: 171);
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
    await mountStats(
      tester,
      handler: (request) async {
        if (request.url.path == '/api/stats/range') {
          return jsonResponse(stats);
        }
        return defaultApi(request);
      },
    );

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
    final empty = rangeStatsJson(
      expense: 0,
      income: 0,
      balance: 0,
      previousExpense: 0,
      previousIncome: 0,
      expenseCount: 0,
      incomeCount: 0,
    );
    empty['category_distribution'] = <Object?>[];
    empty['income_category_distribution'] = <Object?>[];
    empty['payment_distribution'] = <Object?>[];
    empty['income_payment_distribution'] = <Object?>[];
    empty['monthly_trends'] = <Object?>[];
    await mountStats(
      tester,
      handler: (request) async {
        if (request.url.path == '/api/stats/range') {
          return jsonResponse(empty);
        }
        return defaultApi(request);
      },
    );

    expect(find.text('暂无分类支出'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('暂无渠道支出'), findsOneWidget);
    expect(find.textContaining('储蓄率'), findsNothing);
  });

  testWidgets('stats filter fits 320dp with 2x text', (tester) async {
    await mountStats(
      tester,
      size: const Size(320, 800),
      textScaler: const TextScaler.linear(2),
    );

    await tester.tap(find.byKey(const ValueKey('stats-filter')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('stats-range-lastMonth')),
    );
    await tester.tap(find.byKey(const ValueKey('stats-range-lastMonth')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-filter-apply')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stats-view-income')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('stats-view-income')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('收入构成'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('收入构成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
