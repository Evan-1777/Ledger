import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_app/core/api/models.dart';
import 'package:ledger_app/features/record/record_sheet.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  setUpAll(initTestLocale);

  Future<void> openSheet(
    WidgetTester tester,
    TestControllers controllers, {
    Transaction? initial,
  }) async {
    await pumpWithProviders(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => RecordSheet.show(context, initial: initial),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      controllers: controllers,
      scaffold: false,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('record sheet validates the amount', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await openSheet(tester, controllers);

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('请输入大于 0 的金额'), findsOneWidget);
  });

  testWidgets('expense creation posts a signed amount and closes', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final controllers = await testControllersWithHandler((request) async {
      requests.add(request);
      if (request.method == 'POST' && request.url.path == '/api/transactions') {
        return jsonResponse(transactionJson());
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await openSheet(tester, controllers);

    await tester.enterText(find.byType(TextField).at(0), '128');
    await tester.enterText(find.byType(TextField).at(1), '午餐 · 牛肉面');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final post = requests.lastWhere(
      (request) =>
          request.method == 'POST' && request.url.path == '/api/transactions',
    );
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['type'], 'expense');
    expect(body['amount'], -128);
    expect(body['description'], '午餐 · 牛肉面');
    expect(body['payment_method_id'], 1);
    expect(body['category_id'], 1);
    expect(body['tag_id'], 1);
    expect(body['transacted_at'], endsWith('Z'));
    expect(body.containsKey('fee'), isFalse);
    expect(find.text('记账成功'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
  });

  testWidgets('transfer uses two distinct asset channels and fee', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final controllers = await testControllersWithHandler((request) async {
      requests.add(request);
      if (request.method == 'POST' && request.url.path == '/api/transactions') {
        return jsonResponse(transactionJson(type: 'transfer'));
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await openSheet(tester, controllers);

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '100');
    await tester.enterText(find.byType(TextField).at(1), '资金归集');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final post = requests.lastWhere(
      (request) =>
          request.method == 'POST' && request.url.path == '/api/transactions',
    );
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['type'], 'transfer');
    expect(body['source_payment_method_id'], 2);
    expect(body['payment_method_id'], 1);
    expect(body['fee'], 0);
    expect(body['source_payment_method_id'], isNot(body['payment_method_id']));
  });

  testWidgets('repayment targets a liability and omits the source', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final controllers = await testControllersWithHandler((request) async {
      requests.add(request);
      if (request.method == 'POST' && request.url.path == '/api/transactions') {
        return jsonResponse(
          transactionJson(type: 'repayment', amountCents: 50000),
        );
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await openSheet(tester, controllers);

    await tester.tap(find.text('还款'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '500');
    await tester.enterText(find.byType(TextField).at(1), '信用卡还款');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final post = requests.lastWhere(
      (request) =>
          request.method == 'POST' && request.url.path == '/api/transactions',
    );
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['type'], 'repayment');
    expect(body['payment_method_id'], 5);
    expect(body.containsKey('source_payment_method_id'), isFalse);
    expect(body.containsKey('fee'), isFalse);
    expect(body['category_id'], 8);
    expect(body['tag_id'], 8);
  });

  testWidgets('editing locks the transaction type', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await openSheet(tester, controllers, initial: transactionModel());

    final segmented = tester.widget<SegmentedButton<TransactionType>>(
      find.byType(SegmentedButton<TransactionType>),
    );
    expect(segmented.onSelectionChanged, isNull);
    expect(find.text('账单修改成功'), findsNothing);
    expect(find.text('午餐 · 牛肉面'), findsOneWidget);
  });

  testWidgets('record sheet adopts config that arrives after opening', (
    tester,
  ) async {
    var configured = false;
    final controllers = await testControllersWithHandler((request) async {
      if (!configured &&
          (request.url.path == '/api/categories' ||
              request.url.path == '/api/payment-methods')) {
        return jsonResponse([]);
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await openSheet(tester, controllers);

    expect(find.text('暂无可用渠道，请先在设置中添加'), findsOneWidget);

    configured = true;
    await controllers.ledger.loadConfig();
    await tester.pumpAndSettle();

    expect(find.text('暂无可用渠道，请先在设置中添加'), findsNothing);
    expect(find.text('招商银行卡'), findsWidgets);
    expect(find.text('餐饮美食 · 午餐'), findsOneWidget);
  });

  testWidgets('record sheet fits 320dp with 2x text', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => RecordSheet.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      controllers: controllers,
      scaffold: false,
      size: const Size(320, 800),
      textScaler: const TextScaler.linear(2),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
