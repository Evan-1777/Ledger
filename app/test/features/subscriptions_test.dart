import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_app/core/widgets/ledger_widgets.dart';
import 'package:ledger_app/features/shell/app_shell.dart';
import 'package:ledger_app/features/subscriptions/subscriptions_screen.dart';

import '../support/harness.dart';

/// 局部有状态假服务：订阅页用例需要变更后列表真的变化。
class _FakeSubscriptionServer {
  _FakeSubscriptionServer({
    List<Map<String, Object?>>? groups,
    List<Map<String, Object?>>? subscriptions,
  }) : groups =
           groups ??
           [
             subscriptionGroupJson(id: 1, name: '影音娱乐', sortOrder: 1),
             subscriptionGroupJson(id: 2, name: '工具软件', sortOrder: 2),
           ],
       subscriptions =
           subscriptions ??
           [
             subscriptionJson(
               id: 1,
               groupId: 1,
               name: 'Netflix',
               amountCents: 7500,
               billingDay: DateTime.now().day,
             ),
             subscriptionJson(
               id: 2,
               groupId: 1,
               name: 'iCloud',
               amountCents: 600,
               billingDay: 30,
               status: 'paused',
             ),
             subscriptionJson(
               id: 3,
               groupId: null,
               name: 'Spotify',
               amountCents: 1200,
               billingDay: 12,
             ),
           ];

  final List<Map<String, Object?>> groups;
  final List<Map<String, Object?>> subscriptions;
  final List<http.Request> requests = [];
  bool failGroups = false;
  bool failSubscriptions = false;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;

    if (request.method == 'GET' && path == '/api/subscription-groups') {
      if (failGroups) return jsonResponse({'error': 'offline'}, status: 500);
      return jsonResponse(groups);
    }
    if (request.method == 'GET' && path == '/api/subscriptions') {
      if (failSubscriptions) {
        return jsonResponse({'error': 'offline'}, status: 500);
      }
      return jsonResponse(subscriptions);
    }
    if (request.method == 'POST' && path == '/api/subscription-groups') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final created = subscriptionGroupJson(
        id: _nextId(groups),
        name: body['name'] as String,
        sortOrder: body['sort_order'] as int,
      );
      groups.add(created);
      return jsonResponse(created);
    }
    if (path.startsWith('/api/subscription-groups/')) {
      final id = int.parse(request.url.pathSegments.last);
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final group = groups.firstWhere((item) => item['id'] == id);
        group['name'] = body['name'];
        group['sort_order'] = body['sort_order'];
        return jsonResponse(group);
      }
      if (request.method == 'DELETE') {
        groups.removeWhere((item) => item['id'] == id);
        for (final sub in subscriptions) {
          if (sub['group_id'] == id) sub['group_id'] = null;
        }
        return jsonResponse({'success': true});
      }
    }
    if (request.method == 'POST' && path == '/api/subscriptions') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final created = subscriptionJson(
        id: _nextId(subscriptions),
        groupId: body['group_id'] as int?,
        name: body['name'] as String,
        amountCents: ((body['amount'] as num) * 100).round(),
        billingDay: body['billing_day'] as int,
        status: body['status'] as String,
      );
      subscriptions.add(created);
      return jsonResponse(created);
    }
    if (path.startsWith('/api/subscriptions/')) {
      final id = int.parse(request.url.pathSegments.last);
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final sub = subscriptions.firstWhere((item) => item['id'] == id);
        sub['group_id'] = body['group_id'];
        sub['name'] = body['name'];
        sub['amount_cents'] = ((body['amount'] as num) * 100).round();
        sub['amount'] = (body['amount'] as num).toDouble();
        sub['billing_day'] = body['billing_day'];
        sub['status'] = body['status'];
        return jsonResponse(sub);
      }
      if (request.method == 'DELETE') {
        subscriptions.removeWhere((item) => item['id'] == id);
        return jsonResponse({'success': true});
      }
    }
    return jsonResponse({});
  }

  int _nextId(List<Map<String, Object?>> items) {
    var max = 0;
    for (final item in items) {
      final id = item['id'] as int;
      if (id > max) max = id;
    }
    return max + 1;
  }

  Iterable<http.Request> requestsFor(String method, String path) => requests
      .where((request) => request.method == method && request.url.path == path);
}

