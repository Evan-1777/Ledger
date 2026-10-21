import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:ledger_app/app.dart';
import 'package:ledger_app/core/state/ledger_controller.dart';
import 'package:ledger_app/core/state/preferences_controller.dart';
import 'package:ledger_app/features/auth/session_controller.dart';

import 'support/fakes.dart';

void main() {
  Future<SessionController> lockedSession() async {
    final store = MemorySessionStore();
    final api = fakeApi(
      client: MockClient((_) async => throw StateError('unexpected request')),
      baseUrl: () => store.serverUrl ?? '',
      tokenProvider: store.readToken,
    );
    final session = SessionController(store: store, api: api);
    await session.restore();
    return session;
  }

  testWidgets('LedgerApp shows the connection screen when locked', (
    tester,
  ) async {
    final session = await lockedSession();
    final api = fakeApi(
      client: MockClient((_) async => throw StateError('unexpected request')),
      baseUrl: () => session.serverUrl ?? '',
    );
    final ledger = LedgerController(api: api, onSessionExpired: session.expire);
    final preferences = PreferencesController(MemoryPreferencesStore());

    await tester.pumpWidget(
      LedgerApp(session: session, ledger: ledger, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);
    expect(find.text('管理员密码'), findsOneWidget);
  });

  testWidgets('LedgerApp renders in dark mode', (tester) async {
    final session = await lockedSession();
    final api = fakeApi(
      client: MockClient((_) async => throw StateError('unexpected request')),
      baseUrl: () => session.serverUrl ?? '',
    );
    final ledger = LedgerController(api: api, onSessionExpired: session.expire);
    final preferences = PreferencesController(
      MemoryPreferencesStore(themeMode: ThemeMode.dark),
    );

    await tester.pumpWidget(
      LedgerApp(session: session, ledger: ledger, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.themeMode, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });
}
