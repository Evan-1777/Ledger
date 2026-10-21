import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ledger_app/features/auth/session_controller.dart';

import '../support/harness.dart';

void main() {
  test('restore without a token locks the app', () async {
    final controllers = await testControllers(
      token: null,
      serverUrl: null,
      client: MockClient((_) async => jsonResponse({})),
    );

    await controllers.session.restore();

    expect(controllers.session.phase, SessionPhase.locked);
  });

  test('restore with a valid token authenticates', () async {
    final controllers = await testControllers(
      token: 'token',
      client: MockClient(
        (_) async => jsonResponse({'status': 'authenticated'}),
      ),
    );

    await controllers.session.restore();

    expect(controllers.session.phase, SessionPhase.authenticated);
  });

  test('restore opens the shell before the network answers', () async {
    final pending = Completer<http.Response>();
    final controllers = await testControllers(
      token: 'token',
      client: MockClient((_) => pending.future),
    );

    await controllers.session.restore();

    expect(controllers.session.phase, SessionPhase.authenticated);

    pending.complete(jsonResponse({'status': 'authenticated'}));
    await pumpEventQueue();
    expect(controllers.session.phase, SessionPhase.authenticated);
  });

  test('restore with an expired token clears it in the background', () async {
    final pending = Completer<http.Response>();
    final controllers = await testControllers(
      token: 'expired',
      client: MockClient((_) => pending.future),
    );

    await controllers.session.restore();

    expect(controllers.session.phase, SessionPhase.authenticated);
    expect(await controllers.store.readToken(), 'expired');

    pending.complete(jsonResponse({'error': 'unauthorized'}, status: 401));
    await pumpEventQueue();

    expect(controllers.session.phase, SessionPhase.locked);
    expect(await controllers.store.readToken(), isNull);
  });

  test('a background network failure keeps the optimistic session', () async {
    final controllers = await testControllers(
      token: 'kept',
      client: MockClient((_) async {
        throw http.ClientException('offline');
      }),
    );

    await controllers.session.restore();

    expect(controllers.session.phase, SessionPhase.authenticated);
    await pumpEventQueue();
    expect(controllers.session.phase, SessionPhase.authenticated);
    expect(await controllers.store.readToken(), 'kept');
  });

  test('login stores the normalized address and the token', () async {
    late http.Request captured;
    final controllers = await testControllers(
      serverUrl: null,
      client: MockClient((request) async {
        captured = request;
        return jsonResponse({'token': 'new-token', 'expires_at': 1});
      }),
    );

    final ok = await controllers.session.login(
      ' https://ledger.example.com/ ',
      'secret',
    );

    expect(ok, isTrue);
    expect(controllers.session.phase, SessionPhase.authenticated);
    expect(controllers.store.serverUrl, 'https://ledger.example.com');
    expect(await controllers.store.readToken(), 'new-token');
    expect(
      captured.url.toString(),
      'https://ledger.example.com/api/auth/login',
    );
  });

  test('wrong password keeps the previous token', () async {
    final controllers = await testControllers(
      token: 'old-token',
      client: MockClient(
        (_) async => jsonResponse({'error': 'invalid password'}, status: 401),
      ),
    );

    final ok = await controllers.session.login('https://ledger.test', 'wrong');

    expect(ok, isFalse);
    expect(controllers.session.loginError, '密码错误');
    expect(await controllers.store.readToken(), 'old-token');
  });

  test('login network failure shows a connection message', () async {
    final controllers = await testControllers(
      client: MockClient((_) async {
        throw http.ClientException('offline');
      }),
    );

    final ok = await controllers.session.login('https://ledger.test', 'pw');

    expect(ok, isFalse);
    expect(controllers.session.loginError, contains('无法连接服务器'));
  });

  test('invalid address is rejected before any request', () async {
    var called = false;
    final controllers = await testControllers(
      client: MockClient((_) async {
        called = true;
        return jsonResponse({});
      }),
    );

    final ok = await controllers.session.login(
      'https://ledger.test/path',
      'pw',
    );

    expect(ok, isFalse);
    expect(controllers.session.loginError, contains('服务器地址'));
    expect(called, isFalse);
  });

  test('the next request after switching server uses the new host', () async {
    late http.Request captured;
    final controllers = await testControllers(
      token: 'old-token',
      serverUrl: 'https://old.example.com',
      client: MockClient((request) async {
        captured = request;
        return jsonResponse([]);
      }),
    );

    final ok = await controllers.session.updateServer(
      'https://new.example.com',
    );
    await controllers.api.getCategories();

    expect(ok, isTrue);
    expect(captured.url.host, 'new.example.com');
    expect(captured.url.path, '/api/categories');
    expect(await controllers.store.readToken(), isNull);
  });

  test('changing the server clears the token and locks', () async {
    final controllers = await testControllers(
      token: 'old-token',
      client: MockClient((_) async => jsonResponse({})),
    );

    final ok = await controllers.session.updateServer(
      'https://other.example.com',
    );

    expect(ok, isTrue);
    expect(controllers.store.serverUrl, 'https://other.example.com');
    expect(await controllers.store.readToken(), isNull);
    expect(controllers.session.phase, SessionPhase.locked);
  });

  test('logout clears the token but keeps the server address', () async {
    final controllers = await testControllers(token: 'token');

    await controllers.session.logout();

    expect(await controllers.store.readToken(), isNull);
    expect(controllers.store.serverUrl, 'https://ledger.test');
    expect(controllers.session.phase, SessionPhase.locked);
  });
}
