import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/features/shell/app_shell.dart';

import '../support/harness.dart';

void main() {
  setUpAll(initTestLocale);

  testWidgets('shell navigates between five sections and opens recording', (
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
    expect(find.text('订阅'), findsWidgets);
    expect(find.text('资产'), findsWidgets);
    expect(find.text('设置'), findsWidgets);

    await tester.tap(find.text('订阅').last);
    await tester.pumpAndSettle();
    expect(find.text('每月固定开支'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('本月结余'), findsOneWidget);

    await tester.tap(find.text('资产').last);
    await tester.pumpAndSettle();
    expect(find.text('净资产'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('本月结余'), findsOneWidget);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('偏好与服务'), findsOneWidget);
    expect(find.text('支出分类'), findsOneWidget);

    await tester.tap(find.text('资产').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理').first);
    await tester.pumpAndSettle();
    expect(find.text('渠道与账户'), findsOneWidget);
    expect(find.text('招商银行卡'), findsOneWidget);

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

  testWidgets('refresh failure with cached data shows one snackbar', (
    tester,
  ) async {
    var fail = false;
    final controllers = await testControllersWithHandler((request) async {
      if (fail) {
        return jsonResponse({'error': 'offline'}, status: 500);
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const AppShell(),
      controllers: controllers,
      scaffold: false,
    );

    fail = true;
    await controllers.ledger.loadAll();
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('offline'), findsOneWidget);
    expect(find.text('本月结余'), findsOneWidget);
  });

  testWidgets('system back closes the record sheet before the shell', (
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

    await tester.tap(find.widgetWithText(FloatingActionButton, '记一笔'));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('保存'), findsNothing);
    expect(find.text('本月结余'), findsOneWidget);
  });

  testWidgets('shell fits landscape', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: const AppShell(),
      controllers: controllers,
      scaffold: false,
      size: const Size(640, 360),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
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
