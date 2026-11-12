import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_app/core/api/models.dart';
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

  Future<void> openFilter(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('stream-filter-menu')));
    await tester.pumpAndSettle();
  }

  Color filterButtonColor(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const ValueKey('stream-filter-menu')),
        matching: find.byType(Container),
      ),
    );
    return (container.decoration as BoxDecoration).color!;
  }

  ColorScheme schemeOf(WidgetTester tester) => Theme.of(
    tester.element(find.byKey(const ValueKey('stream-filter-menu'))),
  ).colorScheme;

  testWidgets('stream shows headline, day group and filter entry', (
    tester,
  ) async {
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
    expect(find.byKey(const ValueKey('stream-filter-menu')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('stream-filter-menu'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(filterButtonColor(tester), schemeOf(tester).surfaceContainerHigh);

    await openFilter(tester);
    for (final type in ['all', 'expense', 'income', 'transfer', 'repayment']) {
      expect(find.byKey(ValueKey('stream-filter-type-$type')), findsOneWidget);
    }
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('stream-filter-type-all')),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets(
    'filter apply sends the matching query and highlights the entry',
    (tester) async {
      final requests = <http.Request>[];
      final controllers = await testControllersWithHandler((request) async {
        if (request.url.path == '/api/transactions') requests.add(request);
        return defaultApi(request);
      });
      await controllers.ledger.loadAll();
      await pumpWithProviders(
        tester,
        home: const StreamScreen(),
        controllers: controllers,
      );
      final baseline = requests.length;

      await openFilter(tester);
      await tester.tap(
        find.byKey(const ValueKey('stream-filter-type-expense')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stream-filter-apply')));
      await tester.pumpAndSettle();

      final applied = requests.skip(baseline).toList();
      expect(applied.length, 1);
      expect(applied.single.url.queryParameters, {
        'limit': '100',
        'type': 'expense',
      });
      expect(find.text('支出'), findsWidgets);
      expect(filterButtonColor(tester), schemeOf(tester).secondaryContainer);
    },
  );

  testWidgets(
    'applying every dimension sends one request and shows the summary',
    (tester) async {
      final requests = <http.Request>[];
      final controllers = await testControllersWithHandler((request) async {
        if (request.url.path == '/api/transactions') requests.add(request);
        return defaultApi(request);
      });
      await controllers.ledger.loadAll();
      await pumpWithProviders(
        tester,
        home: const StreamScreen(),
        controllers: controllers,
      );
      final baseline = requests.length;

      await openFilter(tester);
      await tester.tap(
        find.byKey(const ValueKey('stream-filter-type-expense')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stream-filter-category-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stream-filter-tag-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stream-filter-channel-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stream-filter-apply')));
      await tester.pumpAndSettle();

      final applied = requests.skip(baseline).toList();
      expect(applied.length, 1);
      expect(applied.single.url.queryParameters, {
        'limit': '100',
        'type': 'expense',
        'category_id': '1',
        'tag_id': '1',
        'payment_method_id': '1',
      });
      expect(find.text('支出 · 餐饮美食 · 午餐 · 招商银行卡'), findsOneWidget);
    },
  );

  testWidgets('filter sheet converges categories and tags with the type', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    await openFilter(tester);
    expect(
      find.byKey(const ValueKey('stream-filter-type-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stream-filter-category-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stream-filter-channel-all')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('stream-filter-tag-all')), findsNothing);
    expect(find.text('选择分类后可筛选标签'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stream-filter-category-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stream-filter-tag-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('stream-filter-tag-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stream-filter-type-transfer')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('stream-filter-category-all')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('stream-filter-tag-all')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stream-filter-type-expense')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('stream-filter-category-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stream-filter-category-4')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('stream-filter-type-income')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('stream-filter-category-4')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stream-filter-category-1')),
      findsNothing,
    );
  });

  testWidgets('filter groups align with the sheet title and footer', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    await openFilter(tester);
    expect(tester.getTopLeft(find.text('筛选')).dx, closeTo(20, 0.5));
    expect(tester.getTopLeft(find.text('类型')).dx, closeTo(20, 0.5));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('stream-filter-type-all')))
          .dx,
      closeTo(20, 0.5),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('stream-filter-reset'))).dx,
      closeTo(20, 0.5),
    );
  });

  testWidgets('reset clears dimensions but keeps the keyword', (tester) async {
    final requests = <http.Request>[];
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/transactions') requests.add(request);
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    await tester.tap(find.byKey(const ValueKey('stream-search-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('stream-search-field')),
      '午',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // Apply a dimension first so reset has something to clear.
    await openFilter(tester);
    await tester.tap(find.byKey(const ValueKey('stream-filter-type-expense')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stream-filter-apply')));
    await tester.pumpAndSettle();
    final baseline = requests.length;

    await openFilter(tester);
    await tester.tap(find.byKey(const ValueKey('stream-filter-reset')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('stream-filter-type-all')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('stream-filter-category-all')),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('stream-filter-apply')));
    await tester.pumpAndSettle();

    final applied = requests.skip(baseline).toList();
    expect(applied.length, 1);
    expect(applied.single.url.queryParameters, {'limit': '100', 'q': '午'});
  });

  testWidgets('search debounces to the last keyword and collapses', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/transactions') requests.add(request);
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );
    final baseline = requests.length;

    await tester.tap(find.byKey(const ValueKey('stream-search-toggle')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('stream-search-field'));
    expect(field, findsOneWidget);

    await tester.enterText(field, '拼');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, '拼多');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, '拼多多');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    final searched = requests
        .skip(baseline)
        .where((request) => request.url.queryParameters.containsKey('q'))
        .toList();
    expect(searched.length, 1);
    expect(searched.single.url.queryParameters['q'], '拼多多');

    await tester.tap(find.byKey(const ValueKey('stream-search-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stream-search-field')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stream-search-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stream-search-field')), findsNothing);
    expect(find.text(formatMonth(DateTime.now())), findsOneWidget);
  });

  testWidgets('clearing within the debounce window drops the pending keyword', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/transactions') requests.add(request);
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );
    final baseline = requests.length;

    await tester.tap(find.byKey(const ValueKey('stream-search-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('stream-search-field')),
      '拼多多',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('stream-search-clear')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      requests
          .skip(baseline)
          .where((request) => request.url.queryParameters['q'] == '拼多多'),
      isEmpty,
    );
  });

  testWidgets('an active query shows the filtered empty state', (tester) async {
    final controllers = await testControllersWithHandler(
      (request) => defaultApi(request, transactions: []),
    );
    await controllers.ledger.loadAll();
    await controllers.ledger.setQuery(
      const TransactionQuery(type: TransactionType.expense),
    );
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    expect(find.text('没有符合条件的账单'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '记一笔'), findsNothing);
  });

  testWidgets('row keeps the channel note visible and wraps a long meta', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler((request) {
      if (request.url.path == '/api/transactions') {
        return Future.value(
          jsonResponse([
            transactionJson(
              id: 1,
              categoryName: '一个非常非常长的分类名称用来测试折行行为',
              tagName: '一个同样非常长的标签名称测试折行',
              paymentMethodName: '招商银行卡',
            ),
          ]),
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

    final note = find.byKey(const ValueKey('stream-row-note-1'));
    expect(note, findsOneWidget);
    expect(tester.widget<Text>(note).data, '招商银行卡');
    final row = tester.getRect(find.byKey(const ValueKey('stream-row-1')));
    expect(tester.getRect(note).right, lessThanOrEqualTo(row.right + 0.5));

    final meta = tester.widget<Text>(
      find.byKey(const ValueKey('stream-row-meta-1')),
    );
    expect(meta.maxLines, 2);
    expect(tester.takeException(), isNull);
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

  testWidgets('refunded row shows its badge and cancels refund in one tap', (
    tester,
  ) async {
    final refundRequests = <http.Request>[];
    final refunded = transactionJson(refundedAt: '2026-10-19T05:00:00Z');
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/transactions/1/refund') {
        refundRequests.add(request);
        return jsonResponse(transactionJson());
      }
      return defaultApi(request, transactions: [refunded]);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    expect(find.byKey(const ValueKey('stream-row-refunded-1')), findsOneWidget);
    expect(find.text('已退款'), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('取消退款'), findsOneWidget);
    await tester.tap(find.text('取消退款'));
    await tester.pumpAndSettle();

    expect(refundRequests.length, 1);
    expect(refundRequests.single.method, 'DELETE');
    expect(refundRequests.single.url.path, '/api/transactions/1/refund');
    expect(find.text('已撤销退款'), findsOneWidget);
  });

  testWidgets('refunding a row sends one request and reports success', (
    tester,
  ) async {
    final refunds = <http.Request>[];
    final controllers = await testControllersWithHandler((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/api/transactions/1/refund') {
        refunds.add(request);
        return jsonResponse(
          transactionJson(refundedAt: '2026-10-19T05:00:00Z'),
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

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退款'));
    await tester.pumpAndSettle();

    expect(refunds.length, 1);
    expect(refunds.single.method, 'POST');
    expect(refunds.single.url.path, '/api/transactions/1/refund');
    expect(find.text('已标记退款'), findsOneWidget);
  });

  testWidgets('transfer rows offer no refund entry', (tester) async {
    final transfer = transactionJson(
      type: 'transfer',
      amountCents: 10000,
      paymentMethodName: '支付宝',
      sourcePaymentMethodName: '招商银行卡',
    );
    final controllers = await testControllersWithHandler(
      (request) => defaultApi(request, transactions: [transfer]),
    );
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
    );

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.text('退款'), findsNothing);
    expect(find.text('取消退款'), findsNothing);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets(
    '320dp with 2x text opens the filter and reaches the apply button',
    (tester) async {
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

      await tester.ensureVisible(
        find.byKey(const ValueKey('stream-filter-menu')),
      );
      await tester.pumpAndSettle();
      await openFilter(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('stream-filter-type-expense')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('stream-filter-menu'))).height,
        greaterThanOrEqualTo(48),
      );
      final sheetScrollable = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      await tester.drag(sheetScrollable.first, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stream-filter-apply')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dark theme renders the filtered stream without errors', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await controllers.ledger.setQuery(
      const TransactionQuery(type: TransactionType.expense, paymentMethodId: 1),
    );
    await pumpWithProviders(
      tester,
      home: const StreamScreen(),
      controllers: controllers,
      themeMode: ThemeMode.dark,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('支出 · 招商银行卡'), findsOneWidget);
  });
}
