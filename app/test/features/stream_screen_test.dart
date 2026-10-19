import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_app/features/stream/stream_screen.dart';

import '../support/harness.dart';

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

    expect(find.text('本月结余'), findsOneWidget);
    expect(find.text('¥9,551.50'), findsOneWidget);
    expect(find.text('午餐 · 牛肉面'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('转账'), findsOneWidget);
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

    expect(tester.takeException(), isNull);
  });
}
