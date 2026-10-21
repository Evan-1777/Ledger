import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ledger_app/app.dart';
import 'package:ledger_app/core/widgets/ledger_widgets.dart';
import 'package:ledger_app/features/auth/session_controller.dart';
import 'package:ledger_app/features/stream/stream_screen.dart';

import 'support/harness.dart';

void main() {
  setUpAll(initTestLocale);

  Future<void> mount(WidgetTester tester, TestControllers controllers) async {
    await tester.pumpWidget(
      LedgerApp(
        session: controllers.session,
        ledger: controllers.ledger,
        preferences: controllers.preferences,
      ),
    );
  }

  testWidgets('cold start paints cached data before the network answers', (
    tester,
  ) async {
    final controllers = await testControllers(
      token: 'token',
      cache: seededLedgerCache(),
      client: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return defaultApi(request);
      }),
    );
    await controllers.session.restore();

    await mount(tester, controllers);

    expect(
      find.descendant(
        of: find.byType(StreamScreen),
        matching: find.text('午餐 · 牛肉面'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SkeletonList), findsNothing);
    expect(find.byType(EmptyState), findsNothing);
    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('管理员密码'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('午餐 · 牛肉面'), findsOneWidget);
  });

  testWidgets('cold start without cache keeps skeletons on the first frame', (
    tester,
  ) async {
    final controllers = await testControllers(
      token: 'token',
      client: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return defaultApi(request);
      }),
    );
    await controllers.session.restore();

    await mount(tester, controllers);

    expect(find.byType(SkeletonList), findsWidgets);
    expect(find.byType(EmptyState), findsNothing);
    expect(find.byType(ErrorState), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('午餐 · 牛肉面'), findsOneWidget);
  });

  testWidgets('refresh failure keeps cached data and shows one snackbar', (
    tester,
  ) async {
    final controllers = await testControllers(
      token: 'token',
      cache: seededLedgerCache(),
      client: MockClient((request) async {
        throw http.ClientException('offline');
      }),
    );
    await controllers.session.restore();

    await mount(tester, controllers);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('午餐 · 牛肉面'), findsOneWidget);
    expect(find.text('管理员密码'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('无法连接服务器'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a rejected token returns to the login screen', (tester) async {
    final controllers = await testControllers(
      token: 'token',
      cache: seededLedgerCache(),
      client: MockClient(
        (request) async => jsonResponse({'error': 'unauthorized'}, status: 401),
      ),
    );
    await controllers.session.restore();

    await mount(tester, controllers);
    await tester.pumpAndSettle();

    expect(find.text('管理员密码'), findsOneWidget);
    expect(find.text('午餐 · 牛肉面'), findsNothing);
    expect(controllers.session.phase, SessionPhase.locked);
    expect(await controllers.store.readToken(), isNull);
  });

  testWidgets('resuming revalidates the session and falls back on 401', (
    tester,
  ) async {
    var checks = 0;
    var reject = false;
    final controllers = await testControllers(
      token: 'token',
      cache: seededLedgerCache(),
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/check') {
          checks++;
          return reject
              ? jsonResponse({'error': 'unauthorized'}, status: 401)
              : jsonResponse({'status': 'authenticated'});
        }
        return defaultApi(request);
      }),
    );
    await controllers.session.restore();
    await mount(tester, controllers);
    await tester.pumpAndSettle();

    final before = checks;
    reject = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(checks, before + 1);
    expect(find.text('管理员密码'), findsOneWidget);
    expect(controllers.session.phase, SessionPhase.locked);
  });
}
