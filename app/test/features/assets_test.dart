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
