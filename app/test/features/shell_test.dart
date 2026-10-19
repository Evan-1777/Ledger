import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/features/shell/app_shell.dart';

import '../support/harness.dart';

void main() {
  setUpAll(initTestLocale);

  testWidgets('shell navigates between four sections and opens recording', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const AppShell(),
      controllers: controllers,
      scaffold: false,
    );

    expect(find.text('流水'), findsWidgets);
    expect(find.text('统计'), findsWidgets);
    expect(find.text('资产'), findsWidgets);
    expect(find.text('设置'), findsWidgets);

    await tester.tap(find.text('资产').last);
    await tester.pumpAndSettle();
    expect(find.text('净资产'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('本月结余'), findsOneWidget);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('偏好与服务'), findsOneWidget);

    await tester.tap(find.text('流水').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, '记一笔'));
    await tester.pumpAndSettle();
    expect(find.text('金额'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsNothing);
  });

  testWidgets('shell fits 320dp with 2x text', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const AppShell(),
      controllers: controllers,
      scaffold: false,
      size: const Size(320, 800),
      textScaler: const TextScaler.linear(2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
