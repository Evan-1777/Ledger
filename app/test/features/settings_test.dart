import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_app/core/widgets/ledger_widgets.dart';
import 'package:ledger_app/features/auth/session_controller.dart';
import 'package:ledger_app/features/settings/settings_screen.dart';

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

  testWidgets('categories show editable rows and a protected system panel', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.categories,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
    );

    expect(find.byType(LedgerSliverAppBar), findsOneWidget);
    expect(find.text('餐饮美食'), findsOneWidget);
    expect(find.text('交通出行'), findsOneWidget);
    expect(find.byTooltip('分类操作'), findsNWidgets(2));
    expect(find.text('债务偿还'), findsOneWidget);
    expect(find.text('账户转账'), findsOneWidget);
    expect(find.text('系统 · 只读'), findsNWidgets(2));
    expect(find.byTooltip('分类操作'), findsNWidgets(2));
    expect(popupClip(tester, find.byTooltip('分类操作').first), Clip.antiAlias);
  });

  testWidgets('category segment switches between expense and income', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.categories,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
    );

    await tester.tap(find.text('收入分类'));
    await tester.pumpAndSettle();

    expect(find.text('职业收入'), findsOneWidget);
    expect(find.text('餐饮美食'), findsNothing);
  });

  testWidgets('section switch reports the selected section', (tester) async {
    var selected = SettingsSection.categories;
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: selected,
        onSectionChanged: (value) => selected = value,
      ),
      controllers: controllers,
    );

    await tester.tap(find.text('渠道与账户'));
    await tester.pump();

    expect(selected, SettingsSection.channels);
  });

  testWidgets('channel section shows grouped accounts and credit limits', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.channels,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
    );

    expect(find.text('资产账户'), findsWidgets);
    expect(find.text('负债账户'), findsWidgets);
    expect(find.text('招商银行卡'), findsWidgets);
    expect(find.text('额度 ¥20,000.00'), findsOneWidget);
    expect(popupClip(tester, find.byTooltip('账户操作').first), Clip.antiAlias);
  });

  testWidgets('deleting a referenced category shows the 409 message', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler((request) async {
      if (request.method == 'DELETE' &&
          request.url.path.startsWith('/api/categories/')) {
        return jsonResponse({'error': '该消费类型已有关联账单，禁止删除'}, status: 409);
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.categories,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
    );

    await tester.tap(find.byTooltip('分类操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('该消费类型已有关联账单，禁止删除'), findsOneWidget);
  });

  testWidgets('tag sheet menu clips its content', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.categories,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
    );

    await tester.tap(find.text('餐饮美食'));
    await tester.pumpAndSettle();

    expect(find.text('细分标签'), findsOneWidget);
    expect(popupClip(tester, find.byTooltip('标签操作').first), Clip.antiAlias);
  });

  testWidgets('category stats toggle writes and refreshes the row', (
    tester,
  ) async {
    var excluded = false;
    final puts = <http.Request>[];
    final controllers = await testControllersWithHandler((request) async {
      if (request.method == 'PUT' &&
          request.url.path.startsWith('/api/categories/')) {
        puts.add(request);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        excluded = body['exclude_from_stats'] == true;
        return jsonResponse({
          'id': 1,
          'name': '餐饮美食',
          'sort_order': 1,
          'type': 'expense',
          'exclude_from_stats': excluded,
          'created_at': '',
          'tags': <Object?>[],
        });
      }
      if (request.url.path == '/api/categories') {
        return jsonResponse([
          {
            'id': 1,
            'name': '餐饮美食',
            'sort_order': 1,
            'type': 'expense',
            'exclude_from_stats': excluded,
            'created_at': '',
            'tags': <Object?>[],
          },
        ]);
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.categories,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
    );

    expect(find.text('0 个细分标签'), findsOneWidget);
    await tester.tap(find.byTooltip('分类操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不计入收支统计'));
    await tester.pumpAndSettle();

    expect(puts.length, 1);
    expect(
      (jsonDecode(puts.single.body)
          as Map<String, dynamic>)['exclude_from_stats'],
      isTrue,
    );
    expect(find.text('0 个细分标签 · 不计入统计'), findsOneWidget);
    expect(find.text('已设为不计入收支统计'), findsOneWidget);

    await tester.tap(find.byTooltip('分类操作'));
    await tester.pumpAndSettle();
    expect(find.text('计入收支统计'), findsOneWidget);
    await tester.tap(find.text('计入收支统计'));
    await tester.pumpAndSettle();

    expect(puts.length, 2);
    expect(
      (jsonDecode(puts.last.body)
          as Map<String, dynamic>)['exclude_from_stats'],
      isFalse,
    );
    expect(find.text('0 个细分标签'), findsOneWidget);
  });

  testWidgets('category stats toggle failure shows the server message', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler((request) async {
      if (request.method == 'PUT' &&
          request.url.path.startsWith('/api/categories/')) {
        return jsonResponse({'error': 'server error'}, status: 500);
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.categories,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
    );

    await tester.tap(find.byTooltip('分类操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('不计入收支统计'));
    await tester.pumpAndSettle();

    expect(find.text('server error'), findsOneWidget);
  });

  testWidgets('theme changes persist through the preferences controller', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.categories,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
    );

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(controllers.preferences.themeMode, ThemeMode.dark);
  });

  testWidgets('changing server clears the token and returns to lock', (
    tester,
  ) async {
    final controllers = await testControllersWithHandler(
      defaultApi,
      token: 'token',
    );
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.categories,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
    );

    await tester.ensureVisible(find.text('服务器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('服务器'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'https://other.example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(controllers.store.serverUrl, 'https://other.example.com');
    expect(await controllers.store.readToken(), isNull);
    expect(controllers.session.phase, SessionPhase.locked);
  });

  testWidgets('logout clears the token after confirmation', (tester) async {
    final controllers = await testControllersWithHandler(
      defaultApi,
      token: 'token',
    );
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.categories,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
    );

    await tester.ensureVisible(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出'));
    await tester.pumpAndSettle();

    expect(await controllers.store.readToken(), isNull);
    expect(controllers.session.phase, SessionPhase.locked);
  });

  testWidgets('settings fit 320dp with 2x text', (tester) async {
    final controllers = await testControllersWithHandler(defaultApi);
    await controllers.ledger.loadAll();
    await pumpWithProviders(
      tester,
      home: SettingsScreen(
        section: SettingsSection.categories,
        onSectionChanged: (_) {},
      ),
      controllers: controllers,
      size: const Size(320, 800),
      textScaler: const TextScaler.linear(2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
