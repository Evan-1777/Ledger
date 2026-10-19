import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/features/assets/assets_screen.dart';

import '../support/harness.dart';

void main() {
  setUpAll(initTestLocale);

  testWidgets('assets page hides and reveals amounts', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: AssetsScreen(onManage: () {}),
      controllers: controllers,
    );

    expect(find.text('73,520.00'), findsOneWidget);
    await tester.tap(find.byTooltip('隐藏金额'));
    await tester.pump();
    expect(find.text('••••'), findsWidgets);
    expect(find.text('73,520.00'), findsNothing);

    await tester.tap(find.byTooltip('显示金额'));
    await tester.pump();
    expect(find.text('73,520.00'), findsOneWidget);
    expect(controllers.preferences.hideAmounts, isFalse);
  });

  testWidgets('manage button opens channel settings', (tester) async {
    var managed = 0;
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: AssetsScreen(onManage: () => managed++),
      controllers: controllers,
    );

    await tester.tap(find.text('管理').first);
    await tester.pump();

    expect(managed, 1);
  });

  testWidgets('distribution bar keeps a positive flex for tiny balances', (
    tester,
  ) async {
    final stats = statsJson();
    stats['asset_summary'] = {
      'total_assets': 1.0,
      'total_liabilities': 0.0,
      'net_assets': 1.0,
      'asset_channels': [
        {
          'id': 1,
          'name': '主要账户',
          'remaining_balance': 0.9996,
          'initial_balance': 0.9996,
          'percentage': 99.96,
        },
        {
          'id': 2,
          'name': '微量账户',
          'remaining_balance': 0.0004,
          'initial_balance': 0.0004,
          'percentage': 0.04,
        },
      ],
      'liability_channels': <Object?>[],
    };
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/stats/summary') {
        return jsonResponse(stats);
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: AssetsScreen(onManage: () {}),
      controllers: controllers,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('assets fit 320dp with 2x text', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: AssetsScreen(onManage: () {}),
      controllers: controllers,
      size: const Size(320, 800),
      textScaler: const TextScaler.linear(2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
