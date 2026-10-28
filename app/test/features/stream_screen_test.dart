import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_app/core/format/dates.dart';
import 'package:ledger_app/core/widgets/ledger_widgets.dart';
import 'package:ledger_app/features/stream/stream_screen.dart';

import '../support/harness.dart';

Clip popupClip(WidgetTester tester, Finder finder) {
  final ancestor = find.ancestor(
    of: finder,
    matching: find.byWidgetPredicate((widget) => widget is PopupMenuButton),
  );
  final target = ancestor.evaluate().isEmpty ? finder : ancestor.first;
  return tester.widget<PopupMenuButton<dynamic>>(target).clipBehavior;
}

void main() {
  setUpAll(initTestLocale);

  testWidgets('stream shows headline, day group and filters', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    expect(find.byType(LedgerSliverAppBar), findsOneWidget);
    expect(find.text('本月结余'), findsOneWidget);
    expect(find.text('¥9,551.50'), findsOneWidget);
    expect(find.text('午餐 · 牛肉面'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(
      popupClip(tester, find.byKey(const ValueKey('filter-menu'))),
      Clip.antiAlias,
    );

    await tester.tap(find.byKey(const ValueKey('filter-menu')));
    await tester.pumpAndSettle();
    for (final filter in [
      'all',
      'expense',
      'income',
      'transfer',
      'repayment',
    ]) {
      expect(find.byKey(ValueKey('filter-$filter')), findsOneWidget);
    }
  });

  testWidgets('filter tap requests the matching type', (tester) async {
    final requests = <http.Request>[];
    final controllers = await testControllersWithHandler((request) async {
      requests.add(request);
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    await tester.tap(find.byKey(const ValueKey('filter-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-expense')));
    await tester.pumpAndSettle();

    expect(
      requests.any(
        (request) =>
            request.url.path == '/api/transactions' &&
            request.url.queryParameters['type'] == 'expense',
      ),
      isTrue,
    );
  });

  testWidgets(
    'filter menu exposes options and keeps the current label visible',
    (tester) async {
      final controllers = await testControllersWithHandler(defaultApi);
      await controllers.ledger.loadAll();
      await pumpWithProviders(
        tester,
        home: const StreamScreen(),
        controllers: controllers,
      );

      final trigger = find.byKey(const ValueKey('filter-menu'));
      expect(
        find.descendant(of: trigger, matching: find.text('全部')),
        findsOneWidget,
      );
      expect(tester.getSize(trigger).height, greaterThanOrEqualTo(48));

      await tester.tap(trigger);
      await tester.pumpAndSettle();
      for (final filter in [
        'all',
        'expense',
        'income',
        'transfer',
        'repayment',
      ]) {
        expect(find.byKey(ValueKey('filter-$filter')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('filter-expense')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: trigger, matching: find.text('支出')),
        findsOneWidget,
      );

      final hero = tester.getRect(
        find
            .ancestor(of: find.text('本月结余'), matching: find.byType(Container))
            .first,
      );
      final firstGroup = tester.getRect(
        find
            .ancestor(
              of: find.text('午餐 · 牛肉面'),
              matching: find.byType(LedgerCard),
            )
            .first,
      );
      final month = tester.getRect(find.text(formatMonth(DateTime.now())));
      expect(month.top, greaterThanOrEqualTo(hero.bottom));
      expect(month.bottom, lessThanOrEqualTo(firstGroup.top));
    },
  );

  testWidgets('empty stream offers the record action', (tester) async {
    final controllers = await testControllersWithHandler(
      (request) => defaultApi(request, transactions: []),
    );
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    expect(find.text('本月还没有记账'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '记一笔'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation and sends one request', (
    tester,
  ) async {
    final deletes = <http.Request>[];
    final controllers = await testControllersWithHandler((request) async {
      if (request.method == 'DELETE') deletes.add(request);
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    expect(popupClip(tester, find.byTooltip('更多操作')), Clip.antiAlias);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除账单'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(deletes, isEmpty);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(deletes.length, 1);
    expect(find.text('账单已删除'), findsOneWidget);
  });

  testWidgets('excluded categories leave the day subtotal but keep rows', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/categories') {
        return jsonResponse([
          {
            'id': 1,
            'name': '餐饮美食',
            'sort_order': 1,
            'type': 'expense',
            'exclude_from_stats': true,
            'created_at': '',
            'tags': [
              {'id': 1, 'category_id': 1, 'name': '午餐', 'sort_order': 1},
            ],
          },
          {
            'id': 2,
            'name': '交通出行',
            'sort_order': 2,
            'type': 'expense',
            'exclude_from_stats': false,
            'created_at': '',
            'tags': [
              {'id': 2, 'category_id': 2, 'name': '地铁', 'sort_order': 1},
            ],
          },
        ]);
      }
      if (request.url.path == '/api/transactions') {
        return jsonResponse([
          transactionJson(id: 1, amountCents: -2800),
          transactionJson(
            id: 2,
            amountCents: -1000,
            description: '地铁通勤',
            categoryId: 2,
            categoryName: '交通出行',
            tagId: 2,
            tagName: '地铁',
          ),
        ]);
      }
      if (request.url.path == '/api/stats/summary') {
        return jsonResponse(
          statsJson(monthExpense: 10, monthIncome: 0, monthBalance: -10),
        );
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    expect(find.text('支出 ¥10.00'), findsOneWidget);
    expect(find.text('¥10.00'), findsOneWidget);
    expect(find.text('午餐 · 牛肉面'), findsOneWidget);
    expect(find.text('地铁通勤'), findsOneWidget);
  });

  testWidgets('stream fits 320dp with 2x text', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
      size: const Size(320, 800),
      textScaler: const TextScaler.linear(2),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('filter-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-menu')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('filter-expense')), findsOneWidget);
  });
}
