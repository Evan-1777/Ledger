import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_app/features/auth/login_screen.dart';
import 'package:ledger_app/features/auth/session_controller.dart';

import '../support/harness.dart';

void main() {
  setUpAll(initTestLocale);

  Future<TestControllers> locked({
    Future<http.Response> Function(http.Request)? handler,
    String? serverUrl,
  }) async {
    final controllers = await testControllersWithHandler(
      handler ?? (_) async => jsonResponse({'token': 'token', 'expires_at': 1}),
      serverUrl: serverUrl,
    );
    await controllers.session.logout();
    return controllers;
  }

  testWidgets('empty fields are validated inline', (tester) async {
    final controllers = await locked();
    await pumpWithProviders(
      tester,
      home: const LoginScreen(),
      controllers: controllers,
      scaffold: false,
    );

    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pump();

    expect(find.text('请输入服务器地址'), findsOneWidget);
  });

  testWidgets('invalid address and empty password are reported', (
    tester,
  ) async {
    final controllers = await locked();
    await pumpWithProviders(
      tester,
      home: const LoginScreen(),
      controllers: controllers,
      scaffold: false,
    );

    await tester.enterText(find.byType(TextField).at(0), 'ledger.example.com');
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pump();
    expect(find.text('请输入管理员密码'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pumpAndSettle();
    expect(find.textContaining('仅填协议'), findsOneWidget);
  });

  testWidgets('wrong password shows an inline error', (tester) async {
    final controllers = await locked(
      handler: (_) async =>
          jsonResponse({'error': 'invalid password'}, status: 401),
    );
    await pumpWithProviders(
      tester,
      home: const LoginScreen(),
      controllers: controllers,
      scaffold: false,
    );

    await tester.enterText(find.byType(TextField).at(0), 'https://ledger.test');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pumpAndSettle();

    expect(find.text('密码错误'), findsOneWidget);
    expect(controllers.session.phase, isNot(SessionPhase.authenticated));
  });

  testWidgets('unreachable server shows a connection error', (tester) async {
    final controllers = await locked(
      handler: (_) async => throw http.ClientException('offline'),
    );
    await pumpWithProviders(
      tester,
      home: const LoginScreen(),
      controllers: controllers,
      scaffold: false,
    );

    await tester.enterText(find.byType(TextField).at(0), 'https://ledger.test');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('无法连接服务器'), findsOneWidget);
  });

  testWidgets('successful login authenticates the session', (tester) async {
    final controllers = await locked();
    await pumpWithProviders(
      tester,
      home: const LoginScreen(),
      controllers: controllers,
      scaffold: false,
    );

    await tester.enterText(
      find.byType(TextField).at(0),
      'https://ledger.test/',
    );
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pumpAndSettle();

    expect(controllers.session.phase, SessionPhase.authenticated);
    expect(controllers.store.serverUrl, 'https://ledger.test');
    expect(await controllers.store.readToken(), 'token');
  });
}
