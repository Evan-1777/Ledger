import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ledger_app/core/api/api_client.dart';
import 'package:ledger_app/core/api/api_exception.dart';
import 'package:ledger_app/core/api/models.dart';

import '../support/harness.dart';

void main() {
  group('normalizeServerUrl', () {
    test('removes whitespace and the trailing slash', () {
      expect(
        normalizeServerUrl(' https://ledger.example.com/ '),
        'https://ledger.example.com',
      );
      expect(
        normalizeServerUrl('http://192.168.1.8:8080'),
        'http://192.168.1.8:8080',
      );
    });

    test('rejects paths, queries, fragments and non-http schemes', () {
      for (final value in [
        'https://ledger.example.com/api',
        'https://ledger.example.com?x=1',
        'https://ledger.example.com#x',
        'ftp://ledger.example.com',
        'ledger.example.com',
        '',
        'https://ledger example.com',
      ]) {
        expect(
          () => normalizeServerUrl(value),
          throwsA(
            isA<ApiException>().having(
              (error) => error.kind,
              'kind',
              ApiErrorKind.invalidServer,
            ),
          ),
        );
      }
    });
  });

  test('login posts the password and returns the token', () async {
    late http.Request captured;
    final api = ApiClient(
      client: MockClient((request) async {
        captured = request;
        return jsonResponse({'token': 'signed-token', 'expires_at': 123});
      }),
      baseUrl: () => 'https://ledger.test',
      tokenProvider: () async => null,
    );

    final result = await api.login('secret');

    expect(result.token, 'signed-token');
    expect(captured.url.toString(), 'https://ledger.test/api/auth/login');
    expect(captured.headers['Content-Type'], 'application/json');
    expect(jsonDecode(captured.body), {'password': 'secret'});
    expect(captured.headers.containsKey('Authorization'), isFalse);
  });

  test('protected requests carry the bearer token', () async {
    late http.Request captured;
    final api = ApiClient(
      client: MockClient((request) async {
        captured = request;
        return jsonResponse([]);
      }),
      baseUrl: () => 'https://ledger.test',
      tokenProvider: () async => 'token-123',
    );

    await api.getCategories();

    expect(captured.headers['Authorization'], 'Bearer token-123');
    expect(captured.url.path, '/api/categories');
  });

  test('401 is mapped to an unauthorized error', () async {
    final api = ApiClient(
      client: MockClient(
        (_) async => jsonResponse({'error': 'unauthorized'}, status: 401),
      ),
      baseUrl: () => 'https://ledger.test',
      tokenProvider: () async => 'token',
    );

    await expectLater(
      api.getTransactions(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.kind, 'kind', ApiErrorKind.unauthorized)
            .having((error) => error.statusCode, 'status', 401),
      ),
    );
  });

  test('409 keeps the server message', () async {
    final api = ApiClient(
      client: MockClient(
        (_) async => jsonResponse({'error': '该消费类型已有关联账单，禁止删除'}, status: 409),
      ),
      baseUrl: () => 'https://ledger.test',
      tokenProvider: () async => 'token',
    );

    await expectLater(
      api.deleteCategory(1),
      throwsA(
        isA<ApiException>()
            .having((error) => error.kind, 'kind', ApiErrorKind.conflict)
            .having((error) => error.message, 'message', '该消费类型已有关联账单，禁止删除'),
      ),
    );
  });

  test('timeout is mapped without losing the token', () async {
    final api = ApiClient(
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return jsonResponse({});
      }),
      baseUrl: () => 'https://ledger.test',
      tokenProvider: () async => 'token',
      timeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      api.checkAuth(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiErrorKind.timeout,
        ),
      ),
    );
  });

  test('invalid JSON is mapped to an invalid response', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response('<html>', 200)),
      baseUrl: () => 'https://ledger.test',
      tokenProvider: () async => null,
    );

    await expectLater(
      api.getStatsSummary(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('transaction list sends type and limit filters', () async {
    late http.Request captured;
    final api = ApiClient(
      client: MockClient((request) async {
        captured = request;
        return jsonResponse([transactionJson()]);
      }),
      baseUrl: () => 'https://ledger.test',
      tokenProvider: () async => 'token',
    );

    final list = await api.getTransactions(type: TransactionType.expense);

    expect(list.single.amountCents, -2800);
    expect(captured.url.queryParameters, {'limit': '100', 'type': 'expense'});
  });

  test('expense body omits fee and transfer body keeps both', () async {
    final bodies = <Map<String, dynamic>>[];
    final api = ApiClient(
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return jsonResponse(transactionJson());
      }),
      baseUrl: () => 'https://ledger.test',
      tokenProvider: () async => 'token',
    );

    await api.createTransaction(
      TransactionInput(
        type: TransactionType.expense,
        amount: -12.5,
        description: '午餐',
        paymentMethodId: 1,
        categoryId: 1,
        tagId: 1,
        transactedAt: DateTime.utc(2026, 10, 19, 4, 42),
      ),
    );
    await api.createTransaction(
      TransactionInput(
        type: TransactionType.transfer,
        amount: 100,
        fee: 1.5,
        description: '转账',
        paymentMethodId: 1,
        sourcePaymentMethodId: 2,
        categoryId: 0,
        tagId: 0,
        transactedAt: DateTime.utc(2026, 10, 19, 4, 42),
      ),
    );

    expect(bodies[0].containsKey('fee'), isFalse);
    expect(bodies[0].containsKey('source_payment_method_id'), isFalse);
    expect(bodies[1]['fee'], 1.5);
    expect(bodies[1]['source_payment_method_id'], 2);
    expect(bodies[1]['transacted_at'], '2026-10-19T04:42:00.000Z');
  });

  test('tag update always includes the current sort order', () async {
    late http.Request captured;
    final api = ApiClient(
      client: MockClient((request) async {
        captured = request;
        return jsonResponse({
          'id': 7,
          'category_id': 1,
          'name': '晚餐',
          'sort_order': 3,
          'created_at': '',
        });
      }),
      baseUrl: () => 'https://ledger.test',
      tokenProvider: () async => 'token',
    );

    await api.updateTag(7, name: '晚餐', sortOrder: 3);

    expect(jsonDecode(captured.body), {'name': '晚餐', 'sort_order': 3});
  });
}