Future<TestControllers> _pumpSubscriptions(
  WidgetTester tester,
  _FakeSubscriptionServer server, {
  Size size = const Size(390, 844),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final controllers = await testControllersWithHandler(server.handle);
  await controllers.ledger.loadSubscriptions();
  await pumpWithProviders(
    tester,
    home: const SubscriptionsScreen(),
    controllers: controllers,
    size: size,
    textScaler: textScaler,
  );
  await tester.pumpAndSettle();
  return controllers;
}

/// Hero 月度金额；「未来 7 天」可能算出同一数值，不能按全文匹配。
String heroMonthly(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('subscriptions-hero-monthly')))
    .data!;

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestLocale);

  testWidgets('hero and sections count only active subscriptions', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    expect(heroMonthly(tester), '87.00');
    expect(find.text('1,044.00'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('subscription-amount-1')),
        matching: find.text('75.00'),
      ),
      findsOneWidget,
    );
    expect(find.text('共 2 项'), findsOneWidget);
    expect(find.text('共 1 项'), findsOneWidget);
    expect(find.text('75.00 / 月'), findsOneWidget);
    expect(find.text('iCloud'), findsOneWidget);
    expect(find.text('已暂停 · 原扣款日 30 日'), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);

    final groupTop = tester.getTopLeft(find.text('影音娱乐')).dy;
    final ungroupedTop = tester.getTopLeft(find.text('未分组')).dy;
    expect(ungroupedTop, greaterThan(groupTop));
  });

  testWidgets('status filter narrows rows without changing the hero', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    await tester.tap(find.byKey(const ValueKey('subscriptions-filter-paused')));
    await tester.pumpAndSettle();

    expect(find.text('iCloud'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
    expect(find.text('1 项已暂停'), findsOneWidget);
    expect(heroMonthly(tester), '87.00');
    expect(find.text('—'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subscriptions-filter-all')));
    await tester.pumpAndSettle();
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('共 2 项'), findsOneWidget);
    expect(find.text('共 1 项'), findsOneWidget);
  });

  testWidgets('an empty group keeps its add entry and preselects the group', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer(
      groups: [
        subscriptionGroupJson(id: 1, name: '影音娱乐', sortOrder: 1),
        subscriptionGroupJson(id: 2, name: '工具软件', sortOrder: 2),
        subscriptionGroupJson(id: 3, name: '空组', sortOrder: 3),
      ],
    );
    await _pumpSubscriptions(tester, server);

    final add = find.byKey(const ValueKey('subscriptions-empty-add-3'));
    await scrollTo(tester, add);
    expect(find.text('暂无订阅'), findsWidgets);

    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('subscription-save')), findsOneWidget);
    final field = tester.widget<DropdownButtonFormField<int>>(
      find.byKey(const ValueKey('subscription-group')),
    );
    expect(field.initialValue, 3);
  });

  testWidgets('the subscription form validates before posting', (tester) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    await tester.tap(find.byKey(const ValueKey('subscriptions-add')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('subscription-save')),
        matching: find.text('添加订阅'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('subscription-save')));
    await tester.pumpAndSettle();
    expect(find.text('请输入服务名称'), findsOneWidget);
    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('subscription-name')),
    );
    expect(nameField.decoration!.errorText, '请输入服务名称');
    expect(nameField.focusNode!.hasFocus, isTrue);

    await tester.enterText(
      find.byKey(const ValueKey('subscription-name')),
      'Netflix',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('subscription-name')))
          .decoration!
          .errorText,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('subscription-amount')),
      '0',
    );
    await tester.tap(find.byKey(const ValueKey('subscription-save')));
    await tester.pumpAndSettle();
    expect(find.text('金额需在 ¥0.01–¥1,000,000.00 之间'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('subscription-amount')),
      '10',
    );
    await tester.enterText(
      find.byKey(const ValueKey('subscription-day')),
      '32',
    );
    await tester.tap(find.byKey(const ValueKey('subscription-save')));
    await tester.pumpAndSettle();
    expect(find.text('扣款日需为 1–31 的整数'), findsOneWidget);
    expect(server.requestsFor('POST', '/api/subscriptions'), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('subscription-day')),
      '15',
    );
    await tester.tap(find.byKey(const ValueKey('subscription-save')));
    await tester.pumpAndSettle();

    final post = server.requestsFor('POST', '/api/subscriptions').single;
    expect(jsonDecode(post.body), {
      'name': 'Netflix',
      'group_id': null,
      'amount': 10,
      'billing_day': 15,
      'status': 'active',
    });
    expect(find.text('订阅已添加'), findsOneWidget);
  });

  testWidgets('the row menu pauses and resumes the subscription', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    await tester.tap(find.byKey(const ValueKey('subscription-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂停续费'));
    await tester.pumpAndSettle();

    final pause = server.requestsFor('PUT', '/api/subscriptions/1').single;
    final pauseBody = jsonDecode(pause.body) as Map<String, dynamic>;
    expect(pauseBody['status'], 'paused');
    expect(pauseBody['name'], 'Netflix');
    expect(find.text('已暂停续费'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subscription-menu-1')));
    await tester.pumpAndSettle();
    expect(find.text('恢复续费'), findsOneWidget);
    await tester.tap(find.text('恢复续费'));
    await tester.pumpAndSettle();

    expect(
      (jsonDecode(server.requestsFor('PUT', '/api/subscriptions/1').last.body)
          as Map<String, dynamic>)['status'],
      'active',
    );
    expect(find.text('已恢复续费'), findsOneWidget);
  });

  testWidgets('deleting a group asks for confirmation and keeps its rows', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    await tester.tap(find.byKey(const ValueKey('subscription-group-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分组'));
    await tester.pumpAndSettle();
    expect(find.text('「影音娱乐」内的 2 项订阅将移至未分组。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(server.requestsFor('DELETE', '/api/subscription-groups/1'), isEmpty);

    await tester.tap(find.byKey(const ValueKey('subscription-group-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(
      server.requestsFor('DELETE', '/api/subscription-groups/1'),
      hasLength(1),
    );
    expect(find.text('分组已删除，订阅已移至未分组'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('影音娱乐'), findsNothing);
    expect(find.text('未分组'), findsOneWidget);
  });

  testWidgets('editing prefills the row and preserves untouched fields', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);
    final today = DateTime.now().day;

    await tester.tap(find.byKey(const ValueKey('subscription-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    final name = tester.widget<TextField>(
      find.byKey(const ValueKey('subscription-name')),
    );
    final amount = tester.widget<TextField>(
      find.byKey(const ValueKey('subscription-amount')),
    );
    final day = tester.widget<TextField>(
      find.byKey(const ValueKey('subscription-day')),
    );
    final group = tester.widget<DropdownButtonFormField<int>>(
      find.byKey(const ValueKey('subscription-group')),
    );
    expect(name.controller!.text, 'Netflix');
    expect(amount.controller!.text, '75');
    expect(day.controller!.text, '$today');
    expect(group.initialValue, 1);

    await tester.enterText(
      find.byKey(const ValueKey('subscription-amount')),
      '80',
    );
    await tester.tap(find.byKey(const ValueKey('subscription-save')));
    await tester.pumpAndSettle();

    final put = server.requestsFor('PUT', '/api/subscriptions/1').single;
    expect(jsonDecode(put.body), {
      'name': 'Netflix',
      'group_id': 1,
      'amount': 80,
      'billing_day': today,
      'status': 'active',
    });
    expect(find.text('订阅已更新'), findsOneWidget);
  });

  testWidgets('renaming and moving groups send ordered PUT requests', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    await tester.tap(find.byKey(const ValueKey('subscription-group-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名分组'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('group-name')), '影音');
    await tester.tap(find.byKey(const ValueKey('group-save')));
    await tester.pumpAndSettle();

    final rename = server
        .requestsFor('PUT', '/api/subscription-groups/1')
        .single;
    expect(jsonDecode(rename.body), {'name': '影音', 'sort_order': 1});
    expect(find.text('分组已重命名'), findsOneWidget);

    final menu = find.byKey(const ValueKey('subscription-group-menu-2'));
    await scrollTo(tester, menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('上移'));
    await tester.pumpAndSettle();

    final puts = server.requestsFor('PUT', '/api/subscription-groups/2');
    expect(puts, hasLength(1));
    final groupPuts = server.requests
        .where(
          (request) =>
              request.method == 'PUT' &&
              request.url.path.startsWith('/api/subscription-groups/'),
        )
        .toList();
    expect(groupPuts.map((request) => request.url.pathSegments.last).toList(), [
      '1',
      '2',
      '1',
    ]);
    expect(find.text('分组顺序已更新'), findsOneWidget);
  });

  testWidgets('deleting a subscription confirms before sending', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    await tester.tap(find.byKey(const ValueKey('subscription-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('「Netflix」删除后不可恢复。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(server.requestsFor('DELETE', '/api/subscriptions/1'), isEmpty);

    await tester.tap(find.byKey(const ValueKey('subscription-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(server.requestsFor('DELETE', '/api/subscriptions/1'), hasLength(1));
    expect(find.text('订阅已删除'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
  });

  testWidgets('first load failure stays on the page, refresh failure toasts', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer()..failSubscriptions = true;
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path.startsWith('/api/subscription')) {
        return server.handle(request);
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
    await tester.tap(find.text('订阅').last);
    await tester.pumpAndSettle();

    expect(find.text('offline'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    server.failSubscriptions = false;
    await controllers.ledger.loadSubscriptions();
    await tester.pumpAndSettle();
    expect(find.text('每月固定开支'), findsOneWidget);

    server.failSubscriptions = true;
    await controllers.ledger.loadSubscriptions();
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('offline'), findsWidgets);
    expect(find.text('每月固定开支'), findsOneWidget);
  });

  testWidgets('five groups plus ungrouped render without color overflow', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer(
      groups: [
        for (var i = 1; i <= 5; i++)
          subscriptionGroupJson(id: i, name: '分组 $i', sortOrder: i),
      ],
      subscriptions: [
        for (var i = 1; i <= 5; i++)
          subscriptionJson(
            id: i,
            groupId: i,
            name: '服务 $i',
            amountCents: 100 * i,
            billingDay: i,
          ),
        subscriptionJson(
          id: 6,
          groupId: null,
          name: '未分组服务',
          amountCents: 600,
          billingDay: 6,
        ),
      ],
    );
    await _pumpSubscriptions(tester, server);

    expect(tester.takeException(), isNull);
    await scrollTo(tester, find.text('未分组'));
    expect(find.text('未分组服务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp with 2x text keeps the filters and hero in view', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer(
      groups: [
        subscriptionGroupJson(id: 1, name: '影音娱乐', sortOrder: 1),
        subscriptionGroupJson(id: 2, name: '工具软件', sortOrder: 2),
        subscriptionGroupJson(id: 3, name: '空组', sortOrder: 3),
      ],
    );
    await _pumpSubscriptions(
      tester,
      server,
      size: const Size(320, 800),
      textScaler: const TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
    for (final label in ['年度预估', '未来 7 天']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(800));
    }
    final addRect = tester.getRect(
      find.byKey(const ValueKey('subscriptions-add')),
    );
    expect(addRect.right, lessThanOrEqualTo(320));
    expect(addRect.top, greaterThanOrEqualTo(0));

    final filterAll = find.byKey(const ValueKey('subscriptions-filter-all'));
    await scrollTo(tester, filterAll);
    for (final name in ['all', 'active', 'paused']) {
      final rect = tester.getRect(
        find.byKey(ValueKey('subscriptions-filter-$name')),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.bottom, lessThanOrEqualTo(800));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'group headers follow the filter and pause subtotals go neutral',
    (tester) async {
      final server = _FakeSubscriptionServer(
        groups: [
          subscriptionGroupJson(id: 1, name: '影音娱乐', sortOrder: 1),
          subscriptionGroupJson(id: 2, name: '空组', sortOrder: 2),
          subscriptionGroupJson(id: 3, name: '纯暂停', sortOrder: 3),
        ],
        subscriptions: [
          subscriptionJson(
            id: 1,
            groupId: 1,
            name: 'Netflix',
            amountCents: 7500,
            billingDay: 5,
          ),
          subscriptionJson(
            id: 2,
            groupId: 1,
            name: 'iCloud',
            amountCents: 600,
            billingDay: 30,
            status: 'paused',
          ),
          subscriptionJson(
            id: 3,
            groupId: 3,
            name: '旧服务',
            amountCents: 3900,
            billingDay: 20,
            status: 'paused',
          ),
        ],
      );
      await _pumpSubscriptions(tester, server);

      expect(find.text('共 2 项'), findsOneWidget);
      expect(find.text('75.00 / 月'), findsOneWidget);
      expect(find.text('0.00 / 月'), findsNothing);
      expect(find.text('0 项使用中'), findsNothing);

      await scrollTo(tester, find.text('纯暂停'));
      expect(find.text('共 1 项'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('暂无订阅'), findsOneWidget);

      final pausedChip = find.byKey(
        const ValueKey('subscriptions-filter-paused'),
      );
      await scrollTo(tester, pausedChip);
      await tester.tap(pausedChip);
      await tester.pumpAndSettle();
      expect(find.text('1 项已暂停'), findsWidgets);
      expect(find.text('—'), findsWidgets);
      expect(find.text('75.00 / 月'), findsNothing);
      expect(find.text('空组'), findsNothing);

      await scrollTo(tester, find.text('纯暂停'));
      expect(find.text('1 项已暂停'), findsWidgets);
      expect(find.text('—'), findsWidgets);
    },
  );

  testWidgets('hero distribution bar is visible and labelled', (tester) async {
    final semantics = tester.ensureSemantics();
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    final bar = find.byKey(const ValueKey('subscriptions-distribution-bar'));
    expect(tester.getSize(bar).height, 7);
    expect(find.bySemanticsLabel('按分组划分的每月固定开支'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('hero leads the page and filter chips keep their width', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    final heroTop = tester.getTopLeft(find.text('每月固定开支')).dy;
    final addTop = tester
        .getTopLeft(find.byKey(const ValueKey('subscriptions-add')))
        .dy;
    final filterTop = tester
        .getTopLeft(find.byKey(const ValueKey('subscriptions-filter-all')))
        .dy;
    expect(addTop, greaterThan(heroTop));
    expect(filterTop, greaterThan(addTop));

    for (final name in ['all', 'active', 'paused']) {
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(ValueKey('subscriptions-filter-$name')),
            )
            .showCheckmark,
        isFalse,
      );
    }

    final activeChip = find.byKey(
      const ValueKey('subscriptions-filter-active'),
    );
    final before = tester.getRect(activeChip);
    await tester.tap(activeChip);
    await tester.pumpAndSettle();
    final after = tester.getRect(activeChip);
    expect(after.left, before.left);
    expect(after.width, before.width);
  });

  testWidgets('empty state sits in a card with a single CTA', (tester) async {
    final server = _FakeSubscriptionServer(groups: [], subscriptions: []);
    await _pumpSubscriptions(tester, server);

    expect(find.text('还没有订阅'), findsOneWidget);
    expect(find.text('添加第一个订阅'), findsNothing);
    expect(find.byKey(const ValueKey('subscriptions-add')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(EmptyState),
        matching: find.byType(LedgerCard),
      ),
      findsOneWidget,
    );
  });

  testWidgets('group and ungrouped headers align title, count and amount', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    expect(
      tester.getTopLeft(find.text('影音娱乐')).dx,
      tester.getTopLeft(find.text('未分组')).dx,
    );
    expect(
      tester.getTopLeft(find.text('共 2 项')).dx,
      tester.getTopLeft(find.text('共 1 项')).dx,
    );
    final grouped = tester.getRect(find.text('75.00 / 月'));
    final ungrouped = tester.getRect(find.text('12.00 / 月'));
    expect(grouped.right, moreOrLessEquals(ungrouped.right, epsilon: 0.5));
  });

  testWidgets('row copy uses the remaining width and keeps the date unbroken', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer(
      subscriptions: [
        subscriptionJson(
          id: 1,
          groupId: 1,
          name: 'Netflix',
          amountCents: 7500,
          billingDay: 15,
        ),
        subscriptionJson(
          id: 2,
          groupId: 1,
          name: 'iCloud',
          amountCents: 600,
          billingDay: 30,
          status: 'paused',
        ),
      ],
    );
    await _pumpSubscriptions(tester, server);

    final body = tester.getSize(
      find.byKey(const ValueKey('subscription-body-1')),
    );
    final amount = tester.getSize(
      find.byKey(const ValueKey('subscription-amount-1')),
    );
    expect(body.width, greaterThan(amount.width));

    final meta = tester.widget<Text>(find.textContaining('下次').first);
    expect(meta.data, contains('\u2060'));
    expect(meta.maxLines, 2);
    expect(find.text('已暂停 · 原扣款日 30 日'), findsOneWidget);
  });

  testWidgets('the subscription sheet sizes to its content', (tester) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    await tester.tap(find.byKey(const ValueKey('subscriptions-add')));
    await tester.pumpAndSettle();

    final sheet = tester.getSize(
      find.byKey(const ValueKey('subscription-sheet')),
    );
    expect(sheet.height, lessThan(590));
    expect(tester.takeException(), isNull);
  });

  testWidgets('creating from a filtered view returns to all', (tester) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    final pausedChip = find.byKey(
      const ValueKey('subscriptions-filter-paused'),
    );
    await tester.tap(pausedChip);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('subscriptions-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(pausedChip).selected, isTrue);

    await tester.tap(find.byKey(const ValueKey('subscriptions-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('subscription-name')),
      'Disney+',
    );
    await tester.enterText(
      find.byKey(const ValueKey('subscription-amount')),
      '9',
    );
    await tester.enterText(find.byKey(const ValueKey('subscription-day')), '5');
    await tester.tap(find.byKey(const ValueKey('subscription-save')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('subscriptions-filter-all')),
          )
          .selected,
      isTrue,
    );
    expect(find.text('Disney+'), findsOneWidget);
  });

  testWidgets('creating a group from a filtered view returns to all', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(tester, server);

    await tester.tap(find.byKey(const ValueKey('subscriptions-filter-paused')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subscriptions-add-group')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('group-name')), '新分组');
    await tester.tap(find.byKey(const ValueKey('group-save')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('subscriptions-filter-all')),
          )
          .selected,
      isTrue,
    );
    await scrollTo(tester, find.text('新分组'));
    expect(find.text('新分组'), findsOneWidget);
  });

  testWidgets('deleting an empty group skips the migration copy', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer(
      groups: [
        subscriptionGroupJson(id: 1, name: '影音娱乐', sortOrder: 1),
        subscriptionGroupJson(id: 3, name: '空组', sortOrder: 3),
      ],
    );
    await _pumpSubscriptions(tester, server);

    final menu = find.byKey(const ValueKey('subscription-group-menu-3'));
    await scrollTo(tester, menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分组'));
    await tester.pumpAndSettle();
    expect(find.text('删除后不可恢复。'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(
      server.requestsFor('DELETE', '/api/subscription-groups/3'),
      hasLength(1),
    );
    expect(find.text('分组已删除'), findsOneWidget);
    expect(find.text('空组'), findsNothing);
  });

  testWidgets('dark theme keeps the subscription page stable', (tester) async {
    final server = _FakeSubscriptionServer();
    final controllers = await testControllersWithHandler(server.handle);
    await controllers.ledger.loadSubscriptions();
    await pumpWithProviders(
      tester,
      home: const SubscriptionsScreen(),
      controllers: controllers,
      themeMode: ThemeMode.dark,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('每月固定开支'), findsOneWidget);
    expect(find.text('已暂停 · 原扣款日 30 日'), findsOneWidget);
  });

  testWidgets('320dp with 2x text keeps rows and the form usable', (
    tester,
  ) async {
    final server = _FakeSubscriptionServer();
    await _pumpSubscriptions(
      tester,
      server,
      size: const Size(320, 800),
      textScaler: const TextScaler.linear(2),
    );

    await scrollTo(tester, find.byKey(const ValueKey('subscription-body-1')));
    expect(tester.takeException(), isNull);
    final amount = tester.getRect(
      find.byKey(const ValueKey('subscription-amount-1')),
    );
    expect(amount.left, greaterThanOrEqualTo(0));
    expect(amount.right, lessThanOrEqualTo(320));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('subscriptions-add')),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subscriptions-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('subscription-sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final save = tester.getRect(
      find.byKey(const ValueKey('subscription-save')),
    );
    expect(save.bottom, lessThanOrEqualTo(800));
  });
}
